/*
 * ============================================================
 *  CrayCare — ESP32 Multi-Sensor Monitor + Firebase RTDB
 *  Board   : ESP32 DevKit
 *  Flow    : Flutter App writes config -> ESP32 reads config
 *            ESP32 writes sensor values only -> Flutter reads
 * ============================================================
 *
 *  MINIMAL FIREBASE PAYLOAD — only raw sensor values.
 *  Zones, status, thresholds are computed by the Flutter app.
 *
 *  TURBIDITY — NTU conversion based on field calibration:
 *    1.50V =   0 NTU (clear water)
 *    1.40V = 500 NTU (dirty water)
 *    NTU = (turbidityVClear - voltage) * 500 / (turbidityVClear - turbidityVDirty)
 *
 * Active sensors now:
 *  1. Temperature       : DS18B20
 *  2. Turbidity         : DFRobot SEN0189
 *
 * Placeholder sensors added:
 *  3. Dissolved Oxygen  : analog placeholder
 *  4. pH Level          : analog placeholder
 *  5. Water Level       : analog placeholder
 *
 * Arduino IDE libraries needed:
 *  1. Firebase ESP Client by Mobizt
 *  2. OneWire
 *  3. DallasTemperature
 *  4. Preferences (built-in)
 *
 * WiFi credentials: stored in NVS via Preferences.
 *   First boot: enter via Serial Monitor.
 *   Reset: send "RESET_WIFI" over Serial.
 *
 * Firebase paths:
 *  /sensor_readings/latest   -> overwritten every 5s (1 record)
 *  /sensor_readings/history  -> pushed every 60s (for time-series)
 *  /sensor_readings/config   -> threshold config written by Flutter app
 */

#include <WiFi.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <Firebase_ESP_Client.h>

#include <Preferences.h>
#include <time.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// ============================================================
//  WIFI SETTINGS — stored in NVS via Preferences
//  First boot: enter SSID + password over Serial Monitor
//  Reset: send "RESET_WIFI" via Serial
// ============================================================
Preferences prefs;
String ssid;
String pass;

// ============================================================
//  FIREBASE SETTINGS
// ============================================================
#define FIREBASE_API_KEY "AIzaSyCjDOkzE4iubiLx_xA2YufMUMo6jgIKcaw"
#define FIREBASE_DATABASE_URL "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app"

#define FIREBASE_LATEST_PATH   "/sensor_readings/latest"
#define FIREBASE_HISTORY_PATH  "/sensor_readings/history"
#define FIREBASE_CONFIG_PATH   "/sensor_readings/config"

// ESP / Feeder Firebase paths
#define FIREBASE_ESP_PATH              "/esp"
#define FIREBASE_FEEDER_COMMANDS_PATH  "/feeder/commands"
#define FIREBASE_FEEDER_STATUS_PATH    "/feeder/status"
#define FIREBASE_FEEDER_SCHEDULES_PATH "/feeder/schedules"
#define FIREBASE_FEEDER_LOGS_PATH      "/feeder/logs"

#define FIREBASE_SEND_INTERVAL_MS 5000
#define HISTORY_SEND_INTERVAL_MS 60000
#define CONFIG_SYNC_INTERVAL_MS 10000
#define SENSOR_POLL_MS 500

// Feeder timing
#define FEEDER_CMD_INTERVAL_MS 300
#define FEEDER_STATUS_INTERVAL_MS 5000
#define FEEDER_SCHEDULE_SYNC_MS 30000
#define FEEDER_SCHEDULE_CHECK_MS 1000
#define FEEDER_SERVO_PULSE_WIDTH 2000   // microseconds for full rotation
#define FEEDER_MAX_SCHEDULES 20

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

bool firebaseReady = false;
unsigned long lastFirebaseSendTime = 0;
unsigned long lastHistorySendTime = 0;
unsigned long lastConfigSyncTime = 0;
unsigned long lastPollTime = 0;

// Feeder state
// LEDC servo control (no ESP32Servo library needed — avoid timer conflicts)
#define SERVO_LEDC_CHANNEL 0
#define SERVO_LEDC_FREQ 50
#define SERVO_LEDC_RESOLUTION 16
#define SERVO_PULSE_MIN 500
#define SERVO_PULSE_MAX 2500

int _servoAngleToDuty(int angle) {
  angle = constrain(angle, 0, 180);
  int pulseWidth = map(angle, 0, 180, SERVO_PULSE_MIN, SERVO_PULSE_MAX);
  // duty = pulseWidth / period(20000µs) * maxDuty(65535)
  return (int)((float)pulseWidth / 20000.0f * 65535.0f);
}

void _setServoAngle(int angle) {
  ledcWrite(SERVO_LEDC_CHANNEL, _servoAngleToDuty(angle));
}

bool feederAutoMode = true;
int feederHopperLevel = 100;          // percentage 0-100
unsigned long feederLastFeedEpoch = 0;
bool feederIsRunning = false;
String feederFeedSource = "";          // "manual" or "scheduled"

// Non-blocking feeder state machine
enum FeederRunState {
  FEEDER_IDLE,
  FEEDER_FORWARD,
  FEEDER_PAUSE_F,
  FEEDER_BACKWARD,
  FEEDER_PAUSE_B,
  FEEDER_DONE
};
FeederRunState feederRunState = FEEDER_IDLE;
int feederCurrentCycle = 0;
int feederMaxCycles = 1;               // number of back-and-forth sweeps
unsigned long feederStepMs = 0;
unsigned long feederStartMs = 0;

struct FeedSchedule {
  String key;
  int hour24;
  int minute;
  bool enabled;
};

int feederScheduleCount = 0;
FeedSchedule feederSchedules[FEEDER_MAX_SCHEDULES];

unsigned long lastFeederCmdCheckMs = 0;
unsigned long lastFeederStatusMs = 0;
unsigned long lastFeederScheduleSyncMs = 0;
unsigned long lastFeederScheduleCheckMs = 0;

// ============================================================
//  PINS
// ============================================================
#define TEMP_PIN 4
#define TURBIDITY_PIN 34
#define DO_PIN 35
#define PH_PIN 32
#define WATER_LEVEL_PIN 33

// Feeder
#define FEEDER_SERVO_PIN 13
#define FEEDER_HOPPER_SENSOR_PIN 36   // optional: load cell / level sensor

// Set these to 1 after the actual sensor modules are connected and calibrated.
#define ENABLE_DO_SENSOR 0
#define ENABLE_PH_SENSOR 0
#define ENABLE_WATER_LEVEL_SENSOR 0

// ============================================================
//  CALIBRATED TURBIDITY THRESHOLDS
//  Recalibrated: clear water ~1.52V, dirty ~1.40V, air <1.30V
//  ESP32 sends turbidityAir flag so Flutter shows "--" when no water.
// ============================================================
float turbidityVClear = 1.50;          // Voltage for clear water (0 NTU)
float turbidityVDirty = 1.40;          // Voltage for very dirty water (500 NTU)
float turbidityVAirMax = 1.30;         // Below this voltage = air/no water

float tempCriticalLow = 24.0;
float tempCriticalHigh = 30.0;

float turbNtuMin = 0.0;
float turbNtuMax = 40.0;

float doCriticalLow = 4.0;
float doCriticalHigh = 12.0;

float phCriticalLow = 7.0;
float phCriticalHigh = 8.5;

float waterLevelCriticalLow = 30.0;
float waterLevelCriticalHigh = 95.0;

float doVoltageScale = 4.0;
float doVoltageOffset = 0.0;
float phVoltageSlope = -5.70;
float phVoltageIntercept = 21.34;
float waterLevelVoltageMin = 0.0;
float waterLevelVoltageMax = 3.3;

// ============================================================
//  SAMPLING / FILTERING SETTINGS
// ============================================================
#define SMOOTH_WINDOW 10
#define SAMPLE_COUNT 50
#define SAMPLE_DELAY_MS 5

#define TEMP_JUMP_MAX 3.0
#define TURB_NTU_JUMP_MAX 100.0
#define MIN_VALID_TEMP -10.0
#define MAX_VALID_TEMP 60.0
#define MAX_SKIP_COUNT 10

#define NTU_MAX 1000.0

// ============================================================
//  SENSOR OBJECTS
// ============================================================
OneWire oneWire(TEMP_PIN);
DallasTemperature sensors(&oneWire);

// ============================================================
//  SENSOR STATES
// ============================================================
float tempBuffer[SMOOTH_WINDOW];
uint8_t tempCount = 0;
uint8_t tempIndex = 0;
float smoothedTemp = -127.0;
float lastValidTemp = -127.0;
bool tempSensorOK = false;
uint8_t tempSkipCount = 0;

float turbidityBuffer[SMOOTH_WINDOW];
uint8_t turbidityCount = 0;
uint8_t turbidityIndex = 0;
float smoothedTurbidityNTU = 0.0;
float lastValidTurbidityNTU = -1.0;
bool turbiditySensorOK = false;
uint8_t turbiditySkipCount = 0;
float turbidityVoltage = 0.0;

float dissolvedOxygen = -1.0;
float dissolvedOxygenVoltage = 0.0;
bool doSensorOK = false;

float phLevel = -1.0;
float phVoltage = 0.0;
bool phSensorOK = false;

float waterLevelPercent = -1.0;
float waterLevelVoltage = 0.0;
bool waterLevelSensorOK = false;

struct TurbidityResult {
  float ntu;
  bool valid;
};

// ============================================================
//  GENERIC HELPERS
// ============================================================
float readAnalogVoltage(uint8_t pin) {
  long sum = 0;

  for (int i = 0; i < SAMPLE_COUNT; i++) {
    sum += analogRead(pin);
    delay(SAMPLE_DELAY_MS);
  }

  float avg = (float)sum / SAMPLE_COUNT;
  return avg * (3.3f / 4095.0f);
}

float computeAverage(float buffer[], uint8_t count) {
  if (count == 0) return 0.0;

  float sum = 0.0;
  uint8_t n = min(count, (uint8_t)SMOOTH_WINDOW);

  for (uint8_t i = 0; i < n; i++) {
    sum += buffer[i];
  }

  return sum / n;
}

unsigned long getEpochMillis() {
  time_t now;
  time(&now);

  if (now < 1700000000) return 0;

  return (unsigned long)now * 1000UL;
}

// ============================================================
//  TURBIDITY: VOLTAGE -> NTU CONVERSION
//  Based on calibrated field data:
//    1.6V =   0 NTU  (clear water)
//    1.4V = 500 NTU  (dirty)
//    NTU = (turbidityVClear - voltage) * 2500
// ============================================================
TurbidityResult classifyTurbidity(float v) {
  TurbidityResult r;

  if (v < turbidityVAirMax) {
    r.ntu = 0.0;
    r.valid = false;
    return r;
  }

  r.ntu = (turbidityVClear - v) * 500.0f / (turbidityVClear - turbidityVDirty);
  r.ntu = constrain(r.ntu, 0.0f, NTU_MAX);
  r.valid = true;

  return r;
}

// For serial debug only
String getTempZone(float t) {
  if (!tempSensorOK || t < -100.0) return "SENSOR ERROR";
  if (t < tempCriticalLow) return "CRITICAL LOW";
  if (t > tempCriticalHigh) return "CRITICAL HIGH";
  return "OPTIMAL";
}

// ============================================================
//  WIFI / FIREBASE
// ============================================================
void connectWiFi() {
  prefs.begin("wifi", true);
  ssid = prefs.getString("ssid", "");
  pass = prefs.getString("pass", "");
  prefs.end();

  // First boot — prompt for credentials via Serial
  if (ssid == "") {
    Serial.println("\n=== WIFI SETUP ===");
    Serial.println("Enter SSID:");
    while (!Serial.available()) delay(100);
    ssid = Serial.readStringUntil('\n');
    ssid.trim();
    Serial.println(">> " + ssid);
    Serial.println("Enter PASSWORD:");
    while (!Serial.available()) delay(100);
    pass = Serial.readStringUntil('\n');
    pass.trim();
    prefs.begin("wifi", false);
    prefs.putString("ssid", ssid);
    prefs.putString("pass", pass);
    prefs.end();
    Serial.println("[SAVED] Restarting...");
    delay(1500);
    ESP.restart();
  }

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(ssid.c_str(), pass.c_str());

  Serial.print("[WIFI] Connecting");

  int retries = 40;
  while (WiFi.status() != WL_CONNECTED && retries-- > 0) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println();
    Serial.print("Connected! IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println(" FAILED — check SSID/password or network availability");
    Serial.println("Type RESET_WIFI to reconfigure");
  }
}

void initTime() {
  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");

  Serial.print("Syncing time");
  for (int i = 0; i < 20; i++) {
    time_t now;
    time(&now);

    if (now > 1700000000) {
      Serial.println(" OK");
      return;
    }

    Serial.print(".");
    delay(500);
  }

  Serial.println(" skipped");
}

void connectFirebase() {
  config.api_key = FIREBASE_API_KEY;
  config.database_url = FIREBASE_DATABASE_URL;
  config.token_status_callback = tokenStatusCallback;

  Firebase.reconnectWiFi(true);

  Serial.print("Signing in to Firebase anonymously... ");

  if (Firebase.signUp(&config, &auth, "", "")) {
    firebaseReady = true;
    Serial.println("OK");
  } else {
    firebaseReady = false;
    Serial.printf("FAILED: %s\n", config.signer.signupError.message.c_str());
  }

  Firebase.begin(&config, &auth);
  Firebase.setDoubleDigits(2);
}

bool readConfigFloatPath(const char* relativePath, float &target, float minValue, float maxValue) {
  String path = String(FIREBASE_CONFIG_PATH) + "/" + relativePath;

  if (!Firebase.RTDB.getFloat(&fbdo, path.c_str())) {
    return false;
  }

  float value = fbdo.floatData();

  if (!isfinite(value) || value < minValue || value > maxValue) {
    Serial.printf("[CONFIG SKIP] %s invalid value: %.3f\n", relativePath, value);
    return false;
  }

  target = value;
  return true;
}

bool readRangeConfig(const char* sensorKey, float &lowTarget, float &highTarget, float minLimit, float maxLimit) {
  float newLow = lowTarget;
  float newHigh = highTarget;

  String minPath = String("ranges/") + sensorKey + "/min";
  String maxPath = String("ranges/") + sensorKey + "/max";

  bool gotMin = readConfigFloatPath(minPath.c_str(), newLow, minLimit, maxLimit);
  bool gotMax = readConfigFloatPath(maxPath.c_str(), newHigh, minLimit, maxLimit);

  if (!gotMin && !gotMax) return false;

  if (newLow >= newHigh) {
    Serial.printf("[CONFIG SKIP] ranges/%s min must be lower than max\n", sensorKey);
    return false;
  }

  lowTarget = newLow;
  highTarget = newHigh;
  return true;
}

bool ensureFirebaseReady();

// ============================================================
//  CONFIG SYNC — Read threshold config from Firebase
// ============================================================
void syncConfigFromFirebase() {
  if (!ensureFirebaseReady()) return;

  float oldTempLow = tempCriticalLow;
  float oldTempHigh = tempCriticalHigh;
  float oldTurbidityVClear = turbidityVClear;
  float oldTurbidityVDirty = turbidityVDirty;
  float oldTurbidityVAirMax = turbidityVAirMax;
  float oldTurbNtuMin = turbNtuMin;
  float oldTurbNtuMax = turbNtuMax;
  float oldDOLow = doCriticalLow;
  float oldDOHigh = doCriticalHigh;
  float oldPHLow = phCriticalLow;
  float oldPHHigh = phCriticalHigh;
  float oldWaterLow = waterLevelCriticalLow;
  float oldWaterHigh = waterLevelCriticalHigh;

  bool gotAny = false;

  gotAny |= readRangeConfig("temp", tempCriticalLow, tempCriticalHigh, 0.0, 50.0);
  gotAny |= readRangeConfig("turb", turbNtuMin, turbNtuMax, 0.0, 1000.0);
  gotAny |= readRangeConfig("do", doCriticalLow, doCriticalHigh, 0.0, 30.0);
  gotAny |= readRangeConfig("ph", phCriticalLow, phCriticalHigh, 0.0, 14.0);
  gotAny |= readRangeConfig("waterlevel", waterLevelCriticalLow, waterLevelCriticalHigh, 0.0, 100.0);

  gotAny |= readConfigFloatPath("tempCriticalLow", tempCriticalLow, 0.0, 50.0);
  gotAny |= readConfigFloatPath("tempCriticalHigh", tempCriticalHigh, 0.0, 50.0);

  gotAny |= readConfigFloatPath("turbidityVClear", turbidityVClear, 0.0, 3.3);
  gotAny |= readConfigFloatPath("turbidityVDirty", turbidityVDirty, 0.0, 3.3);
  gotAny |= readConfigFloatPath("turbidityVAirMax", turbidityVAirMax, 0.0, 3.3);

  gotAny |= readConfigFloatPath("doCriticalLow", doCriticalLow, 0.0, 30.0);
  gotAny |= readConfigFloatPath("doCriticalHigh", doCriticalHigh, 0.0, 30.0);

  gotAny |= readConfigFloatPath("phCriticalLow", phCriticalLow, 0.0, 14.0);
  gotAny |= readConfigFloatPath("phCriticalHigh", phCriticalHigh, 0.0, 14.0);

  gotAny |= readConfigFloatPath("waterLevelCriticalLow", waterLevelCriticalLow, 0.0, 100.0);
  gotAny |= readConfigFloatPath("waterLevelCriticalHigh", waterLevelCriticalHigh, 0.0, 100.0);

  gotAny |= readConfigFloatPath("doVoltageScale", doVoltageScale, -100.0, 100.0);
  gotAny |= readConfigFloatPath("doVoltageOffset", doVoltageOffset, -100.0, 100.0);
  gotAny |= readConfigFloatPath("phVoltageSlope", phVoltageSlope, -100.0, 100.0);
  gotAny |= readConfigFloatPath("phVoltageIntercept", phVoltageIntercept, -100.0, 100.0);
  gotAny |= readConfigFloatPath("waterLevelVoltageMin", waterLevelVoltageMin, 0.0, 3.3);
  gotAny |= readConfigFloatPath("waterLevelVoltageMax", waterLevelVoltageMax, 0.0, 3.3);

  bool invalidConfig = false;

  if (tempCriticalLow >= tempCriticalHigh) {
    invalidConfig = true;
    Serial.println("[CONFIG SKIP] tempCriticalLow must be lower than tempCriticalHigh");
  }

  if (turbidityVDirty >= turbidityVClear) {
    invalidConfig = true;
    Serial.println("[CONFIG SKIP] turbidityVDirty must be lower than turbidityVClear");
  }

  if (turbNtuMin >= turbNtuMax) {
    invalidConfig = true;
    Serial.println("[CONFIG SKIP] ranges/turb min must be lower than max");
  }

  if (doCriticalLow >= doCriticalHigh) {
    invalidConfig = true;
    Serial.println("[CONFIG SKIP] doCriticalLow must be lower than doCriticalHigh");
  }

  if (phCriticalLow >= phCriticalHigh) {
    invalidConfig = true;
    Serial.println("[CONFIG SKIP] phCriticalLow must be lower than phCriticalHigh");
  }

  if (waterLevelCriticalLow >= waterLevelCriticalHigh) {
    invalidConfig = true;
    Serial.println("[CONFIG SKIP] waterLevelCriticalLow must be lower than waterLevelCriticalHigh");
  }

  if (waterLevelVoltageMin >= waterLevelVoltageMax) {
    invalidConfig = true;
    Serial.println("[CONFIG SKIP] waterLevelVoltageMin must be lower than waterLevelVoltageMax");
  }

  if (invalidConfig) {
    tempCriticalLow = oldTempLow;
    tempCriticalHigh = oldTempHigh;
    turbidityVClear = oldTurbidityVClear;
    turbidityVDirty = oldTurbidityVDirty;
    turbidityVAirMax = oldTurbidityVAirMax;
    turbNtuMin = oldTurbNtuMin;
    turbNtuMax = oldTurbNtuMax;
    doCriticalLow = oldDOLow;
    doCriticalHigh = oldDOHigh;
    phCriticalLow = oldPHLow;
    phCriticalHigh = oldPHHigh;
    waterLevelCriticalLow = oldWaterLow;
    waterLevelCriticalHigh = oldWaterHigh;
    return;
  }

  if (!gotAny) {
    Serial.println("[CONFIG] No Firebase config found. Using defaults.");
    return;
  }

  Serial.printf("[CONFIG] Temp %.1f-%.1f C | Turb %.0f-%.0f NTU | DO %.1f-%.1f mg/L | pH %.1f-%.1f | Water %.1f-%.1f%%\n",
                tempCriticalLow,
                tempCriticalHigh,
                turbNtuMin,
                turbNtuMax,
                doCriticalLow,
                doCriticalHigh,
                phCriticalLow,
                phCriticalHigh,
                waterLevelCriticalLow,
                waterLevelCriticalHigh);
}

// ============================================================
//  FIREBASE READY CHECK — Re-auth if token expired
// ============================================================
bool ensureFirebaseReady() {
  if (!firebaseReady) return false;
  if (Firebase.ready()) return true;
  Serial.println("[FIREBASE] Token expired, re-authenticating...");
  if (Firebase.signUp(&config, &auth, "", "")) {
    firebaseReady = true;
    Serial.println("[FIREBASE] Re-auth OK");
    return true;
  }
  Serial.printf("[FIREBASE] Re-auth failed: %s\n", config.signer.signupError.message.c_str());
  return false;
}

// ============================================================
//  FIREBASE CONFIG PUSH — ESP32 sends calibration to Firebase
// ============================================================
void sendConfigToFirebase() {
  if (!ensureFirebaseReady()) return;
  FirebaseJson cfg;
  cfg.set("turbidityVClear", turbidityVClear);
  cfg.set("turbidityVDirty", turbidityVDirty);
  cfg.set("turbidityVAirMax", turbidityVAirMax);
  if (Firebase.RTDB.updateNode(&fbdo, FIREBASE_CONFIG_PATH, &cfg)) {
    Serial.println("[CONFIG PUSH] Calibration sent to Firebase");
  } else {
    Serial.printf("[CONFIG PUSH] Failed: %s\n", fbdo.errorReason().c_str());
  }
}

// ============================================================
//  FIREBASE JSON — MINIMAL PAYLOAD
//  Only raw sensor values. Flutter computes zones & status.
//  Turbidity is sent as NTU (Nephelometric Turbidity Units).
// ============================================================
void buildMinimalJson(FirebaseJson &json, bool includeTimestamp) {

  json.set("temperature", smoothedTemp);
  if (turbiditySensorOK) {
    json.set("turbidityAir", false);
    json.set("turbidity", smoothedTurbidityNTU);
  } else {
    json.set("turbidityAir", true);
    json.set("turbidity", 0);
  }

  if (ENABLE_DO_SENSOR) {
    json.set("dissolvedOxygen", dissolvedOxygen);
  }

  if (ENABLE_PH_SENSOR) {
    json.set("phLevel", phLevel);
  }

  if (ENABLE_WATER_LEVEL_SENSOR) {
    json.set("waterLevelPercent", waterLevelPercent);
  }

  if (includeTimestamp) {
    json.set("timestamp", getEpochMillis());
  }
}

void sendLatestToFirebase() {
  if (!ensureFirebaseReady()) return;

  FirebaseJson json;
  buildMinimalJson(json, false);

  if (Firebase.RTDB.updateNode(&fbdo, FIREBASE_LATEST_PATH, &json)) {
    Serial.println("[FIREBASE] Latest sent");
  } else {
    Serial.printf("[FIREBASE ERROR] %s\n", fbdo.errorReason().c_str());
  }
}

void sendEspLastSeen() {
  if (!ensureFirebaseReady()) return;
  time_t now;
  time(&now);
  unsigned long epochMs = (now > 1700000000) ? (unsigned long)now * 1000UL : 0;
  if (epochMs == 0) return;

  if (Firebase.RTDB.setInt(&fbdo, FIREBASE_ESP_PATH "/lastSeen", (int)epochMs)) {
    // success
  } else if (fbdo.httpConnected()) {
    Serial.printf("[ESP STATUS ERROR] %s\n", fbdo.errorReason().c_str());
  }
}

void sendHistoryToFirebase() {
  if (!ensureFirebaseReady()) return;

  FirebaseJson json;
  buildMinimalJson(json, true);

  if (Firebase.RTDB.pushJSON(&fbdo, FIREBASE_HISTORY_PATH, &json)) {
    Serial.println("[FIREBASE] History saved");
  } else {
    Serial.printf("[FIREBASE HISTORY ERROR] %s\n", fbdo.errorReason().c_str());
  }
}

// ============================================================
//  SENSOR PRIMING
// ============================================================
void primeTemperatureBuffer() {
  sensors.requestTemperatures();
  float ft = sensors.getTempCByIndex(0);

  if (ft > MIN_VALID_TEMP && ft < MAX_VALID_TEMP) {
    lastValidTemp = ft;

    for (uint8_t i = 0; i < SMOOTH_WINDOW; i++) {
      tempBuffer[i] = ft;
    }

    tempCount = SMOOTH_WINDOW;
    tempIndex = 0;
    smoothedTemp = ft;
    tempSensorOK = true;
  }
}

void primeTurbidityBuffer() {
  float fv = readAnalogVoltage(TURBIDITY_PIN);
  TurbidityResult tr = classifyTurbidity(fv);

  turbidityVoltage = fv;
  lastValidTurbidityNTU = tr.ntu;

  for (uint8_t i = 0; i < SMOOTH_WINDOW; i++) {
    turbidityBuffer[i] = tr.ntu;
  }

  turbidityCount = SMOOTH_WINDOW;
  turbidityIndex = 0;
  smoothedTurbidityNTU = tr.ntu;
  turbiditySensorOK = tr.valid;
}

// ============================================================
//  SENSOR READ FUNCTIONS
// ============================================================
void readTemperatureSensor() {
  sensors.requestTemperatures();
  float rawTemp = sensors.getTempCByIndex(0);

  if (rawTemp < MIN_VALID_TEMP || rawTemp > MAX_VALID_TEMP) {
    tempSensorOK = false;
    Serial.printf("[TEMP SKIP] out of bounds: %.1f\n", rawTemp);
    return;
  }

  bool accept = true;

  if (lastValidTemp > -100.0) {
    float jump = fabs(rawTemp - lastValidTemp);

    if (jump > TEMP_JUMP_MAX) {
      accept = false;
      Serial.printf("[TEMP SKIP] jump too large: %.2f\n", jump);
    }
  }

  if (accept) {
    tempSkipCount = 0;
    tempBuffer[tempIndex] = rawTemp;
    tempIndex = (tempIndex + 1) % SMOOTH_WINDOW;

    if (tempCount < SMOOTH_WINDOW) tempCount++;

    lastValidTemp = rawTemp;
    tempSensorOK = true;
    smoothedTemp = computeAverage(tempBuffer, tempCount);
  } else {
    tempSkipCount++;

    if (tempSkipCount >= MAX_SKIP_COUNT) {
      Serial.println("[TEMP] Watchdog override — forcing new baseline.");
      lastValidTemp = rawTemp;
      tempSkipCount = 0;
    }
  }
}

void readTurbiditySensor() {
  float voltage = readAnalogVoltage(TURBIDITY_PIN);
  TurbidityResult tr = classifyTurbidity(voltage);

  turbidityVoltage = voltage;

  if (!tr.valid) {
    turbiditySensorOK = false;
    smoothedTurbidityNTU = 0.0;
    Serial.printf("[TURB] Air/no water (V=%.3f)\n", voltage);
    return;
  }

  bool accept = true;

  if (lastValidTurbidityNTU >= 0.0) {
    float jump = fabs(tr.ntu - lastValidTurbidityNTU);

    if (jump > TURB_NTU_JUMP_MAX) {
      accept = false;
      Serial.printf("[TURB SKIP] NTU jump too large: %.1f\n", jump);
    }
  }

  if (accept) {
    turbiditySkipCount = 0;
    turbidityBuffer[turbidityIndex] = tr.ntu;
    turbidityIndex = (turbidityIndex + 1) % SMOOTH_WINDOW;

    if (turbidityCount < SMOOTH_WINDOW) turbidityCount++;

    lastValidTurbidityNTU = tr.ntu;
    turbiditySensorOK = true;
    smoothedTurbidityNTU = computeAverage(turbidityBuffer, turbidityCount);
  } else {
    turbiditySkipCount++;

    if (turbiditySkipCount >= MAX_SKIP_COUNT) {
      Serial.println("[TURB] Watchdog override — forcing new baseline.");
      lastValidTurbidityNTU = tr.ntu;
      turbiditySkipCount = 0;
    }
  }
}

void readDissolvedOxygenSensor() {
  if (!ENABLE_DO_SENSOR) {
    dissolvedOxygen = -1.0;
    return;
  }

  dissolvedOxygenVoltage = readAnalogVoltage(DO_PIN);
  dissolvedOxygen = dissolvedOxygenVoltage * doVoltageScale + doVoltageOffset;
  dissolvedOxygen = constrain(dissolvedOxygen, 0.0f, 30.0f);
  doSensorOK = true;
}

void readPHSensor() {
  if (!ENABLE_PH_SENSOR) {
    phLevel = -1.0;
    return;
  }

  phVoltage = readAnalogVoltage(PH_PIN);
  phLevel = phVoltageSlope * phVoltage + phVoltageIntercept;
  phLevel = constrain(phLevel, 0.0f, 14.0f);
  phSensorOK = true;
}

void readWaterLevelSensor() {
  if (!ENABLE_WATER_LEVEL_SENSOR) {
    waterLevelPercent = -1.0;
    return;
  }

  waterLevelVoltage = readAnalogVoltage(WATER_LEVEL_PIN);
  waterLevelPercent = (waterLevelVoltage - waterLevelVoltageMin) * 100.0f / (waterLevelVoltageMax - waterLevelVoltageMin);
  waterLevelPercent = constrain(waterLevelPercent, 0.0f, 100.0f);
  waterLevelSensorOK = true;
}

void readAllSensors() {
  readTemperatureSensor();
  readTurbiditySensor();
  readDissolvedOxygenSensor();
  readPHSensor();
  readWaterLevelSensor();
}

// ─── Feeder forward declarations ───
void initFeeder();
void processFeederCommands();
void sendFeederStatus();
void syncFeederSchedules();
void checkScheduledFeed();
void startFeed(String source);
void processFeederTick();
void pushFeederLog(String action, String type);

// ============================================================
//  SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  sensors.begin();

  primeTemperatureBuffer();
  primeTurbidityBuffer();

  connectWiFi();
  initTime();
  connectFirebase();
  syncConfigFromFirebase();
  sendConfigToFirebase();
  initFeeder();
  syncFeederSchedules();

  Serial.println("============================================");
  Serial.println("  CrayCare Monitor — Calibrated Turbidity");
  Serial.printf("  Latest path : %s\n", FIREBASE_LATEST_PATH);
  Serial.printf("  History path: %s\n", FIREBASE_HISTORY_PATH);
  Serial.printf("  Config path : %s\n", FIREBASE_CONFIG_PATH);
  Serial.println("  Turbidity: NTU (calibrated)");
  Serial.println("============================================");
}

// ============================================================
//  LOOP
// ============================================================
void loop() {
  unsigned long now = millis();

  // ─── Serial Commands ───
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd == "RESET_WIFI") {
      prefs.begin("wifi", false);
      prefs.clear();
      prefs.end();
      Serial.println("[WIFI] Credentials erased. Restarting...");
      delay(1500);
      ESP.restart();
    }
    if (cmd == "FEED") {
      startFeed("manual");
    }
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WIFI] Reconnecting...");
    WiFi.disconnect();
    WiFi.begin(ssid.c_str(), pass.c_str());
    delay(1000);
    return;
  }

  // ─── Feeder ───
  if (now - lastFeederCmdCheckMs >= FEEDER_CMD_INTERVAL_MS) {
    lastFeederCmdCheckMs = now;
    processFeederCommands();
  }

  if (now - lastFeederStatusMs >= FEEDER_STATUS_INTERVAL_MS) {
    lastFeederStatusMs = now;
    sendFeederStatus();
  }

  if (now - lastFeederScheduleSyncMs >= FEEDER_SCHEDULE_SYNC_MS) {
    lastFeederScheduleSyncMs = now;
    syncFeederSchedules();
  }

  if (now - lastFeederScheduleCheckMs >= FEEDER_SCHEDULE_CHECK_MS) {
    lastFeederScheduleCheckMs = now;
    checkScheduledFeed();
  }

  // ─── Feeder state machine tick ───
  processFeederTick();

  // ─── Sensors ───

  if (now - lastConfigSyncTime >= CONFIG_SYNC_INTERVAL_MS) {
    lastConfigSyncTime = now;
    syncConfigFromFirebase();
  }

  if (now - lastPollTime >= SENSOR_POLL_MS) {
    lastPollTime = now;

    readAllSensors();

    Serial.printf("[OK] Temp: %.1f C | Turb: %.0f NTU (%.3fV) | DO: %.1f | pH: %.2f | Level: %.1f%%\n",
                  smoothedTemp,
                  smoothedTurbidityNTU,
                  turbidityVoltage,
                  dissolvedOxygen,
                  phLevel,
                  waterLevelPercent);
  }

  if (now - lastFirebaseSendTime >= FIREBASE_SEND_INTERVAL_MS) {
    lastFirebaseSendTime = now;
    sendLatestToFirebase();
    sendEspLastSeen();
  }

  if (now - lastHistorySendTime >= HISTORY_SEND_INTERVAL_MS) {
    lastHistorySendTime = now;
    sendHistoryToFirebase();
  }
}

// ============================================================
//  FEEDER MODULE — Servo Auto-Feeder Control
//  Firebase paths:
//    /feeder/commands   -> Flutter pushes, ESP32 polls & deletes
//    /feeder/status     -> ESP32 writes every 5s
//    /feeder/schedules  -> Flutter writes, ESP32 reads
//    /feeder/logs       -> ESP32 pushes
// ============================================================

// ─── Initialize Feeder ───
void initFeeder() {
  ledcSetup(SERVO_LEDC_CHANNEL, SERVO_LEDC_FREQ, SERVO_LEDC_RESOLUTION);
  ledcAttachPin(FEEDER_SERVO_PIN, SERVO_LEDC_CHANNEL);
  _setServoAngle(0);
  feederIsRunning = false;
  feederRunState = FEEDER_IDLE;
  feederCurrentCycle = 0;

  // Quick servo test on boot
  Serial.println("[FEEDER] Testing servo...");
  _setServoAngle(90);
  delay(800);
  _setServoAngle(0);
  delay(500);
  Serial.println("[FEEDER] Servo initialized OK");
}

// ─── Process Commands from Firebase ───
// Reads ALL command data first, then processes and deletes.
// This avoids fbdo/FirebaseJson buffer conflicts.
void processFeederCommands() {
  if (!ensureFirebaseReady()) return;

  FirebaseJson json;
  if (!Firebase.RTDB.getJSON(&fbdo, FIREBASE_FEEDER_COMMANDS_PATH, &json)) {
    return;
  }
  // Data is already in FirebaseJson — do NOT check httpConnected() here

  size_t count = json.iteratorBegin();
  if (count == 0) {
    json.iteratorEnd();
    return;
  }

  // Store all commands in local arrays first
  struct CmdEntry {
    String key;
    String action;
    String mode;
  };
  CmdEntry entries[20];
  int entryCount = 0;

  for (size_t i = 0; i < count && entryCount < 20; i++) {
    int iterType;
    String iterKey, iterValue;
    json.iteratorGet(i, iterType, iterKey, iterValue);

    FirebaseJson cmd;
    cmd.setJsonData(iterValue);
    FirebaseJsonData d;

    CmdEntry& e = entries[entryCount];
    e.key = iterKey;

    if (cmd.get(d, "action")) e.action = d.stringValue;
    if (cmd.get(d, "mode"))   e.mode   = d.stringValue;

    if (e.action != "") entryCount++;
  }

  json.iteratorEnd();

  // Now process stored commands (no fbdo conflict)
  for (int i = 0; i < entryCount; i++) {
    CmdEntry& e = entries[i];

    Serial.printf("[FEEDER CMD] %s (mode=%s) key=%s\n",
      e.action.c_str(), e.mode.c_str(), e.key.c_str());

    if (e.action == "feed_now") {
      startFeed("manual");
    } else if (e.action == "set_mode" && e.mode != "") {
      feederAutoMode = (e.mode == "auto");
      Serial.printf("[FEEDER] Mode -> %s\n",
        feederAutoMode ? "AUTO" : "MANUAL");
    }

    // Delete after processing
    String cmdPath = String(FIREBASE_FEEDER_COMMANDS_PATH) + "/" + e.key;
    if (!Firebase.RTDB.deleteNode(&fbdo, cmdPath.c_str())) {
      Serial.printf("[FEEDER] Delete cmd failed: %s\n", fbdo.errorReason().c_str());
    }
  }
}

// ─── Send Feeder Status to Firebase ───
void sendFeederStatus() {
  if (!ensureFirebaseReady()) return;

  time_t now;
  time(&now);
  unsigned long epochMs = (now > 1700000000) ? (unsigned long)now * 1000UL : 0;

  FirebaseJson json;
  json.set("mode", feederAutoMode ? "auto" : "manual");
  json.set("isRunning", feederIsRunning);
  json.set("feedSource", feederIsRunning ? feederFeedSource : "");
  json.set("hopperLevel", feederHopperLevel);
  json.set("lastFeedEpoch", (int)feederLastFeedEpoch);
  json.set("lastSeen", (int)epochMs);

  if (Firebase.RTDB.updateNode(&fbdo, FIREBASE_FEEDER_STATUS_PATH, &json)) {
    // success, no log needed
  } else if (fbdo.httpConnected()) {
    Serial.printf("[FEEDER STATUS ERROR] %s\n", fbdo.errorReason().c_str());
  }
}

// ─── Sync Schedules from Firebase ───
void syncFeederSchedules() {
  if (!ensureFirebaseReady()) return;

  FirebaseJson json;
  if (!Firebase.RTDB.getJSON(&fbdo, FIREBASE_FEEDER_SCHEDULES_PATH, &json)) {
    feederScheduleCount = 0;
    return;
  }
  if (!fbdo.httpConnected()) {
    feederScheduleCount = 0;
    return;
  }

  size_t count = json.iteratorBegin();
  if (count == 0) {
    feederScheduleCount = 0;
    json.iteratorEnd();
    return;
  }

  feederScheduleCount = 0;

  for (size_t i = 0; i < count && feederScheduleCount < FEEDER_MAX_SCHEDULES; i++) {
    int iterType;
    String iterKey, iterValue;
    json.iteratorGet(i, iterType, iterKey, iterValue);

    FeedSchedule& s = feederSchedules[feederScheduleCount];
    s.key = iterKey;

    // Parse child value as JSON
    FirebaseJson item;
    item.setJsonData(iterValue);
    FirebaseJsonData d;

    // Parse time "6:00" and ampm "AM"
    String timeStr = "6:00";
    String ampm = "AM";
    if (item.get(d, "time")) timeStr = d.stringValue;
    if (item.get(d, "ampm")) ampm = d.stringValue;

    // Convert to 24h
    int colon = timeStr.indexOf(':');
    if (colon < 0) { continue; }
    int hour = timeStr.substring(0, colon).toInt();
    int minute = timeStr.substring(colon + 1).toInt();
    if (ampm == "PM" && hour != 12) hour += 12;
    if (ampm == "AM" && hour == 12) hour = 0;

    s.hour24 = hour;
    s.minute = minute;
    s.enabled = true;
    if (item.get(d, "enabled")) s.enabled = d.boolValue;

    feederScheduleCount++;
  }

  json.iteratorEnd();
  Serial.printf("[FEEDER] Synced %d schedules\n", feederScheduleCount);
}

// ─── Check if it's time for a scheduled feed ───
void checkScheduledFeed() {
  if (!feederAutoMode || feederScheduleCount == 0) return;

  time_t now;
  time(&now);
  struct tm* timeinfo = localtime(&now);
  int currentMin = timeinfo->tm_hour * 60 + timeinfo->tm_min;

  for (int i = 0; i < feederScheduleCount; i++) {
    FeedSchedule& s = feederSchedules[i];
    if (!s.enabled) continue;

    int schedMin = s.hour24 * 60 + s.minute;
    // Fire within the same minute (tolerate 0-59s)
    if (schedMin == currentMin) {
      // Check we haven't already fired this minute
      unsigned long nowEpoch = (unsigned long)now;
      if (nowEpoch - feederLastFeedEpoch >= 60) {
        Serial.printf("[FEEDER] Scheduled feed at %02d:%02d\n", s.hour24, s.minute);
        startFeed("scheduled");
      }
    }
  }
}

// ─── Start Feed — kicks off non-blocking state machine ───
void startFeed(String source) {
  if (feederRunState != FEEDER_IDLE) {
    Serial.println("[FEEDER] Already running, skipping");
    return;
  }

  time_t now;
  time(&now);
  feederLastFeedEpoch = (unsigned long)now;
  feederFeedSource = source;
  feederIsRunning = true;
  feederCurrentCycle = 0;
  feederRunState = FEEDER_FORWARD;
  feederStartMs = millis();
  feederStepMs = feederStartMs;

  // Immediately notify Flutter that servo is starting
  sendFeederStatus();
  Serial.printf("[FEEDER] Start feed (source=%s)\n", source.c_str());
}

// ─── Non-blocking feeder tick — call every loop() ───
void processFeederTick() {
  if (feederRunState == FEEDER_IDLE) return;

  unsigned long now = millis();

  switch (feederRunState) {

    case FEEDER_FORWARD:
      _setServoAngle(180);
      feederStepMs = now;
      feederRunState = FEEDER_PAUSE_F;
      Serial.printf("[FEEDER] Forward  %d/%d\n",
        feederCurrentCycle + 1, feederMaxCycles);
      break;

    case FEEDER_PAUSE_F:
      if (now - feederStepMs >= 400) {  // hold open, food dispenses
        _setServoAngle(0);
        feederStepMs = now;
        feederRunState = FEEDER_BACKWARD;
      }
      break;

    case FEEDER_BACKWARD:
      _setServoAngle(0);
      feederStepMs = now;
      feederRunState = FEEDER_PAUSE_B;
      Serial.printf("[FEEDER] Backward %d/%d\n",
        feederCurrentCycle + 1, feederMaxCycles);
      break;

    case FEEDER_PAUSE_B:
      if (now - feederStepMs >= 150) {  // brief pause at closed
        feederCurrentCycle++;
        if (feederCurrentCycle >= feederMaxCycles) {
          feederRunState = FEEDER_DONE;
          feederStepMs = now;
        } else {
          // Start next cycle
          feederRunState = FEEDER_FORWARD;
          feederStepMs = now;
        }
      }
      break;

    case FEEDER_DONE:
      // Keep isRunning=true for at least 1s so Flutter reliably catches the transition
      if (now - feederStartMs < 1000) break;

      _setServoAngle(0);

      // Update hopper level
      feederHopperLevel -= 9;
      if (feederHopperLevel < 0) feederHopperLevel = 0;

      feederIsRunning = false;
      feederRunState = FEEDER_IDLE;

      // Push final status + log
      sendFeederStatus();
      pushFeederLog(
        feederFeedSource == "scheduled"
          ? "Dispensed feed (Scheduled)"
          : "Dispensed feed (Manual)",
        feederAutoMode ? "auto" : "manual"
      );

      feederFeedSource = "";
      Serial.println("[FEEDER] Feed complete");
      break;

    default:
      feederRunState = FEEDER_IDLE;
      break;
  }
}

// ─── Push Feeding Log to Firebase ───
void pushFeederLog(String action, String type) {
  if (!ensureFirebaseReady()) return;

  time_t now;
  time(&now);
  struct tm* timeinfo = localtime(&now);

  // Format time
  int h12 = timeinfo->tm_hour % 12;
  if (h12 == 0) h12 = 12;
  String ampm = timeinfo->tm_hour >= 12 ? "PM" : "AM";
  char timeBuf[10];
  sprintf(timeBuf, "%d:%02d %s", h12, timeinfo->tm_min, ampm.c_str());

  // Format date
  const char* months[] = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
  char dateBuf[20];
  sprintf(dateBuf, "%s %d, %d", months[timeinfo->tm_mon], timeinfo->tm_mday, 1900 + timeinfo->tm_year);

  unsigned long epochMs = ((unsigned long)now) * 1000UL;

  FirebaseJson json;
  json.set("action", action);
  json.set("type", type);
  json.set("time", String(timeBuf));
  json.set("date", String(dateBuf));
  json.set("timestamp", (int)epochMs);

  if (Firebase.RTDB.pushJSON(&fbdo, FIREBASE_FEEDER_LOGS_PATH, &json)) {
    Serial.printf("[FEEDER LOG] %s\n", action.c_str());
  } else if (fbdo.httpConnected()) {
    Serial.printf("[FEEDER LOG ERROR] %s\n", fbdo.errorReason().c_str());
  }
}
