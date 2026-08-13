/*
 * ============================================================
 *  CrayCare — ESP32 Multi-Sensor Monitor + Firebase Firestore
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
 * Firestore ingestion paths (written by ESP32):
 *  sensorIngestion/current                  -> latest payload every 5 seconds
 *  sensorIngestion/current/history/{docId}  -> history payload every 10 minutes
 *
 * Cloud Functions resolve hardware_system/currentOwner.tank_id and route to:
 *  tanks/{tankId}/sensor_readings/latest
 *  tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{docId}
 *
 * All Firebase operations use Firestore only — zero RTDB calls.
 * Feeder commands/status/schedules/logs all migrated to Firestore.
 */

#include <WiFi.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <Firebase_ESP_Client.h>

#include <Preferences.h>
#include <time.h>
#include <stdlib.h>    // atoll()
#include <LittleFS.h>  // offline store-and-forward buffer (data partition)
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include "secrets.h"   // Firebase credentials — gitignored (see secrets.h.example)

#ifndef FIREBASE_API_KEY
#error "secrets.h missing — copy include/secrets.h.example to include/secrets.h and fill in your values"
#endif

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
// Firebase credentials (FIREBASE_API_KEY, FIREBASE_DATABASE_URL,
// FIREBASE_PROJECT_ID) are defined in secrets.h (included above).
// All data paths route to tanks/{currentTankId}/... — no intermediate
// sensorIngestion collection exists anymore.
// Hardware ID derived from MAC address on first use (see getHardwareId())
String hardwareId = "";
String currentTankId = "";

#define FIREBASE_SEND_INTERVAL_MS 5000
#define HISTORY_SEND_INTERVAL_MS 600000  // 10 minutes; matches the documented schema
#define CONFIG_SYNC_INTERVAL_MS 10000
#define FLUSH_INTERVAL_MS 1000           // flush backlog at 1 entry/sec (max)
#define SENSOR_POLL_MS 500

// Feeder timing
#define FEEDER_CMD_INTERVAL_MS 300
#define FEEDER_STATUS_INTERVAL_MS 5000
#define FEEDER_SCHEDULE_SYNC_MS 30000
#define FEEDER_SCHEDULE_CHECK_MS 1000
#define FEEDER_SERVO_PULSE_WIDTH 2000   // microseconds for full rotation
#define FEEDER_MAX_SCHEDULES 20

// Resolve tank_id from hardware_system/currentOwner (used for subcollection paths)
extern FirebaseData fbdo;
bool ensureFirebaseReady();
void fetchTankId() {
  if (!ensureFirebaseReady()) return;
  // Read hardware_system/currentOwner to get tank_id for subcollection paths
  if (!Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "",
        "hardware_system/currentOwner")) {
    return;
  }
  FirebaseJson resp;
  resp.setJsonData(fbdo.payload());
  FirebaseJsonData d;
  if (resp.get(d, "fields/tank_id/stringValue")) {
    currentTankId = d.stringValue;
  }
  Serial.printf("[ESP] Resolved tank_id = %s\n", currentTankId.c_str());
}

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

bool firebaseReady = false;
unsigned long lastFirebaseSendTime = 0;
unsigned long lastHistorySendTime = 0;
unsigned long lastFlushTime = 0;

// ─── Offline buffer (LittleFS store-and-forward) ─────────────────────
// History entries that fail to upload (WiFi outage / Firebase unreachable)
// are appended here as Firestore wire-format JSON lines. When connectivity
// returns, loop() flushes them oldest-first at 1 entry/sec, deleting each
// line only after Firestore confirms the write (or finds a duplicate doc).
#define BUFFER_PATH "/buf/history.jsonl"
bool littlefsMounted = false;

size_t countBufferedEntries();  // forward decl (used by initOfflineBuffer)

void initOfflineBuffer() {
  if (!LittleFS.begin(true)) {           // formatOnFail on the spiffs partition
    Serial.println("[BUF] LittleFS mount FAILED — offline buffering disabled");
    littlefsMounted = false;
    return;
  }
  littlefsMounted = true;
  Serial.printf("[BUF] LittleFS ready, buffered: %u\n", (unsigned)countBufferedEntries());
}

size_t countBufferedEntries() {
  if (!littlefsMounted) return 0;
  File f = LittleFS.open(BUFFER_PATH, "r");
  if (!f) return 0;
  size_t n = 0;
  while (f.available()) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (line.length() > 10) n++;
  }
  f.close();
  return n;
}

bool bufferAppend(const String& jsonLine) {
  if (!littlefsMounted || jsonLine.length() < 10) return false;
  File f = LittleFS.open(BUFFER_PATH, FILE_APPEND);
  if (!f) return false;
  f.println(jsonLine);
  f.close();
  return true;
}

// Drop the first line (index 0) and rewrite the remaining lines.
bool bufferDropFirst(const String* lines, size_t n) {
  if (!littlefsMounted) return false;
  File f = LittleFS.open(BUFFER_PATH, "w");
  if (!f) return false;
  for (size_t i = 1; i < n; i++) f.println(lines[i]);
  f.close();
  return true;
}

// Read all buffered lines into a fixed array (bounded).
size_t bufferReadAll(String* lines, size_t maxLines) {
  if (!littlefsMounted) return 0;
  File f = LittleFS.open(BUFFER_PATH, "r");
  if (!f) return 0;
  size_t n = 0;
  while (f.available() && n < maxLines) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (line.length() > 10) lines[n++] = line;
  }
  f.close();
  return n;
}

// Upload the oldest buffered entry. Returns:
//   true  -> entry uploaded (or dropped as duplicate) -> remove from buffer
//   false -> still no connectivity -> keep in buffer and retry later
bool flushOneBufferedEntry() {
  String lines[32];
  size_t n = bufferReadAll(lines, 32);
  if (n == 0) return true;

  // Deterministic doc ID from the bucket time (dedup: re-uploading the same
  // bucket after a crash simply finds the existing doc and skips it).
  // The buffered line is Firestore wire-format JSON, e.g.
  //   {"fields":{"captured_at_ms":{"integerValue":"1755122400000"},...}}
  // so dig into the nested integerValue for the epoch-ms.
  long long capMs = 0;
  int idx = lines[0].indexOf("\"captured_at_ms\"");
  if (idx >= 0) {
    int st = lines[0].indexOf("\"integerValue\":\"", idx);
    if (st >= 0) {
      st += 17;  // length of "\"integerValue\":\"" (17 chars)
      int en = lines[0].indexOf('"', st);
      if (en > st) capMs = atoll(lines[0].substring(st, en).c_str());
    }
  }
  String docId = (capMs > 0)
      ? "offline_" + String((unsigned long)(capMs / 600000LL))
      : "offline_" + String((long)millis());
  String docPath = String("sensorIngestion/current/history/") + docId;

  // Skip if already uploaded (crash between create and buffer-delete).
  if (Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "(default)",
                                     docPath.c_str())) {
    Serial.println("[BUF] Duplicate found — dropping buffered entry");
    return bufferDropFirst(lines, n);
  }

  // 7-arg form (collection, docId, content, mask) avoids the ambiguous
  // 6-arg overload (documentPath+content vs collectionId+documentId).
  if (Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "(default)",
                                        "sensorIngestion/current/history",
                                        docId.c_str(), lines[0].c_str(), "")) {
    Serial.printf("[BUF] Flushed entry -> %s\n", docPath.c_str());
    return bufferDropFirst(lines, n);
  }
  Serial.printf("[BUF] Flush failed (%s) — will retry\n", fbdo.errorReason().c_str());
  return false;
}
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
int feederFeedCount = 0;              // total feeds dispensed since boot

// Firestore integerValue is textual. Avoid 32-bit unsigned-long overflow
// when sending epoch milliseconds from the ESP32.
String epochMillisString(time_t seconds) {
  if (seconds < 1700000000) return "0";
  char buffer[24];
  const uint64_t millisValue = static_cast<uint64_t>(seconds) * 1000ULL;
  snprintf(buffer, sizeof(buffer), "%llu", static_cast<unsigned long long>(millisValue));
  return String(buffer);
}

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
//  ACTUATOR STATE — pump + 2 aerators
//  Firestore source of truth: tanks/{tankId}/actuators/{deviceId}
//    control_mode : "on" | "off" | "auto"   (written by Flutter app)
//    current_state: "on" | "off"            (actual relay state — ESP writes back)
//    last_changed : Timestamp               (app) / epoch-ms int (ESP report)
// ============================================================
// Actuator pins — relays are ACTIVE-LOW (digitalWrite LOW = relay ON).
// Firestore IDs match the Flutter app (lib/services/actuator_log_service.dart):
//   "pump"     -> Water Pump       (GPIO 26)
//   "aerator1" -> Primary Aerator  (GPIO 27)
//   "aerator2" -> Secondary Aerator(GPIO 14)
#define ACTUATOR_PUMP_PIN 26
#define ACTUATOR_AER1_PIN 27
#define ACTUATOR_AER2_PIN 14
#define ACTUATOR_SYNC_INTERVAL_MS 5000   // poll tanks/{tankId}/actuators every 5s

struct ActuatorDevice {
  const char* deviceId;       // Firestore doc ID: "pump" | "aerator1" | "aerator2"
  const char* label;          // human label used in logs
  uint8_t pin;                // relay GPIO (active LOW)
  String controlMode;         // "on" | "off" | "auto"  (last value read from Firestore)
  bool relayOn;               // current physical relay state
  bool cloudReported;         // true when current_state has been pushed to Firestore
  String cloudReportedState;  // last current_state string we successfully pushed
  unsigned long lastChangeMs; // uptime ms of last physical relay change
};

ActuatorDevice actuators[3] = {
  { "pump",     "Water Pump",      ACTUATOR_PUMP_PIN, "off", false, false, "", 0 },
  { "aerator1", "Aerator 1",       ACTUATOR_AER1_PIN, "off", false, false, "", 0 },
  { "aerator2", "Aerator 2",       ACTUATOR_AER2_PIN, "off", false, false, "", 0 },
};

unsigned long lastActuatorSyncMs = 0;

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

// Actuator pins are defined with the ACTUATOR STATE block above.

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
float turbNtuMax = 25.0;

float doCriticalLow = 5.0;
float doCriticalHigh = 9.0;

float phCriticalLow = 7.0;
float phCriticalHigh = 8.5;

float waterLevelCriticalLow = 15.0;
float waterLevelCriticalHigh = 20.0;

float doVoltageScale = 4.0;
float doVoltageOffset = 0.0;
float phVoltageSlope = -5.70;
float phVoltageIntercept = 21.34;
float waterLevelVoltageMin = 0.0;
float waterLevelVoltageMax = 3.3;
// Physical water depth represented by the calibrated voltage range.
float waterLevelCmMin = 0.0;
float waterLevelCmMax = 30.0;

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

// ─── 10-min window aggregates (min/max/avg) ──────────────────────────
// Accumulated from ACCEPTED readings between history saves, so brief
// spikes inside a 10-min window are preserved in the history entry
// (and the ML volatility feature gets a real signal). The ESP polls
// every 0.5 s, so each window collects up to ~1200 samples.
// Reset after every history write (or buffer append).
float winTempSum = 0.0f; uint16_t winTempN = 0;
float winTempMin = 0.0f; float winTempMax = 0.0f;
float winTurbSum = 0.0f; uint16_t winTurbN = 0;
float winTurbMin = 0.0f; float winTurbMax = 0.0f;
float winDOSum = 0.0f; uint16_t winDON = 0;
float winDOMin = 0.0f; float winDOMax = 0.0f;
float winPHSum = 0.0f; uint16_t winPHN = 0;
float winPHMin = 0.0f; float winPHMax = 0.0f;
float winWaterSum = 0.0f; uint16_t winWaterN = 0;
float winWaterMin = 0.0f; float winWaterMax = 0.0f;

void resetWindowAggregates() {
  winTempSum = 0.0f; winTempN = 0; winTempMin = 0.0f; winTempMax = 0.0f;
  winTurbSum = 0.0f; winTurbN = 0; winTurbMin = 0.0f; winTurbMax = 0.0f;
  winDOSum = 0.0f; winDON = 0; winDOMin = 0.0f; winDOMax = 0.0f;
  winPHSum = 0.0f; winPHN = 0; winPHMin = 0.0f; winPHMax = 0.0f;
  winWaterSum = 0.0f; winWaterN = 0; winWaterMin = 0.0f; winWaterMax = 0.0f;
}

// Accumulate one accepted reading into the 10-min window aggregates.
#define ACCUM_WINDOW(sumV, nV, minV, maxV, val) \
  do { \
    (sumV) += (val); (nV)++; \
    if ((nV) == 1) { (minV) = (val); (maxV) = (val); } \
    else { if ((val) < (minV)) (minV) = (val); if ((val) > (maxV)) (maxV) = (val); } \
  } while (0)

float dissolvedOxygen = -1.0;
float dissolvedOxygenVoltage = 0.0;
bool doSensorOK = false;

float phLevel = -1.0;
float phVoltage = 0.0;
bool phSensorOK = false;

float waterLevelCm = -1.0;
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

// Read a float from a Firestore document already loaded into `doc`.
// jsonPath is the full dotted path, e.g. "fields/turbidityVClear/doubleValue".
bool readConfigFloatPath(FirebaseJson& doc, const char* jsonPath,
                         float& target, float minValue, float maxValue) {
  FirebaseJsonData d;
  if (!doc.get(d, jsonPath)) return false;
  float value = d.floatValue;
  if (!isfinite(value) || value < minValue || value > maxValue) {
    Serial.printf("[CONFIG SKIP] %s invalid value: %.3f\n", jsonPath, value);
    return false;
  }
  target = value;
  return true;
}

// Read min/max from the Firestore ranges map written by Flutter settings_service.
// Firestore path pattern: fields/ranges/mapValue/fields/{key}/mapValue/fields/{min|max}/doubleValue
bool readRangeConfig(FirebaseJson& doc, const char* sensorKey,
                     float& lowTarget, float& highTarget,
                     float minLimit, float maxLimit) {
  String prefix = String("fields/ranges/mapValue/fields/") + sensorKey
                  + "/mapValue/fields/";
  float newLow  = lowTarget;
  float newHigh = highTarget;
  bool gotMin = readConfigFloatPath(doc, (prefix + "min/doubleValue").c_str(),
                                    newLow, minLimit, maxLimit);
  bool gotMax = readConfigFloatPath(doc, (prefix + "max/doubleValue").c_str(),
                                    newHigh, minLimit, maxLimit);
  if (!gotMin && !gotMax) return false;
  if (newLow >= newHigh) {
    Serial.printf("[CONFIG SKIP] ranges/%s min must be lower than max\n", sensorKey);
    return false;
  }
  lowTarget  = newLow;
  highTarget = newHigh;
  return true;
}

bool ensureFirebaseReady();

// ============================================================
//  CONFIG SYNC — Read per-tank thresholds from the final Firestore schema.
// ============================================================
// Read one threshold document from the final schema:
// tanks/{tankId}/sensors/{temperature|ph_level|dissolved_oxygen|turbidity|water_level}
bool syncTankRange(const char* sensorDoc, float &lowTarget, float &highTarget,
                   float minLimit, float maxLimit) {
  String path = String("tanks/") + currentTankId + "/sensors/" + sensorDoc;
  if (!Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "", path.c_str(), "")) {
    Serial.printf("[CONFIG] %s unavailable: %s\n", path.c_str(), fbdo.errorReason().c_str());
    return false;
  }
  FirebaseJson doc;
  doc.setJsonData(fbdo.payload());
  float low = lowTarget, high = highTarget;
  bool gotLow = readConfigFloatPath(doc, "fields/min_value/doubleValue", low, minLimit, maxLimit);
  bool gotHigh = readConfigFloatPath(doc, "fields/max_value/doubleValue", high, minLimit, maxLimit);
  if (!gotLow || !gotHigh || low >= high) {
    Serial.printf("[CONFIG] Invalid threshold document: %s\n", path.c_str());
    return false;
  }
  lowTarget = low;
  highTarget = high;
  return true;
}

// Thresholds are owned by the currently assigned tank. The ESP obtains its
// tank ID from hardware_system/currentOwner, never from a user UID.
void syncConfigFromFirebase() {
  fetchTankId();
  if (currentTankId.length() == 0) {
    Serial.println("[CONFIG] No tank assigned; retaining firmware defaults.");
    return;
  }

  bool changed = false;
  changed |= syncTankRange("temperature",       tempCriticalLow,       tempCriticalHigh,       0.0,   50.0);
  changed |= syncTankRange("turbidity",         turbNtuMin,            turbNtuMax,             0.0, 1000.0);
  changed |= syncTankRange("dissolved_oxygen",  doCriticalLow,         doCriticalHigh,          0.0,   30.0);
  changed |= syncTankRange("ph_level",          phCriticalLow,         phCriticalHigh,          0.0,   14.0);
  changed |= syncTankRange("water_level",       waterLevelCriticalLow, waterLevelCriticalHigh,  0.0,  300.0);

  if (changed) {
    Serial.printf("[CONFIG] Tank %s | Temp %.1f-%.1f | Turb %.0f-%.0f | DO %.1f-%.1f | pH %.1f-%.1f | Water %.1f-%.1f%%\n",
                  currentTankId.c_str(), tempCriticalLow, tempCriticalHigh,
                  turbNtuMin, turbNtuMax, doCriticalLow, doCriticalHigh,
                  phCriticalLow, phCriticalHigh, waterLevelCriticalLow, waterLevelCriticalHigh);
  }
}

// ============================================================
//  HARDWARE ID — derived from ESP32 MAC address (unique per board)
//  Format: ESP_AABBCCDDEEFF
//  Generated once per boot; never stored in NVS (MAC is static).
// ============================================================
String getHardwareId() {
  if (hardwareId != "") return hardwareId;
  uint8_t mac[6];
  WiFi.macAddress(mac);
  char buf[20];
  snprintf(buf, sizeof(buf), "ESP_%02X%02X%02X%02X%02X%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  hardwareId = String(buf);
  return hardwareId;
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
//  FIRESTORE PAYLOAD BUILDER
//  Formats sensor readings as Firestore typed-value JSON.
//  Used for both latest (patch) and history (create) writes.
//  includeTimestamp=true adds a timestamp field for history.
// ============================================================
void buildFirestorePayload(FirebaseJson &json, bool includeTimestamp) {
  String hwId = getHardwareId();
  json.set("fields/hardwareId/stringValue", hwId);

  if (!includeTimestamp) {
    // ── 5-sec LIVE payload: current smoothed values (dashboard display). ──
    json.set("fields/temperature/doubleValue", smoothedTemp);

    if (turbiditySensorOK) {
      json.set("fields/turbidity_air/booleanValue", false);
      json.set("fields/turbidity/doubleValue", smoothedTurbidityNTU);
    } else {
      json.set("fields/turbidity_air/booleanValue", true);
      json.set("fields/turbidity/doubleValue", 0.0);
    }

    if (ENABLE_DO_SENSOR) {
      json.set("fields/dissolved_oxygen/doubleValue", dissolvedOxygen);
    }

    if (ENABLE_PH_SENSOR) {
      json.set("fields/ph_level/doubleValue", phLevel);
    }

    if (ENABLE_WATER_LEVEL_SENSOR) {
      json.set("fields/water_level/doubleValue", waterLevelCm);
    }
    return;
  }

  // ── 10-min HISTORY payload: per-sensor window aggregates. ────────────
  // Structure per sensor: MIN, MAX, AVG (in that order — avg NOT first).
  // The window accumulators hold every ACCEPTED reading since the last
  // history save (up to ~1200 samples at 0.5s poll), so brief spikes
  // inside the window are preserved (e.g. temp_max catches a spike that
  // the snapshot at save time would miss). Falls back to the smoothed
  // value when no samples were accepted this window.

  // Temperature
  const float tMin = winTempN > 0 ? winTempMin : smoothedTemp;
  const float tMax = winTempN > 0 ? winTempMax : smoothedTemp;
  const float tAvg = winTempN > 0 ? winTempSum / (float)winTempN : smoothedTemp;
  json.set("fields/temp_min/doubleValue", tMin);
  json.set("fields/temp_max/doubleValue", tMax);
  json.set("fields/temp_avg/doubleValue", tAvg);

  // Turbidity
  const float trMin = winTurbN > 0 ? winTurbMin : smoothedTurbidityNTU;
  const float trMax = winTurbN > 0 ? winTurbMax : smoothedTurbidityNTU;
  const float trAvg = winTurbN > 0 ? winTurbSum / (float)winTurbN : smoothedTurbidityNTU;
  json.set("fields/turbidity_min/doubleValue", trMin);
  json.set("fields/turbidity_max/doubleValue", trMax);
  json.set("fields/turbidity_avg/doubleValue", trAvg);

  if (ENABLE_DO_SENSOR) {
    const float dMin = winDON > 0 ? winDOMin : dissolvedOxygen;
    const float dMax = winDON > 0 ? winDOMax : dissolvedOxygen;
    const float dAvg = winDON > 0 ? winDOSum / (float)winDON : dissolvedOxygen;
    json.set("fields/DO_min/doubleValue", dMin);
    json.set("fields/DO_max/doubleValue", dMax);
    json.set("fields/DO_avg/doubleValue", dAvg);
  }

  if (ENABLE_PH_SENSOR) {
    const float pMin = winPHN > 0 ? winPHMin : phLevel;
    const float pMax = winPHN > 0 ? winPHMax : phLevel;
    const float pAvg = winPHN > 0 ? winPHSum / (float)winPHN : phLevel;
    json.set("fields/pH_min/doubleValue", pMin);
    json.set("fields/pH_max/doubleValue", pMax);
    json.set("fields/pH_avg/doubleValue", pAvg);
  }

  if (ENABLE_WATER_LEVEL_SENSOR) {
    const float wMin = winWaterN > 0 ? winWaterMin : waterLevelCm;
    const float wMax = winWaterN > 0 ? winWaterMax : waterLevelCm;
    const float wAvg = winWaterN > 0 ? winWaterSum / (float)winWaterN : waterLevelCm;
    json.set("fields/waterLevel_min/doubleValue", wMin);
    json.set("fields/waterLevel_max/doubleValue", wMax);
    json.set("fields/waterLevel_avg/doubleValue", wAvg);
  }

  // History entries carry the ESP's capture time so the Cloud Function can
  // preserve the ORIGINAL timestamp when routing (critical for offline
  // backfill — buffered readings must land in the correct date folder with
  // their true capture time, not the upload time). NTP is synced in setup().
  time_t nowT;
  time(&nowT);
  if (nowT > 1577836800) {  // > 2020-01-01 — guard against unsynced clock
    long long ms = (long long)nowT * 1000LL;
    json.set("fields/captured_at_ms/integerValue", String(ms));
  }
}


// ─── Write latest sensor reading to Firestore ───────────────────────
// Path: sensorIngestion/current  (fixed doc — patch, overwrites in place)
// Cloud Function onSensorIngestionWrite triggers here, reads
// hardware_system/currentOwner to get ownerUid, and copies data into
// tanks/{tankId}/sensor_readings/latest for the Flutter app to read.
// The ESP never knows any user UID — ownership is resolved server-side.
void sendLatestToFirestore() {
  if (!ensureFirebaseReady()) return;

  FirebaseJson content;
  buildFirestorePayload(content, false);

  // Advertise the pending offline backlog so the app can show
  // "Syncing N offline readings…" while the ESP flushes LittleFS.
  content.set("fields/buffered_entries/integerValue",
              String((unsigned long)countBufferedEntries()));

  // Fixed path — no hardwareId needed. There is only one hardware package.
  const char* docPath = "sensorIngestion/current";

  if (Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "(default)",
                                       docPath, content.raw(), "")) {
    Serial.println("[FIRESTORE] Latest sent");
  } else {
    Serial.printf("[FIRESTORE ERROR] %s\n", fbdo.errorReason().c_str());
  }
}

// ─── Write history entry to Firestore ───────────────────────────────
// Path: sensorIngestion/current/history  (create — auto-ID doc every 10 minutes)
// Cloud Function onSensorIngestionHistoryCreate triggers here, reads
// hardware_system/currentOwner, and saves into
// tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{autoId}.
void sendHistoryToFirestore() {
  // Build the payload FIRST (captures the 10-min window aggregates).
  FirebaseJson content;
  buildFirestorePayload(content, true);

  // WiFi/Firebase down: buffer the reading for later flush. (Previously we
  // returned early here and the reading was LOST — the whole point of the
  // store-and-forward buffer is to survive exactly this case.)
  if (!ensureFirebaseReady()) {
    if (bufferAppend(content.raw())) {
      Serial.printf("[BUF] Offline — buffered entry #%u\n",
                    (unsigned)countBufferedEntries());
    }
    resetWindowAggregates();  // values already captured into content
    return;
  }

  // Fixed subcollection — always under sensorIngestion/current.
  const char* colPath = "sensorIngestion/current/history";

  if (Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "(default)",
                                        colPath, "", content.raw(), "")) {
    Serial.println("[FIRESTORE] History saved");
  } else {
    Serial.printf("[FIRESTORE HISTORY ERROR] %s\n", fbdo.errorReason().c_str());
    // WiFi is up but Firebase failed (or is unreachable): keep the reading.
    // Store-and-forward — it will be flushed automatically once connectivity
    // returns. Power loss during the outage is safe: LittleFS is persistent.
    if (bufferAppend(content.raw())) {
      Serial.printf("[BUF] Buffered entry #%u\n", (unsigned)countBufferedEntries());
    }
  }
  resetWindowAggregates();  // values captured -> start a fresh 10-min window
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
    ACCUM_WINDOW(winTempSum, winTempN, winTempMin, winTempMax, rawTemp);
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
    ACCUM_WINDOW(winTurbSum, winTurbN, winTurbMin, winTurbMax, tr.ntu);
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
  ACCUM_WINDOW(winDOSum, winDON, winDOMin, winDOMax, dissolvedOxygen);
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
  ACCUM_WINDOW(winPHSum, winPHN, winPHMin, winPHMax, phLevel);
}

void readWaterLevelSensor() {
  if (!ENABLE_WATER_LEVEL_SENSOR) {
    waterLevelCm = -1.0;
    return;
  }

  waterLevelVoltage = readAnalogVoltage(WATER_LEVEL_PIN);
  const float ratio = (waterLevelVoltage - waterLevelVoltageMin) /
      (waterLevelVoltageMax - waterLevelVoltageMin);
  waterLevelCm = waterLevelCmMin + ratio * (waterLevelCmMax - waterLevelCmMin);
  waterLevelCm = constrain(waterLevelCm, waterLevelCmMin, waterLevelCmMax);
  waterLevelSensorOK = true;
  ACCUM_WINDOW(winWaterSum, winWaterN, winWaterMin, winWaterMax, waterLevelCm);
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

// ─── Actuator forward declarations ───
void initActuators();
void syncActuatorsFromFirestore();
void applyActuatorDevice(int idx);
bool actuatorAutoTarget(int idx);
void setActuatorRelay(int idx, bool on);
void reportActuatorState(int idx, bool forced);
void pushActuatorLog(int idx, String action, String type, String level);

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
  initOfflineBuffer();  // LittleFS store-and-forward (mounted before loop)
  getHardwareId();  // resolve MAC-based ID after WiFi is up
  fetchTankId();
  syncConfigFromFirebase();
  initFeeder();
  syncFeederSchedules();
  initActuators();

  Serial.println("============================================");
  Serial.println("  CrayCare Monitor — Firestore Ingestion");
  Serial.printf("  Hardware ID : %s\n", hardwareId.c_str());
  Serial.printf("  Tank ID     : %s\n", currentTankId.c_str());
  Serial.printf("  Tank config : tanks/%s/sensors\n", currentTankId.c_str());
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
    // Relay test commands (local only — cloud mode re-asserts on next sync)
    if (cmd == "n1on")  { setActuatorRelay(0, true);  reportActuatorState(0, true); }
    if (cmd == "n1off") { setActuatorRelay(0, false); reportActuatorState(0, true); }
    if (cmd == "n2on")  { setActuatorRelay(1, true);  reportActuatorState(1, true); }
    if (cmd == "n2off") { setActuatorRelay(1, false); reportActuatorState(1, true); }
    if (cmd == "n3on")  { setActuatorRelay(2, true);  reportActuatorState(2, true); }
    if (cmd == "n3off") { setActuatorRelay(2, false); reportActuatorState(2, true); }
    if (cmd == "relay status" || cmd == "relaystatus") {
      for (int i = 0; i < 3; i++) {
        Serial.printf("  %s (GPIO %d): %s | mode=%s\n",
                      actuators[i].label, actuators[i].pin,
                      actuators[i].relayOn ? "ON" : "OFF",
                      actuators[i].controlMode.c_str());
      }
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

  // ─── Actuators (pump + aerators) ───
  if (now - lastActuatorSyncMs >= ACTUATOR_SYNC_INTERVAL_MS) {
    lastActuatorSyncMs = now;
    syncActuatorsFromFirestore();
  }

  // ─── Sensors ───

  if (now - lastConfigSyncTime >= CONFIG_SYNC_INTERVAL_MS) {
    lastConfigSyncTime = now;
    syncConfigFromFirebase();
  }

  if (now - lastPollTime >= SENSOR_POLL_MS) {
    lastPollTime = now;

    readAllSensors();

    Serial.printf("[OK] Temp: %.1f C | Turb: %.0f NTU (%.3fV) | DO: %.1f | pH: %.2f | Level: %.1f cm\n",
                  smoothedTemp,
                  smoothedTurbidityNTU,
                  turbidityVoltage,
                  dissolvedOxygen,
                  phLevel,
                  waterLevelCm);
  }

  if (now - lastFirebaseSendTime >= FIREBASE_SEND_INTERVAL_MS) {
    lastFirebaseSendTime = now;
    // Sensor writes go to Firestore; Cloud Functions add recorded_at server timestamps.
    sendLatestToFirestore();
  }

  if (now - lastHistorySendTime >= HISTORY_SEND_INTERVAL_MS) {
    lastHistorySendTime = now;
    sendHistoryToFirestore();
  }

  // ─── Offline buffer flush (store-and-forward) ───
  // Runs whenever Firebase is reachable; 1 entry/sec max so the live
  // 5-sec + 10-min writes are never starved. Oldest entry goes first.
  if (now - lastFlushTime >= FLUSH_INTERVAL_MS) {
    lastFlushTime = now;
    if (littlefsMounted && countBufferedEntries() > 0) {
      if (ensureFirebaseReady()) {
        if (flushOneBufferedEntry()) {
          Serial.printf("[BUF] Flushed — %u remaining\n",
                        (unsigned)countBufferedEntries());
        }
        // flushOneBufferedEntry()==false -> still offline, keep for retry.
      }
    }
  }
}

// ============================================================
//  FEEDER MODULE — Servo Auto-Feeder Control
//  Firestore paths (all Firestore, zero RTDB):
//    feederCommands/{docId}  -> Flutter pushes, ESP32 polls & deletes
//    feederStatus/status     -> ESP32 writes every 5s
//    feederSchedules/{docId} -> Flutter writes, ESP32 reads
//    feederLogs              -> ESP32 creates (auto-ID)
// ============================================================

// ─── Initialize Feeder ───
void initFeeder() {
  fetchTankId();
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

// ─── Process Commands from Firestore ───
// Lists feederCommands collection, processes each doc, then deletes it.
// Reads all docs into local arrays first to avoid fbdo buffer conflicts.
void processFeederCommands() {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) return;   // no tank assigned -> nothing to do

  String cmdCol = "tanks/" + currentTankId + "/pending_commands";
  if (!Firebase.Firestore.listDocuments(&fbdo, FIREBASE_PROJECT_ID, "",
        cmdCol.c_str(), 20, "", "", "", false)) {
    return;
  }

  FirebaseJson response;
  response.setJsonData(fbdo.payload());
  FirebaseJsonData d;

  struct CmdEntry {
    String docId;
    String action;
    String mode;
  };
  CmdEntry entries[20];
  int entryCount = 0;

  for (int i = 0; i < 20 && entryCount < 20; i++) {
    String namePath = String("documents/[") + i + "]/name";
    if (!response.get(d, namePath)) break;               // no more documents

    // Full resource name → extract last segment as doc ID
    String docName  = d.stringValue;
    int lastSlash   = docName.lastIndexOf('/');
    String docId    = (lastSlash >= 0) ? docName.substring(lastSlash + 1) : docName;

    String base = String("documents/[") + i + "]/fields/";
    CmdEntry& e = entries[entryCount];
    e.docId = docId;

    if (response.get(d, base + "command_type/stringValue")) e.action = d.stringValue;
    // Legacy fallback: try old action field if new not present
    if (e.action == "" && response.get(d, base + "action/stringValue")) e.action = d.stringValue;
    if (response.get(d, base + "trigger_type/stringValue")) e.mode = d.stringValue;
    if (e.mode == "" && response.get(d, base + "mode/stringValue")) e.mode = d.stringValue;

    if (e.action != "") entryCount++;
  }

  // Process then delete (separate loop avoids fbdo buffer conflict)
  for (int i = 0; i < entryCount; i++) {
    CmdEntry& e = entries[i];
    Serial.printf("[FEEDER CMD] %s (mode=%s) id=%s\n",
                  e.action.c_str(), e.mode.c_str(), e.docId.c_str());

    if (e.action == "feed_now") {
      startFeed("manual");
    } else if (e.action == "set_mode" && e.mode != "") {
      feederAutoMode = (e.mode == "auto");
      Serial.printf("[FEEDER] Mode -> %s\n", feederAutoMode ? "AUTO" : "MANUAL");
    }

    String docPath = "tanks/" + currentTankId + "/pending_commands/" + e.docId;
    if (!Firebase.Firestore.deleteDocument(&fbdo, FIREBASE_PROJECT_ID, "",
                                           docPath.c_str())) {
      Serial.printf("[FEEDER] Delete cmd failed: %s\n", fbdo.errorReason().c_str());
    }
  }
}

// ─── Send Feeder Status to Firestore ───
// Path: tanks/{tankId}/feeder/status  (single document, patched in-place)
void sendFeederStatus() {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) return;   // no tank assigned -> nothing to report

  time_t now;
  time(&now);
  const String nowMs = epochMillisString(now);

  FirebaseJson json;
  // Match FeederService's canonical status fields and keep the heartbeat fresh.
  json.set("fields/status/stringValue", feederIsRunning ? "dispensing" : "idle");
  json.set("fields/isRunning/booleanValue", feederIsRunning);
  json.set("fields/feedSource/stringValue", feederFeedSource);
  json.set("fields/feedCount/integerValue", String(feederFeedCount));
  json.set("fields/hopperLevel/doubleValue", String(feederHopperLevel));
  json.set("fields/lastSeen/integerValue", nowMs);
  if (feederLastFeedEpoch > 0) {
    json.set("fields/last_dispensed_at/integerValue", epochMillisString((time_t)feederLastFeedEpoch));
  } else {
    json.set("fields/last_dispensed_at/nullValue", "NULL_VALUE");
  }
  json.set("fields/last_dispensed_grams/doubleValue", (feederIsRunning || feederLastFeedEpoch > 0) ? "20.0" : "0.0");

  String statusDoc = "tanks/" + currentTankId + "/feeder/status";
  if (!Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "",
        statusDoc.c_str(), json.raw(),
        "status,isRunning,feedSource,feedCount,hopperLevel,lastSeen,last_dispensed_at,last_dispensed_grams")) {
    if (fbdo.httpConnected()) {
      Serial.printf("[FEEDER STATUS ERROR] %s\n", fbdo.errorReason().c_str());
    }
  }
}

// ─── Sync Schedules from Firestore ───
// Reads all docs in tanks/{tankId}/feeder_schedules (max FEEDER_MAX_SCHEDULES).
void syncFeederSchedules() {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) return;   // no tank assigned -> nothing to sync

  String schedCol = "tanks/" + currentTankId + "/feeder_schedules";
  if (!Firebase.Firestore.listDocuments(&fbdo, FIREBASE_PROJECT_ID, "",
        schedCol.c_str(), FEEDER_MAX_SCHEDULES, "", "", "", false)) {
    feederScheduleCount = 0;
    return;
  }

  FirebaseJson response;
  response.setJsonData(fbdo.payload());
  FirebaseJsonData d;

  feederScheduleCount = 0;

  for (int i = 0; i < FEEDER_MAX_SCHEDULES; i++) {
    String namePath = String("documents/[") + i + "]/name";
    if (!response.get(d, namePath)) break;

    String docName = d.stringValue;
    int lastSlash  = docName.lastIndexOf('/');
    String docId   = (lastSlash >= 0) ? docName.substring(lastSlash + 1) : docName;

    FeedSchedule& s = feederSchedules[feederScheduleCount];
    s.key = docId;

    String base    = String("documents/[") + i + "]/fields/";
    String timeStr = "6:00";
    String ampm    = "AM";
    int timeValue  = -1;

    // Preferred source: timeValue (minutes since midnight) written by Flutter.
    if (response.get(d, base + "timeValue/integerValue")) {
      timeValue = d.stringValue.toInt();
    }

    // Fallbacks during migration/older app versions.
    if (response.get(d, base + "time/stringValue"))         timeStr = d.stringValue;
    if (response.get(d, base + "ampm/stringValue"))         ampm = d.stringValue;
    if (response.get(d, base + "feed_time/stringValue") && timeStr == "6:00") {
      timeStr = d.stringValue;
    }

    int hour = 6;
    int minute = 0;

    if (timeValue >= 0) {
      hour = timeValue / 60;
      minute = timeValue % 60;
    } else {
      int colon = timeStr.indexOf(':');
      if (colon < 0) continue;
      hour = timeStr.substring(0, colon).toInt();
      minute = timeStr.substring(colon + 1).toInt();

      // Convert 12-hour time + AM/PM into 24-hour time.
      if (ampm == "PM" && hour != 12) hour += 12;
      if (ampm == "AM" && hour == 12) hour = 0;
    }

    s.hour24  = hour;
    s.minute  = minute;
    s.enabled = true;
    if (response.get(d, base + "is_active/booleanValue")) s.enabled = d.boolValue;

    feederScheduleCount++;
  }

  Serial.printf("[FEEDER] Synced %d schedules from Firestore\n", feederScheduleCount);
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

      // Update hopper level and feed count
      feederHopperLevel -= 9;
      if (feederHopperLevel < 0) feederHopperLevel = 0;
      feederFeedCount++;

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

// ─── Push Feeding Log to Firestore ───
// Creates a new auto-ID document in tanks/{tankId}/feeder_logs.
void pushFeederLog(String action, String type) {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) return;   // no tank assigned -> nothing to log

  time_t now;
  time(&now);
  struct tm* timeinfo = localtime(&now);

  // Format time string
  int h12 = timeinfo->tm_hour % 12;
  if (h12 == 0) h12 = 12;
  String ampm = timeinfo->tm_hour >= 12 ? "PM" : "AM";
  char timeBuf[10];
  sprintf(timeBuf, "%d:%02d %s", h12, timeinfo->tm_min, ampm.c_str());

  // Format date string
  const char* months[] = {"Jan","Feb","Mar","Apr","May","Jun",
                           "Jul","Aug","Sep","Oct","Nov","Dec"};
  char dateBuf[20];
  sprintf(dateBuf, "%s %d, %d",
          months[timeinfo->tm_mon], timeinfo->tm_mday, 1900 + timeinfo->tm_year);

  const String epochMs = epochMillisString(now);

  FirebaseJson json;
  json.set("fields/action/stringValue",    action);
  json.set("fields/type/stringValue",      type);
  json.set("fields/time/stringValue",      String(timeBuf));
  json.set("fields/date/stringValue",      String(dateBuf));
  json.set("fields/timestamp/integerValue", String(epochMs));

  String logCollection = "tanks/" + currentTankId + "/feeder_logs";
  if (Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "",
        logCollection.c_str(), "", json.raw(), "")) {
    Serial.printf("[FEEDER LOG] %s\n", action.c_str());
  } else if (fbdo.httpConnected()) {
    Serial.printf("[FEEDER LOG ERROR] %s\n", fbdo.errorReason().c_str());
  }
}

// ============================================================
//  ACTUATOR MODULE — Water Pump + 2 Aerators
//  Firestore source of truth: tanks/{tankId}/actuators/{deviceId}
//    control_mode : "on" | "off" | "auto"   (written by Flutter Controls screen)
//    current_state: "on" | "off"            (ACTUAL relay state — ESP writes back)
//    last_changed : Timestamp (app) / epoch-ms int (ESP report)
//  Logs: tanks/{tankId}/actuator_logs  (ESP creates a doc on every state change)
//  Note: relays are ACTIVE-LOW — digitalWrite(LOW) turns the relay ON.
// ============================================================

// ─── Initialize relay pins (everything OFF at boot) ───
void initActuators() {
  for (int i = 0; i < 3; i++) {
    pinMode(actuators[i].pin, OUTPUT);
    digitalWrite(actuators[i].pin, HIGH);   // active-LOW: HIGH = relay OFF
    actuators[i].relayOn = false;
    actuators[i].cloudReported = true;      // nothing to report yet
    actuators[i].cloudReportedState = "off";
    actuators[i].lastChangeMs = 0;
  }
  Serial.println("[ACT] Relays initialized: pump=GPIO26, aerator1=GPIO27, aerator2=GPIO14 (all OFF)");
}

// ─── Apply physical relay state (active-LOW; no-op if unchanged) ───
void setActuatorRelay(int idx, bool on) {
  if (idx < 0 || idx > 2) return;
  ActuatorDevice& a = actuators[idx];
  if (a.relayOn == on) return;
  a.relayOn = on;
  digitalWrite(a.pin, on ? LOW : HIGH);     // LOW = relay ON
  a.lastChangeMs = millis();
  a.cloudReported = false;
  Serial.printf("[ACT] %s -> %s\n", a.label, on ? "ON" : "OFF");
}

// ─── AUTO rule per device (only used when control_mode == "auto") ───
// Sensor-driven with graceful fallbacks: when the dedicated sensor is not
// enabled (ENABLE_DO_SENSOR / ENABLE_WATER_LEVEL_SENSOR = 0) or not reading
// yet, the rule falls back to temperature (warm water holds less oxygen).
bool actuatorAutoTarget(int idx) {
  ActuatorDevice& a = actuators[idx];

  if (strcmp(a.deviceId, "pump") == 0) {
    // Pump: circulate/refill when water level is critically low,
    // or keep water moving when temperature is high (heat stress).
    if (ENABLE_WATER_LEVEL_SENSOR && waterLevelSensorOK &&
        waterLevelCm < waterLevelCriticalLow) return true;
    if (tempSensorOK && smoothedTemp > tempCriticalHigh) return true;
    return false;
  }

  if (strcmp(a.deviceId, "aerator1") == 0) {
    // Primary aerator: oxygen below threshold, or warm water.
    if (ENABLE_DO_SENSOR && doSensorOK && dissolvedOxygen < doCriticalLow) return true;
    if (tempSensorOK && smoothedTemp > tempCriticalHigh) return true;
    return false;
  }

  if (strcmp(a.deviceId, "aerator2") == 0) {
    // Secondary aerator: CRITICAL oxygen drop (extra boost), or heat stress.
    if (ENABLE_DO_SENSOR && doSensorOK &&
        dissolvedOxygen < (doCriticalLow - 1.5f)) return true;
    if (tempSensorOK && smoothedTemp > tempCriticalHigh) return true;
    return false;
  }

  return false;
}

// ─── Read control_mode for one device from Firestore ───
// Path: tanks/{tankId}/actuators/{deviceId}  -> fields/control_mode/stringValue
bool readActuatorMode(int idx, String& modeOut) {
  if (!ensureFirebaseReady()) return false;
  if (currentTankId.length() == 0) return false;

  String path = String("tanks/") + currentTankId + "/actuators/" + actuators[idx].deviceId;
  if (!Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "", path.c_str(), "")) {
    return false;   // doc may not exist yet — tank seeding happens on app side
  }
  FirebaseJson doc;
  doc.setJsonData(fbdo.payload());
  FirebaseJsonData d;
  if (!doc.get(d, "fields/control_mode/stringValue")) return false;
  modeOut = d.stringValue;
  return true;
}

// ─── Write back ACTUAL relay state to Firestore ───
// Firestore rules allow the anonymous ESP to update ONLY:
//   current_state + last_changed   (never control_mode)
void reportActuatorState(int idx, bool forced) {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) return;

  ActuatorDevice& a = actuators[idx];
  const String state = a.relayOn ? "on" : "off";

  if (!forced && a.cloudReported && a.cloudReportedState == state) return;

  time_t now;
  time(&now);
  const String nowMs = epochMillisString(now);

  FirebaseJson json;
  json.set("fields/current_state/stringValue", state);
  json.set("fields/last_changed/integerValue", nowMs);

  String path = String("tanks/") + currentTankId + "/actuators/" + a.deviceId;
  if (Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "",
        path.c_str(), json.raw(), "current_state,last_changed")) {
    a.cloudReported = true;
    a.cloudReportedState = state;
    Serial.printf("[ACT] Reported %s -> %s\n", a.label, state.c_str());
  } else if (fbdo.httpConnected()) {
    Serial.printf("[ACT REPORT ERROR] %s\n", fbdo.errorReason().c_str());
  }
}

// ─── Push an actuator log entry (auto-ID doc) ───
// Field names match Flutter ActuatorLogService:
//   actuator_type, action, log_level, message, type, time, date, timestamp(ms)
// Put "(AUTO)" in `action` so the app surfaces it as an auto-control event.
void pushActuatorLog(int idx, String action, String type, String level) {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) return;

  time_t now;
  time(&now);
  struct tm* timeinfo = localtime(&now);

  int h12 = timeinfo->tm_hour % 12;
  if (h12 == 0) h12 = 12;
  String ampm = timeinfo->tm_hour >= 12 ? "PM" : "AM";
  char timeBuf[10];
  sprintf(timeBuf, "%d:%02d %s", h12, timeinfo->tm_min, ampm.c_str());

  const char* months[] = {"Jan","Feb","Mar","Apr","May","Jun",
                           "Jul","Aug","Sep","Oct","Nov","Dec"};
  char dateBuf[20];
  sprintf(dateBuf, "%s %d, %d",
          months[timeinfo->tm_mon], timeinfo->tm_mday, 1900 + timeinfo->tm_year);

  const String epochMs = epochMillisString(now);

  FirebaseJson json;
  json.set("fields/actuator_type/stringValue", actuators[idx].deviceId);
  json.set("fields/action/stringValue",        action);
  json.set("fields/log_level/stringValue",     level);
  json.set("fields/message/stringValue",       action);
  json.set("fields/type/stringValue",          type);
  json.set("fields/time/stringValue",          String(timeBuf));
  json.set("fields/date/stringValue",          String(dateBuf));
  json.set("fields/timestamp/integerValue",    epochMs);
  // Also stamped as integer epoch-ms so both the Controls screen
  // (orders by timestamp) and the legacy actuatorLogsStream
  // (orders by logged_at) sort correctly.
  json.set("fields/logged_at/integerValue",    epochMs);

  String col = String("tanks/") + currentTankId + "/actuator_logs";
  if (Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "",
        col.c_str(), "", json.raw(), "")) {
    Serial.printf("[ACT LOG] %s\n", action.c_str());
  } else if (fbdo.httpConnected()) {
    Serial.printf("[ACT LOG ERROR] %s\n", fbdo.errorReason().c_str());
  }
}

// ─── Apply one device's mode -> relay, then report + log changes ───
void applyActuatorDevice(int idx) {
  ActuatorDevice& a = actuators[idx];
  bool target = false;
  String reason = "";
  String type = "auto";

  if (a.controlMode == "on") {
    target = true;
    type = "on";
    reason = "Manual ON";
  } else if (a.controlMode == "off") {
    target = false;
    type = "off";
    reason = "Manual OFF";
  } else {   // "auto" (or anything unknown)
    target = actuatorAutoTarget(idx);
    reason = target ? "Auto condition met" : "Auto condition clear";
  }

  const bool changed = (a.relayOn != target);
  setActuatorRelay(idx, target);

  if (changed) {
    // Action format matches what the app expects:
    //  - "Switched ON/OFF"  -> Controls screen runtime label
    //  - "(AUTO)"           -> ActuatorLogService auto-control event
    String action = String("Switched ") + (target ? "ON" : "OFF") + " — " + a.label;
    if (a.controlMode == "auto") action += String(" (AUTO) — ") + reason;
    pushActuatorLog(idx, action, type, "info");
  }
  reportActuatorState(idx, false);
}

// ─── Sync all 3 actuators from Firestore: read mode -> apply -> report ───
void syncActuatorsFromFirestore() {
  if (currentTankId.length() == 0) return;   // no tank assigned yet

  for (int i = 0; i < 3; i++) {
    String mode;
    if (readActuatorMode(i, mode)) {
      actuators[i].controlMode = mode;
    }
    applyActuatorDevice(i);
  }
}
