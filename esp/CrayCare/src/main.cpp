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
 * Production sensors:
 *  1. Temperature       : DS18B20 (GPIO 4)
 *  2. Turbidity         : DFRobot SEN0189 (GPIO 34)
 *  3. Dissolved Oxygen  : DFRobot SEN0237 analog (GPIO 36)
 *  4. pH Level          : DFRobot SEN0161 analog (GPIO 35)
 *  5. Water Level       : HC-SR04 TRIG 32 / ECHO 33
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
#include <vector>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include "secrets.h"   // Firebase credentials — gitignored (see secrets.h.example)

#ifndef FIREBASE_API_KEY
#error "secrets.h missing — copy include/secrets.h.example to include/secrets.h and fill in your values"
#endif

// ============================================================
//  WIFI SETTINGS — multi-profile, stored in NVS via Preferences
//  Namespace "wifiprof": count, active, ssid0/pass0 ... ssid4/pass4
//  First boot: Enter SSID + PASSWORD prompts over Serial Monitor
//  Add: "wifi add" (prompts) or "wifi set <SSID>|<PASS>" (one-line)
//  List: "wifilist"  Switch: "wifi use <n>"  Reset: "RESET_WIFI"
// ============================================================
Preferences prefs;
String ssid;
String pass;
#define WIFI_MAX_PROFILES 5

// ============================================================
//  FIREBASE SETTINGS
// ============================================================
// Firebase credentials (FIREBASE_API_KEY, FIREBASE_DATABASE_URL,
// FIREBASE_PROJECT_ID, SECRETS_FIREBASE_USER_EMAIL and
// SECRETS_FIREBASE_USER_PASSWORD) are defined in the gitignored secrets.h.
// Sensor snapshots are staged under sensorIngestion and routed by Cloud
// Functions. Device control/config paths use tanks/{currentTankId}/... directly.
// Hardware ID derived from MAC address on first use (see getHardwareId())
String hardwareId = "";
String currentTankId = "";
String currentOwnerUid;
long long currentAssignmentAtMs = 0;

// Firestore timestamps are UTC RFC3339; do not parse them with the Manila TZ.
long long firestoreTimestampMillis(const String& value) {
  int year, month, day, hour, minute, second;
  if (!value.endsWith("Z") || sscanf(value.c_str(), "%d-%d-%dT%d:%d:%d", &year, &month, &day, &hour, &minute, &second) != 6) return 0;
  if (year < 2020 || year > 2099 || month < 1 || month > 12 || hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) return 0;
  const int monthDays[] = {31,28,31,30,31,30,31,31,30,31,30,31};
  const bool leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  if (day < 1 || day > monthDays[month-1] + (month == 2 && leap ? 1 : 0)) return 0;
  const int y = year - (month <= 2 ? 1 : 0);
  const int era = y / 400;
  const int yoe = y - era * 400;
  const int doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1;
  const long long days = era * 146097LL + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468;
  int millisPart = 0;
  const int dot = value.indexOf('.');
  if (dot >= 0) {
    String fraction = value.substring(dot + 1, value.length() - 1);
    while (fraction.length() < 3) fraction += '0';
    millisPart = fraction.substring(0, 3).toInt();
  }
  return (days * 86400 + hour * 3600 + minute * 60 + second) * 1000 + millisPart;
}

#define FIREBASE_SEND_INTERVAL_MS 5000
#define HISTORY_SEND_INTERVAL_MS 600000  // 10 minutes; matches the documented schema
#define CONFIG_SYNC_INTERVAL_MS 10000
#define FLUSH_INTERVAL_MS 1000           // flush backlog at 1 entry/sec (max)
#define SENSOR_POLL_MS 2000

// Feeder timing
#define FEEDER_CMD_INTERVAL_MS 300
#define FEEDER_STATUS_INTERVAL_MS 5000
#define FEEDER_SCHEDULE_SYNC_MS 10000
#define FEEDER_SCHEDULE_CHECK_MS 1000
#define FEEDER_SERVO_PULSE_WIDTH 2000   // microseconds for full rotation
#define FEEDER_SCHEDULE_PAGE_SIZE 20

// Resolve tank_id from hardware_system/currentOwner (used for subcollection paths)
extern FirebaseData fbdo;
bool ensureFirebaseReady();
void applyTankAssignment(const String& tankId, const String& ownerUid = "", long long assignedAtMs = 0);
void fetchTankId() {
  if (!ensureFirebaseReady()) return;
  // Read hardware_system/currentOwner to get tank_id for subcollection paths
  if (!Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "",
        "hardware_system/currentOwner")) {
    if (fbdo.httpCode() == 404) applyTankAssignment("");
    return;
  }
  FirebaseJson resp;
  resp.setJsonData(fbdo.payload());
  FirebaseJsonData d;
  String assignedTank;
  String assignedOwner;
  if (resp.get(d, "fields/tank_id/stringValue")) assignedTank = d.stringValue;
  if (resp.get(d, "fields/uid/stringValue")) assignedOwner = d.stringValue;
  long long assignedAtMs = 0;
  if (resp.get(d, "fields/assigned_at/timestampValue") || resp.get(d, "updateTime")) {
    assignedAtMs = firestoreTimestampMillis(d.stringValue);
  }
  applyTankAssignment(assignedOwner.length() > 0 ? assignedTank : "", assignedOwner, assignedAtMs);
  Serial.printf("[ESP] Resolved tank_id = %s\n", currentTankId.c_str());
}

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

bool firebaseReady = false;
bool firebaseStarted = false;
unsigned long firebaseBeginStartedMs = 0;
unsigned long lastFirebaseAuthAttemptMs = 0;
volatile bool firebaseAuthAttemptFailed = false;
constexpr unsigned long FIREBASE_AUTH_RETRY_INTERVAL_MS = 15UL * 60UL * 1000UL;
bool cloudBootstrapComplete = false;
unsigned long lastFirebaseAuthReportMs = 0;
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

// Drop exactly the first valid line while preserving the entire backlog.
// The previous implementation rewrote only the first 32 loaded lines and
// silently discarded everything after them during a long outage.
bool bufferDropFirst(const String* ignoredLines, size_t ignoredCount) {
  (void)ignoredLines;
  (void)ignoredCount;
  if (!littlefsMounted) return false;
  const char* tempPath = "/buf/history.tmp";
  File src = LittleFS.open(BUFFER_PATH, "r");
  if (!src) return false;
  File dst = LittleFS.open(tempPath, "w");
  if (!dst) { src.close(); return false; }

  bool dropped = false;
  while (src.available()) {
    String line = src.readStringUntil('\n');
    line.trim();
    if (line.length() <= 10) continue;
    if (!dropped) { dropped = true; continue; }
    dst.println(line);
  }
  src.close();
  dst.close();
  if (!dropped) { LittleFS.remove(tempPath); return false; }
  LittleFS.remove(BUFFER_PATH);
  return LittleFS.rename(tempPath, BUFFER_PATH);
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
unsigned long lastWifiReconnectTime = 0;

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
unsigned long feederLastFeedEpoch = 0;
bool feederIsRunning = false;
String feederStatus = "idle";
String feederFeedSource = "";          // "manual" or "scheduled"
String feederLastScheduleKey = "";     // doc id of the schedule that triggered the latest scheduled feed
int feederDispenseCount = 0;              // total feeds dispensed since boot
float feederRequestedGrams = 20.0f;   // nominal estimate; verify 20 g/cycle on hardware
float feederFeedLevelBefore = -1.0f;
float feederAvailableBefore = -1.0f;
bool feederInitialized = false;
unsigned long feederLastScheduledMinute = 0;
unsigned long feederLastCompletedEpoch = 0;
float feederLastCompletedGrams = 0;
unsigned long feederEventSequence = 0;
unsigned long feederOccurrenceEpoch = 0;
String feederEventTank;
String feederEventKey;
String feederCommandId;
String feederStatusReason;
String feederScheduleTime;
bool feederWritingIntent = false;
bool feederConfigReady = false;

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
  float grams;
  String days;   // day-of-week mask "1111111" (Sunday first, '1'=active)
  unsigned long effectiveEpoch = 0;
};

int feederScheduleCount = 0;
std::vector<FeedSchedule> feederSchedules;

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
#define DO_PIN 36
#define PH_PIN 35
#define WATER_LEVEL_TRIG_PIN 32
#define WATER_LEVEL_ECHO_PIN 33
#define FEED_LEVEL_PIN 39  // ADC1 input-only pin (VN), safe while Wi-Fi is active

// Feeder
#define FEEDER_SERVO_PIN 13

// Actuator pins are defined with the ACTUATOR STATE block above.

// Set these to 1 after the actual sensor modules are connected and calibrated.
#define ENABLE_DO_SENSOR 1
#define ENABLE_PH_SENSOR 1
#define ENABLE_WATER_LEVEL_SENSOR 1
#define ENABLE_FEED_LEVEL_SENSOR 1

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

float feedLevelLowThreshold = 20.0;
float feedLevelCriticalThreshold = 10.0;
float hopperCapacityGrams = 1000.0;
// Calibrate these two voltages with an empty and a full hopper. Both sensor
// orientations are supported because the percentage formula uses their span.
float feedLevelEmptyVoltage = 0.50;
float feedLevelFullVoltage = 2.80;

float doVoltageScale = 4.0;
float doVoltageOffset = 0.0;
float phVoltageSlope = -5.70;
float phVoltageIntercept = 21.34;
// HC-SR04 mounting calibration (centimetres). The sensor is mounted above
// the tank bottom; depth = sensorHeight - measured air gap.
float waterSensorHeightCm = 65.0;
float waterLevelCmMin = 0.0;
float waterLevelCmMax = 23.0;

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
// Serial output is opt-in so continuous readings never interfere with commands.
// Sampling, Firestore uploads, buffering, and automation remain active.
bool sensorOutputEnabled = false;

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
// every 2 s, so each window collects up to ~300 samples.
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
float waterDistanceCm = -1.0;
bool waterLevelSensorOK = false;

float feedLevelPercent = -1.0;
float estimatedFeedGrams = -1.0;
float feedLevelVoltage = 0.0;
bool feedLevelSensorOK = false;

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

float saturationDOmgL(float tempC) {
  // Freshwater oxygen saturation approximation near sea level.
  const float t = constrain(tempC, 0.0f, 40.0f);
  return 14.652f - 0.41022f * t + 0.007991f * t * t -
         0.000077774f * t * t * t;
}

void saveSensorCalibrations() {
  prefs.begin("sensorcal", false);
  prefs.putFloat("phSlope", phVoltageSlope);
  prefs.putFloat("phIntercept", phVoltageIntercept);
  prefs.putFloat("doScale", doVoltageScale);
  prefs.putFloat("doOffset", doVoltageOffset);
  prefs.putFloat("tankHeight", waterSensorHeightCm);
  prefs.putFloat("tankDepth", waterLevelCmMax);
  prefs.putFloat("turbClear", turbidityVClear);
  prefs.putFloat("turbDirty", turbidityVDirty);
  prefs.putFloat("turbAir", turbidityVAirMax);
  prefs.putFloat("feedEmpty", feedLevelEmptyVoltage);
  prefs.putFloat("feedFull", feedLevelFullVoltage);
  prefs.end();
}

void loadSensorCalibrations() {
  prefs.begin("sensorcal", true);
  phVoltageSlope = prefs.getFloat("phSlope", phVoltageSlope);
  phVoltageIntercept = prefs.getFloat("phIntercept", phVoltageIntercept);
  doVoltageScale = prefs.getFloat("doScale", doVoltageScale);
  doVoltageOffset = prefs.getFloat("doOffset", doVoltageOffset);
  waterSensorHeightCm = prefs.getFloat("tankHeight", waterSensorHeightCm);
  waterLevelCmMax = prefs.getFloat("tankDepth", waterLevelCmMax);
  turbidityVClear = prefs.getFloat("turbClear", turbidityVClear);
  turbidityVDirty = prefs.getFloat("turbDirty", turbidityVDirty);
  turbidityVAirMax = prefs.getFloat("turbAir", turbidityVAirMax);
  feedLevelEmptyVoltage = prefs.getFloat("feedEmpty", feedLevelEmptyVoltage);
  feedLevelFullVoltage = prefs.getFloat("feedFull", feedLevelFullVoltage);
  prefs.end();
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
int wifiProfileCount() {
  prefs.begin("wifiprof", true);
  int n = prefs.getInt("count", 0);
  prefs.end();
  return constrain(n, 0, WIFI_MAX_PROFILES);
}

void wifiGetProfile(int idx, String &outSsid, String &outPass) {
  outSsid = "";
  outPass = "";
  if (idx < 0 || idx >= WIFI_MAX_PROFILES) return;
  prefs.begin("wifiprof", true);
  outSsid = prefs.getString(("ssid" + String(idx)).c_str(), "");
  outPass = prefs.getString(("pass" + String(idx)).c_str(), "");
  prefs.end();
  outSsid.trim();
}

int wifiActiveIndex() {
  prefs.begin("wifiprof", true);
  int a = prefs.getInt("active", 0);
  prefs.end();
  int n = wifiProfileCount();
  if (n == 0) return 0;
  return constrain(a, 0, n - 1);
}

void wifiSetActive(int idx) {
  prefs.begin("wifiprof", false);
  prefs.putInt("active", idx);
  prefs.end();
}

int wifiFindBySsid(const String &s) {
  int n = wifiProfileCount();
  for (int i = 0; i < n; i++) {
    String eSsid, ePass;
    wifiGetProfile(i, eSsid, ePass);
    if (eSsid == s) return i;
  }
  return -1;
}

int wifiSaveProfile(const String &s, const String &p) {
  if (s.length() == 0 || s.length() > 32 || p.length() > 64) return -1;
  int idx = wifiFindBySsid(s);
  if (idx >= 0) {
    prefs.begin("wifiprof", false);
    prefs.putString(("pass" + String(idx)).c_str(), p);
    prefs.putInt("active", idx);
    prefs.end();
    return idx;
  }
  int n = wifiProfileCount();
  if (n >= WIFI_MAX_PROFILES) {
    idx = wifiActiveIndex();
    prefs.begin("wifiprof", false);
    prefs.putString(("ssid" + String(idx)).c_str(), s);
    prefs.putString(("pass" + String(idx)).c_str(), p);
    prefs.putInt("active", idx);
    prefs.end();
    return idx;
  }
  prefs.begin("wifiprof", false);
  prefs.putString(("ssid" + String(n)).c_str(), s);
  prefs.putString(("pass" + String(n)).c_str(), p);
  prefs.putInt("count", n + 1);
  prefs.putInt("active", n);
  prefs.end();
  return n;
}

void wifiMigrateLegacy() {
  if (wifiProfileCount() > 0) return;
  prefs.begin("wifi", true);
  String oldSsid = prefs.getString("ssid", "");
  String oldPass = prefs.getString("pass", "");
  prefs.end();
  oldSsid.trim();
  if (oldSsid.length() > 0) {
    prefs.begin("wifiprof", false);
    prefs.putString("ssid0", oldSsid);
    prefs.putString("pass0", oldPass);
    prefs.putInt("count", 1);
    prefs.putInt("active", 0);
    prefs.end();
    Serial.printf("[WIFI] Migrated legacy \"%s\" to slot 0\n", oldSsid.c_str());
  }
}

void wifiPromptAndSave() {
  Serial.println("\n=== WIFI SETUP ===");
  Serial.println("Enter SSID:");
  while (!Serial.available()) delay(100);
  String s = Serial.readStringUntil('\n');
  s.trim();
  Serial.println(">> " + s);
  Serial.println("Enter PASSWORD:");
  while (!Serial.available()) delay(100);
  String p = Serial.readStringUntil('\n');
  p.trim();
  if (s.length() == 0) {
    Serial.println("[WIFI] Empty SSID — cancelled");
    return;
  }
  int idx = wifiSaveProfile(s, p);
  if (idx < 0) {
    Serial.println("[WIFI] Save failed — check length");
    return;
  }
  ssid = s;
  pass = p;
  Serial.printf("[SAVED] Slot %d \"%s\" — restarting...\n", idx, s.c_str());
  delay(1500);
  ESP.restart();
}

bool wifiTryOne(const String &s, const String &p) {
  WiFi.begin(s.c_str(), p.c_str());
  Serial.printf("[WIFI] Trying \"%s\"", s.c_str());
  for (int i = 0; i < 20; i++) {
    if (WiFi.status() == WL_CONNECTED) break;
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  return WiFi.status() == WL_CONNECTED;
}

void wifiListProfiles() {
  int n = wifiProfileCount();
  int a = wifiActiveIndex();
  if (n == 0) {
    Serial.println("[WIFI] No saved networks — type \"wifi add\"");
    return;
  }
  Serial.printf("[WIFI] %d saved:\n", n);
  for (int i = 0; i < n; i++) {
    String eSsid, ePass;
    wifiGetProfile(i, eSsid, ePass);
    Serial.printf("  %d: \"%s\"%s\n", i, eSsid.c_str(), (i == a) ? "  *active" : "");
  }
}

void wifiScanNetworks() {
  Serial.println("[WIFI] Scanning...");
  int n = WiFi.scanNetworks();
  if (n <= 0) {
    Serial.printf("[WIFI] No networks found (code=%d)\n", n);
  } else {
    Serial.printf("[WIFI] %d found:\n", n);
    for (int i = 0; i < n; i++) {
      Serial.printf("  \"%s\" (%d dBm) %s\n", WiFi.SSID(i).c_str(), WiFi.RSSI(i),
                    WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "OPEN" : "secure");
    }
  }
  WiFi.scanDelete();
}

void connectWiFi() {
  wifiMigrateLegacy();
  int n = wifiProfileCount();

  if (n == 0) {
    wifiPromptAndSave();
    return;
  }

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.disconnect(true, true);
  delay(200);

  int a = wifiActiveIndex();
  for (int k = 0; k < n; k++) {
    int idx = (a + k) % n;
    String s, p;
    wifiGetProfile(idx, s, p);
    if (s.length() == 0) continue;
    if (wifiTryOne(s, p)) {
      ssid = s;
      pass = p;
      wifiSetActive(idx);
      Serial.print("Connected! IP: ");
      Serial.println(WiFi.localIP());
      return;
    }
  }

  wifiGetProfile(a, ssid, pass);
  Serial.println("[WIFI] FAILED — all saved networks unreachable");
  Serial.println("Commands: WIFI_HELP | wifi set <SSID>|<PASS> | wifi list | wifi use <n> | wifiscan | RESET_WIFI");
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

void firebaseTokenStatusCallback(TokenInfo info) {
  if (info.error.code != 0) {
    firebaseAuthAttemptFailed = true;
    Serial.printf("[FIREBASE] error code=%d message=%s\n",
                  info.error.code, info.error.message.c_str());
    // Firebase-ESP-Client 4.4.17 otherwise loops forever on a rejected
    // email/password login. End this attempt; the main loop retries later.
    config.signer.tokens.status = token_status_ready;
    return;
  }
  Serial.printf("[FIREBASE] auth=%s | token=%s\n",
                getTokenStatus(info), getTokenType(info));
}

void connectFirebase() {
  if (firebaseStarted || WiFi.status() != WL_CONNECTED) return;

  config.api_key = FIREBASE_API_KEY;
  config.database_url = FIREBASE_DATABASE_URL;
  // This callback is throttled above so authentication progress stays visible
  // without flooding the Serial Monitor on repeated retries.
  config.token_status_callback = firebaseTokenStatusCallback;

  auth.user.email = SECRETS_FIREBASE_USER_EMAIL;
  auth.user.password = SECRETS_FIREBASE_USER_PASSWORD;

  Firebase.reconnectWiFi(true);
  firebaseStarted = true;
  firebaseBeginStartedMs = millis();
  firebaseAuthAttemptFailed = false;
  firebaseReady = false;
  Serial.println("[FIREBASE] Starting device authentication...");
  Firebase.begin(&config, &auth);
  Firebase.setDoubleDigits(2);
  lastFirebaseAuthAttemptMs = millis();
  if (firebaseAuthAttemptFailed) {
    config.signer.tokens.status = token_status_error;
    Serial.println("[FIREBASE] Login rejected; next automatic attempt is in 15 minutes.");
  }
  Serial.printf("[FIREBASE] Initial attempt returned after %lu ms; retries are limited to once per minute.\n",
                lastFirebaseAuthAttemptMs - firebaseBeginStartedMs);
}

void printFirebaseAuthStatus() {
  if (!firebaseStarted) {
    Serial.println("[FIREBASE] Not started; waiting for Wi-Fi.");
    return;
  }
  TokenInfo info = Firebase.authTokenInfo();
  Serial.printf("[FIREBASE] auth=%s | token=%s | Wi-Fi=%s\n",
                getTokenStatus(info), getTokenType(info),
                WiFi.status() == WL_CONNECTED ? "connected" : "offline");
  if (info.error.code != 0) {
    Serial.printf("[FIREBASE] error code=%d message=%s\n",
                  info.error.code, info.error.message.c_str());
  }
}

// Read a float from a Firestore document already loaded into `doc`.
// jsonPath is the full dotted path, e.g. "fields/turbidityVClear/doubleValue".
bool readConfigFloatPath(FirebaseJson& doc, const char* jsonPath,
                         float& target, float minValue, float maxValue) {
  FirebaseJsonData d;
  float value;
  if (doc.get(d, jsonPath)) {
    value = d.floatValue;
  } else {
    String integerPath = jsonPath;
    integerPath.replace("/doubleValue", "/integerValue");
    if (!doc.get(d, integerPath)) return false;
    value = d.stringValue.toFloat();
  }
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

bool syncFeedLevelConfig() {
  String path = String("tanks/") + currentTankId + "/sensors/feed_level";
  if (!Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "", path.c_str(), "")) {
    return false;
  }
  FirebaseJson doc;
  doc.setJsonData(fbdo.payload());
  float low = feedLevelLowThreshold;
  float critical = feedLevelCriticalThreshold;
  float capacity = hopperCapacityGrams;
  const bool gotLow = readConfigFloatPath(
    doc, "fields/min_value/doubleValue", low, 1.0f, 50.0f);
  const bool gotCritical = readConfigFloatPath(
    doc, "fields/critical_value/doubleValue", critical, 0.0f, 49.0f);
  const bool gotCapacity = readConfigFloatPath(
    doc, "fields/hopper_capacity_grams/doubleValue", capacity, 100.0f, 50000.0f);
  if (!gotLow || !gotCritical || !gotCapacity || critical >= low) {
    Serial.println("[CONFIG] Invalid feed-level settings; retaining previous values.");
    return false;
  }
  feedLevelLowThreshold = low;
  feedLevelCriticalThreshold = critical;
  hopperCapacityGrams = capacity;
  return true;
}

// Thresholds are owned by the currently assigned tank. The ESP obtains its
// tank ID from hardware_system/currentOwner, never from a user UID.
void syncConfigFromFirebase() {
  fetchTankId();
  if (currentTankId.length() == 0) {
    if (sensorOutputEnabled) Serial.println("[CONFIG] No tank assigned; retaining firmware defaults.");
    return;
  }

  bool changed = true;
  changed &= syncTankRange("temperature",       tempCriticalLow,       tempCriticalHigh,       0.0,   50.0);
  changed &= syncTankRange("turbidity",         turbNtuMin,            turbNtuMax,             0.0, 1000.0);
  changed &= syncTankRange("dissolved_oxygen",  doCriticalLow,         doCriticalHigh,          0.0,   30.0);
  changed &= syncTankRange("ph_level",          phCriticalLow,         phCriticalHigh,          0.0,   14.0);
  changed &= syncTankRange("water_level",       waterLevelCriticalLow, waterLevelCriticalHigh,  0.0,  300.0);
  changed &= syncFeedLevelConfig();
  // Keep a known-good same-tank configuration through temporary outages, but
  // require a complete fresh sync after startup or assignment changes.
  if (changed) feederConfigReady = true;

  if (changed) {
    Serial.printf("[CONFIG] Tank %s | Temp %.1f-%.1f | Turb %.0f-%.0f | DO %.1f-%.1f | pH %.1f-%.1f | Water %.1f-%.1fcm\n",
                  currentTankId.c_str(), tempCriticalLow, tempCriticalHigh,
                  turbNtuMin, turbNtuMax, doCriticalLow, doCriticalHigh,
                  phCriticalLow, phCriticalHigh, waterLevelCriticalLow, waterLevelCriticalHigh);
    Serial.printf("[CONFIG] Feed low <%.0f%% | critical <%.0f%% | capacity %.0fg\n",
                  feedLevelLowThreshold, feedLevelCriticalThreshold,
                  hopperCapacityGrams);
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
  // A failed email/password sign-in can otherwise be retried by every cloud
  // call in loop(), quickly triggering Identity Toolkit rate limiting.
  if (!Firebase.authenticated()) {
    if (millis() - lastFirebaseAuthAttemptMs < FIREBASE_AUTH_RETRY_INTERVAL_MS) {
      firebaseReady = false;
      return false;
    }
    firebaseAuthAttemptFailed = false;
    Serial.println("[FIREBASE] Retrying device authentication...");
    Firebase.begin(&config, &auth);
    lastFirebaseAuthAttemptMs = millis();
    if (firebaseAuthAttemptFailed) {
      config.signer.tokens.status = token_status_error;
      Serial.println("[FIREBASE] Login still rejected; waiting 15 minutes before another retry.");
      firebaseReady = false;
      return false;
    }
  }
  if (Firebase.ready()) {
    firebaseReady = true;
    return true;
  }
  // Firebase-ESP-Client refreshes the email/password token automatically.
  // Do not call signUp here: that API creates accounts and is incorrect for
  // the already-provisioned esp32@craycare.com service account.
  firebaseReady = false;
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
  json.set("fields/source_tank_id/stringValue", currentTankId);
  json.set("fields/source_owner_uid/stringValue", currentOwnerUid);
  json.set("fields/source_assignment_at_ms/integerValue", String(currentAssignmentAtMs));
  time_t capturedAt;
  time(&capturedAt);
  json.set("fields/captured_at_ms/integerValue", epochMillisString(capturedAt));

  if (!includeTimestamp) {
    // ── 5-sec LIVE payload: current smoothed values (dashboard display). ──
    json.set("fields/temperature/doubleValue", tempSensorOK ? smoothedTemp : -1.0f);

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
    if (ENABLE_FEED_LEVEL_SENSOR && feedLevelSensorOK) {
      json.set("fields/feed_level/doubleValue", feedLevelPercent);
      json.set("fields/estimated_feed_grams/doubleValue", estimatedFeedGrams);
    }
    return;
  }

  // ── 10-min HISTORY payload: per-sensor window aggregates. ────────────
  // Structure per sensor: MIN, MAX, AVG (in that order — avg NOT first).
  // The window accumulators hold every ACCEPTED reading since the last
  // history save (up to ~300 samples at 2s poll), so brief spikes
  // inside the window are preserved (e.g. temp_max catches a spike that
  // the snapshot at save time would miss). Sensors with zero accepted samples are omitted
  // instead of writing stale fallback values.

  // Only include sensors that had valid samples in this 10-minute window.
  if (winTempN > 0) {
    json.set("fields/temp_min/doubleValue", winTempMin);
    json.set("fields/temp_max/doubleValue", winTempMax);
    json.set("fields/temp_avg/doubleValue", winTempSum / (float)winTempN);
  }
  if (winTurbN > 0) {
    json.set("fields/turbidity_min/doubleValue", winTurbMin);
    json.set("fields/turbidity_max/doubleValue", winTurbMax);
    json.set("fields/turbidity_avg/doubleValue", winTurbSum / (float)winTurbN);
  }
  if (ENABLE_DO_SENSOR && winDON > 0) {
    json.set("fields/DO_min/doubleValue", winDOMin);
    json.set("fields/DO_max/doubleValue", winDOMax);
    json.set("fields/DO_avg/doubleValue", winDOSum / (float)winDON);
  }
  if (ENABLE_PH_SENSOR && winPHN > 0) {
    json.set("fields/pH_min/doubleValue", winPHMin);
    json.set("fields/pH_max/doubleValue", winPHMax);
    json.set("fields/pH_avg/doubleValue", winPHSum / (float)winPHN);
  }
  if (ENABLE_WATER_LEVEL_SENSOR && winWaterN > 0) {
    json.set("fields/waterLevel_min/doubleValue", winWaterMin);
    json.set("fields/waterLevel_max/doubleValue", winWaterMax);
    json.set("fields/waterLevel_avg/doubleValue", winWaterSum / (float)winWaterN);
  }
  if (ENABLE_FEED_LEVEL_SENSOR && feedLevelSensorOK) {
    json.set("fields/feed_level/doubleValue", feedLevelPercent);
    json.set("fields/estimated_feed_grams/doubleValue", estimatedFeedGrams);
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
  if (WiFi.status() != WL_CONNECTED || !ensureFirebaseReady()) {
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
    if (sensorOutputEnabled) Serial.printf("[TEMP SKIP] out of bounds: %.1f\n", rawTemp);
    return;
  }

  bool accept = true;

  if (lastValidTemp > -100.0) {
    float jump = fabs(rawTemp - lastValidTemp);

    if (jump > TEMP_JUMP_MAX) {
      accept = false;
      if (sensorOutputEnabled) Serial.printf("[TEMP SKIP] jump too large: %.2f\n", jump);
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
      if (sensorOutputEnabled) Serial.println("[TEMP] Watchdog override — forcing new baseline.");
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
    if (sensorOutputEnabled) Serial.printf("[TURB] Air/no water (V=%.3f)\n", voltage);
    return;
  }

  bool accept = true;

  if (lastValidTurbidityNTU >= 0.0) {
    float jump = fabs(tr.ntu - lastValidTurbidityNTU);

    if (jump > TURB_NTU_JUMP_MAX) {
      accept = false;
      if (sensorOutputEnabled) Serial.printf("[TURB SKIP] NTU jump too large: %.1f\n", jump);
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
      if (sensorOutputEnabled) Serial.println("[TURB] Watchdog override — forcing new baseline.");
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
  if (dissolvedOxygenVoltage < 0.05f || dissolvedOxygenVoltage > 3.25f) {
    dissolvedOxygen = -1.0f;
    doSensorOK = false;
    if (sensorOutputEnabled) Serial.printf("[DO] Invalid/disconnected voltage: %.3fV\n", dissolvedOxygenVoltage);
    return;
  }
  dissolvedOxygen = dissolvedOxygenVoltage * doVoltageScale + doVoltageOffset;
  if (!isfinite(dissolvedOxygen) || dissolvedOxygen < 0.0f || dissolvedOxygen > 20.0f) {
    dissolvedOxygen = -1.0f;
    doSensorOK = false;
    return;
  }
  doSensorOK = true;
  ACCUM_WINDOW(winDOSum, winDON, winDOMin, winDOMax, dissolvedOxygen);
}

void readPHSensor() {
  if (!ENABLE_PH_SENSOR) {
    phLevel = -1.0;
    return;
  }

  phVoltage = readAnalogVoltage(PH_PIN);
  if (phVoltage < 0.05f || phVoltage > 3.25f) {
    phLevel = -1.0f;
    phSensorOK = false;
    if (sensorOutputEnabled) Serial.printf("[PH] Invalid/disconnected voltage: %.3fV\n", phVoltage);
    return;
  }
  phLevel = phVoltageSlope * phVoltage + phVoltageIntercept;
  if (!isfinite(phLevel) || phLevel < 0.0f || phLevel > 14.0f) {
    phLevel = -1.0f;
    phSensorOK = false;
    return;
  }
  phSensorOK = true;
  ACCUM_WINDOW(winPHSum, winPHN, winPHMin, winPHMax, phLevel);
}

void readWaterLevelSensor() {
  if (!ENABLE_WATER_LEVEL_SENSOR) {
    waterLevelCm = -1.0;
    waterLevelSensorOK = false;
    return;
  }

  digitalWrite(WATER_LEVEL_TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(WATER_LEVEL_TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(WATER_LEVEL_TRIG_PIN, LOW);

  // Timeout prevents a missing/disconnected echo from blocking the control loop.
  const unsigned long durationUs = pulseIn(WATER_LEVEL_ECHO_PIN, HIGH, 30000UL);
  if (durationUs == 0) {
    waterDistanceCm = -1.0;
    waterLevelCm = -1.0;
    waterLevelSensorOK = false;
    if (sensorOutputEnabled) Serial.println("[WATER] HC-SR04 timeout/disconnected");
    return;
  }

  waterDistanceCm = durationUs * 0.0343f / 2.0f;
  const float depth = waterSensorHeightCm - waterDistanceCm;
  // Reject impossible geometry instead of constraining a bad echo into a
  // believable value that could start the pump.
  if (depth < waterLevelCmMin - 2.0f || depth > waterLevelCmMax + 2.0f) {
    waterLevelCm = -1.0;
    waterLevelSensorOK = false;
    if (sensorOutputEnabled) {
      Serial.printf("[WATER] Invalid echo: distance=%.1fcm depth=%.1fcm\n",
                    waterDistanceCm, depth);
    }
    return;
  }

  waterLevelCm = constrain(depth, waterLevelCmMin, waterLevelCmMax);
  waterLevelSensorOK = true;
  ACCUM_WINDOW(winWaterSum, winWaterN, winWaterMin, winWaterMax, waterLevelCm);
}

void readFeedLevelSensor() {
  if (!ENABLE_FEED_LEVEL_SENSOR) {
    feedLevelSensorOK = false;
    feedLevelPercent = -1.0f;
    estimatedFeedGrams = -1.0f;
    return;
  }

  feedLevelVoltage = readAnalogVoltage(FEED_LEVEL_PIN);
  const float span = feedLevelFullVoltage - feedLevelEmptyVoltage;
  if (!isfinite(feedLevelVoltage) || fabs(span) < 0.05f ||
      feedLevelVoltage < 0.02f || feedLevelVoltage > 3.28f) {
    feedLevelSensorOK = false;
    feedLevelPercent = -1.0f;
    estimatedFeedGrams = -1.0f;
    Serial.printf("[FEED LEVEL] Invalid/disconnected voltage: %.3fV\n",
                  feedLevelVoltage);
    return;
  }

  feedLevelPercent = constrain(
    (feedLevelVoltage - feedLevelEmptyVoltage) * 100.0f / span,
    0.0f,
    100.0f);
  estimatedFeedGrams = hopperCapacityGrams * feedLevelPercent / 100.0f;
  feedLevelSensorOK = true;
}

void readAllSensors() {
  readTemperatureSensor();
  readTurbiditySensor();
  readDissolvedOxygenSensor();
  readPHSensor();
  readWaterLevelSensor();
  readFeedLevelSensor();
}

void printSensorReading() {
  Serial.printf("[SENSOR] Temp: %.1f C | Turb: %.0f NTU (%.3fV) | DO: %.1f mg/L | pH: %.2f | Level: %.1f cm | Feed: %.1f%%\n",
                smoothedTemp, smoothedTurbidityNTU, turbidityVoltage,
                dissolvedOxygen, phLevel, waterLevelCm, feedLevelPercent);
}

void printCalibrationHelp() {
  Serial.println("\n=== CALIBRATION COMMANDS ===");
  Serial.println("phcal7                  Save voltage in pH 7 buffer");
  Serial.println("phcal4                  Save voltage in pH 4 buffer");
  Serial.println("doread                   Show current DO voltage/value");
  Serial.println("doclear                  Calibrate DO in air-saturated water");
  Serial.println("turbclear <VOLTS>        Set clear-water voltage");
  Serial.println("turbdirty <VOLTS>        Set dirty-water voltage");
  Serial.println("turbair <VOLTS>          Set out-of-water threshold");
  Serial.println("tankheight <CM>          Sensor-to-tank-bottom distance");
  Serial.println("tankdepth <CM>           Maximum water depth");
  Serial.println("tankcal                  Show tank calibration");
  Serial.println("raw                      Show one raw reading");
}

void printSerialHelp() {
  Serial.println("\n=== SERIAL COMMANDS ===");
  Serial.println("HELP                     Show this menu");
  Serial.println("SENSOR_ON                Print readings every 2 seconds");
  Serial.println("SENSOR_OFF               Stop periodic sensor printing");
  Serial.println("SENSOR_READ              Take and print one fresh reading");
  Serial.println("CAL_HELP                 Show calibration commands");
  Serial.println("WIFI_HELP                Show Wi-Fi commands");
  Serial.println("FIREBASE_STATUS          Show cloud authentication status");
  Serial.println("FEED                     Start a manual feed");
  Serial.println("relay status             Show relay states");
}

void printWifiHelp() {
  Serial.println("\n=== WI-FI COMMANDS ===");
  Serial.println("wifi add                 Guided SSID/password entry");
  Serial.println("wifi set <SSID>|<PASS>   Save in one line (SSID may contain spaces)");
  Serial.println("wifi list / wifilist     List saved networks");
  Serial.println("wifi use <INDEX>         Switch saved network");
  Serial.println("wifi delete <INDEX>      Delete saved network");
  Serial.println("wifiscan                 Scan nearby networks");
  Serial.println("wifi status              Show current connection");
  Serial.println("RESET_WIFI               Erase every saved network");
}

// ─── Feeder forward declarations ───
void initFeeder();
void processFeederCommands();
void sendFeederStatus();
void syncFeederSchedules();
void loadCachedFeederSchedules();
void saveCachedFeederSchedules();
void loadFeederState();
bool saveFeederState();
void checkScheduledFeed();
void startFeed(String source, float grams = 20.0f, String commandId = "", long long issuedAtMs = 0, long long expiresAtMs = 0);
void processFeederTick();
void pushFeederLog(String action, String type, String status = "",
                   float requestedGrams = -1.0f,
                   float availableGrams = -1.0f,
                   float levelBefore = -1.0f,
                   float levelAfter = -1.0f);
bool flushOneFeederLog();
void recoverFeederLogs();

// ─── Actuator forward declarations ───
void initActuators();
void syncActuatorsFromFirestore();
void applyActuatorDevice(int idx);
bool actuatorAutoTarget(int idx);
void setActuatorRelay(int idx, bool on);
void reportActuatorState(int idx, bool forced);
void pushActuatorLog(int idx, String action, String type);

// ============================================================
//  SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  pinMode(WATER_LEVEL_TRIG_PIN, OUTPUT);
  digitalWrite(WATER_LEVEL_TRIG_PIN, LOW);
  pinMode(WATER_LEVEL_ECHO_PIN, INPUT);
  pinMode(FEED_LEVEL_PIN, INPUT);

  sensors.begin();
  loadSensorCalibrations();

  primeTemperatureBuffer();
  primeTurbidityBuffer();

  connectWiFi();
  initOfflineBuffer();  // LittleFS store-and-forward (mounted before loop)
  getHardwareId();  // resolve MAC-based ID after WiFi is up
  initFeeder();
  initActuators();
  if (WiFi.status() == WL_CONNECTED) {
    initTime();
    connectFirebase();
  } else {
    Serial.println("[CLOUD] Offline startup skipped; serial commands are ready now.");
  }

  Serial.println("============================================");
  Serial.println("  CrayCare Monitor — Firestore Ingestion");
  Serial.printf("  Hardware ID : %s\n", hardwareId.c_str());
  Serial.printf("  Tank ID     : %s\n", currentTankId.c_str());
  Serial.printf("  Tank config : tanks/%s/sensors\n", currentTankId.c_str());
  Serial.println("  Turbidity: NTU (calibrated)");
  Serial.println("  Sensor display: OFF (type HELP for commands)");
  Serial.println("============================================");
}

// ============================================================
//  LOOP
// ============================================================
void loop() {
  // Motor timing must never wait behind a blocking cloud/sensor operation.
  if (feederRunState != FEEDER_IDLE) {
    processFeederTick();
    delay(1);
    return;
  }
  unsigned long now = millis();

  // ─── Serial Commands ───
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd == "HELP" || cmd == "help" || cmd == "?") {
      printSerialHelp();
    }
    if (cmd == "SENSOR_ON" || cmd == "sensor on") {
      sensorOutputEnabled = true;
      Serial.println("[SENSOR] Periodic display ON");
    }
    if (cmd == "SENSOR_OFF" || cmd == "sensor off") {
      sensorOutputEnabled = false;
      Serial.println("[SENSOR] Periodic display OFF; sensing and uploads remain active");
    }
    if (cmd == "SENSOR_READ" || cmd == "sensor read") {
      readAllSensors();
      printSensorReading();
    }
    if (cmd == "CAL_HELP" || cmd == "cal help") printCalibrationHelp();
    if (cmd == "WIFI_HELP" || cmd == "wifi help") printWifiHelp();
    if (cmd == "FIREBASE_STATUS" || cmd == "firebase status") {
      printFirebaseAuthStatus();
    }
    if (cmd == "RESET_WIFI") {
      prefs.begin("wifiprof", false);
      prefs.clear();
      prefs.end();
      prefs.begin("wifi", false);
      prefs.clear();
      prefs.end();
      Serial.println("[WIFI] All credentials erased. Restarting...");
      delay(1500);
      ESP.restart();
    }
    if (cmd == "wifi add") {
      wifiPromptAndSave();
    }
    if (cmd.startsWith("wifi set ")) {
      String rest = cmd.substring(9);
      rest.trim();
      int separator = rest.indexOf('|');
      if (separator < 1) {
        Serial.println("Usage: wifi set <SSID>|<PASS>");
      } else {
        String s = rest.substring(0, separator);
        String p = rest.substring(separator + 1);
        s.trim(); p.trim();
        int idx = wifiSaveProfile(s, p);
        if (idx < 0) {
          Serial.println("[WIFI] Save failed — check SSID/PASS length");
        } else {
          Serial.printf("[WIFI] Saved slot %d \"%s\" — restarting...\n", idx, s.c_str());
          delay(1500);
          ESP.restart();
        }
      }
    }
    if (cmd == "wifilist" || cmd == "wifi list") {
      wifiListProfiles();
    }
    if (cmd.startsWith("wifi use ")) {
      int idx = cmd.substring(9).toInt();
      int n = wifiProfileCount();
      if (idx < 0 || idx >= n) {
        Serial.printf("Usage: wifi use 0-%d (see wifilist)\n", n - 1);
      } else {
        wifiSetActive(idx);
        String s, p;
        wifiGetProfile(idx, s, p);
        Serial.printf("[WIFI] Switching to slot %d \"%s\"...\n", idx, s.c_str());
        delay(500);
        ESP.restart();
      }
    }
    if (cmd.startsWith("wifi delete ") || cmd.startsWith("wifi del ")) {
      int sp = cmd.lastIndexOf(' ');
      int idx = cmd.substring(sp + 1).toInt();
      int n = wifiProfileCount();
      if (idx < 0 || idx >= n) {
        Serial.printf("Usage: wifi delete 0-%d\n", n - 1);
      } else {
        prefs.begin("wifiprof", false);
        for (int i = idx; i < n - 1; i++) {
          prefs.putString(("ssid" + String(i)).c_str(), prefs.getString(("ssid" + String(i + 1)).c_str(), ""));
          prefs.putString(("pass" + String(i)).c_str(), prefs.getString(("pass" + String(i + 1)).c_str(), ""));
        }
        prefs.remove(("ssid" + String(n - 1)).c_str());
        prefs.remove(("pass" + String(n - 1)).c_str());
        prefs.putInt("count", n - 1);
        if (wifiActiveIndex() >= n - 1) prefs.putInt("active", 0);
        prefs.end();
        Serial.printf("[WIFI] Deleted slot %d\n", idx);
        wifiListProfiles();
      }
    }
    if (cmd == "wifiscan" || cmd == "wifi scan") {
      wifiScanNetworks();
    }
    if (cmd == "wifistatus" || cmd == "wifi status") {
      Serial.printf("[WIFI] %s | IP=%s | RSSI=%d dBm | SSID=\"%s\"\n",
                    WiFi.status() == WL_CONNECTED ? "CONNECTED" : "OFFLINE",
                    WiFi.localIP().toString().c_str(), WiFi.RSSI(), ssid.c_str());
      wifiListProfiles();
    }
    if (cmd == "FEED") {
      startFeed("manual");
      if (feederRunState != FEEDER_IDLE) return;
    }
    if (cmd.startsWith("tankheight ")) {
      const float v = cmd.substring(11).toFloat();
      if (v > 5.0f && v < 400.0f) {
        waterSensorHeightCm = v;
        saveSensorCalibrations();
        Serial.printf("[CAL] HC-SR04 height = %.1f cm\n", v);
      }
    }
    if (cmd.startsWith("tankdepth ")) {
      const float v = cmd.substring(10).toFloat();
      if (v > 1.0f && v < waterSensorHeightCm) {
        waterLevelCmMax = v;
        saveSensorCalibrations();
        Serial.printf("[CAL] Tank max depth = %.1f cm\n", v);
      }
    }
    if (cmd == "tankcal") {
      Serial.printf("[CAL] sensorHeight=%.1fcm maxDepth=%.1fcm lastDistance=%.1fcm\n",
                    waterSensorHeightCm, waterLevelCmMax, waterDistanceCm);
    }
    if (cmd == "phcal7" || cmd == "phcal4") {
      const float v = readAnalogVoltage(PH_PIN);
      prefs.begin("sensorcal", false);
      prefs.putFloat(cmd == "phcal7" ? "phV7" : "phV4", v);
      const float v7 = prefs.getFloat("phV7", -1.0f);
      const float v4 = prefs.getFloat("phV4", -1.0f);
      prefs.end();
      if (v7 > 0.0f && v4 > 0.0f && fabs(v7 - v4) > 0.05f) {
        phVoltageSlope = 3.0f / (v7 - v4);
        phVoltageIntercept = 7.0f - phVoltageSlope * v7;
        saveSensorCalibrations();
        Serial.printf("[CAL] pH two-point saved: slope=%.4f intercept=%.4f\n",
                      phVoltageSlope, phVoltageIntercept);
      } else {
        Serial.printf("[CAL] Saved %s voltage %.3fV; calibrate the other buffer next.\n",
                      cmd.c_str(), v);
      }
    }
    if (cmd == "doread") {
      Serial.printf("[CAL] DO raw=%.3fV current=%.2fmg/L temp=%.1fC\n",
                    dissolvedOxygenVoltage, dissolvedOxygen, smoothedTemp);
    }
    if (cmd == "doclear") {
      const float v = readAnalogVoltage(DO_PIN);
      if (v > 0.05f) {
        doVoltageScale = saturationDOmgL(smoothedTemp) / v;
        doVoltageOffset = 0.0f;
        saveSensorCalibrations();
        Serial.printf("[CAL] DO air calibration saved: scale=%.4f\n", doVoltageScale);
      }
    }
    if (cmd.startsWith("turbclear ")) {
      turbidityVClear = cmd.substring(10).toFloat();
      saveSensorCalibrations();
    }
    if (cmd.startsWith("turbdirty ")) {
      turbidityVDirty = cmd.substring(10).toFloat();
      saveSensorCalibrations();
    }
    if (cmd.startsWith("turbair ")) {
      turbidityVAirMax = cmd.substring(8).toFloat();
      saveSensorCalibrations();
    }
    if (cmd == "feedempty") {
      feedLevelEmptyVoltage = readAnalogVoltage(FEED_LEVEL_PIN);
      saveSensorCalibrations();
      Serial.printf("[CAL] Feed hopper EMPTY = %.3fV\n", feedLevelEmptyVoltage);
    }
    if (cmd == "feedfull") {
      feedLevelFullVoltage = readAnalogVoltage(FEED_LEVEL_PIN);
      saveSensorCalibrations();
      Serial.printf("[CAL] Feed hopper FULL = %.3fV\n", feedLevelFullVoltage);
    }
    if (cmd == "raw") {
      Serial.printf("[RAW] pH=%.3fV DO=%.3fV Turb=%.3fV HC-SR04=%.1fcm Water=%.1fcm Feed=%.3fV/%.0f%%/~%.0fg\n",
                    phVoltage, dissolvedOxygenVoltage, turbidityVoltage,
                    waterDistanceCm, waterLevelCm, feedLevelVoltage,
                    feedLevelPercent, estimatedFeedGrams);
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

  // Never stop sensing/local automation just because Wi-Fi is down. The old
  // early return prevented history buffering and scheduled feeding offline.
  const bool networkAvailable = WiFi.status() == WL_CONNECTED;
  if (!networkAvailable && now - lastWifiReconnectTime >= 10000UL) {
    lastWifiReconnectTime = now;
    if (sensorOutputEnabled) {
      Serial.println("[WIFI] Offline — local sensing/automation continues; reconnecting...");
    }
    WiFi.reconnect();
  }

  // Start Firebase only after Wi-Fi exists. Never block serial commands while
  // offline or while email/password authentication is still in progress.
  if (networkAvailable && !firebaseStarted) connectFirebase();
  if (networkAvailable && firebaseStarted && !cloudBootstrapComplete &&
      now - lastFirebaseAuthReportMs >= 10000UL) {
    lastFirebaseAuthReportMs = now;
    printFirebaseAuthStatus();
  }
  if (networkAvailable && firebaseStarted && !cloudBootstrapComplete &&
      ensureFirebaseReady()) {
    firebaseReady = true;
    fetchTankId();
    syncConfigFromFirebase();
    syncFeederSchedules();
    cloudBootstrapComplete = true;
    Serial.println("[FIREBASE] Connected; cloud control is active.");
    now = millis();
  }

  // ─── Feeder ───
  // Observe assignment changes before consuming commands or running a plan.
  if (now - lastConfigSyncTime >= CONFIG_SYNC_INTERVAL_MS) {
    lastConfigSyncTime = now;
    syncConfigFromFirebase();
    now = millis();
  }
  // Cloud commands/status/schedule refresh need network. Already-synced
  // schedules continue to execute locally below while offline.
  if (networkAvailable && now - lastFeederCmdCheckMs >= FEEDER_CMD_INTERVAL_MS) {
    lastFeederCmdCheckMs = now;
    processFeederCommands();
    if (feederRunState != FEEDER_IDLE) return;
  }

  if (networkAvailable && now - lastFeederStatusMs >= FEEDER_STATUS_INTERVAL_MS) {
    lastFeederStatusMs = now;
    sendFeederStatus();
  }

  if (networkAvailable && now - lastFeederScheduleSyncMs >= FEEDER_SCHEDULE_SYNC_MS) {
    lastFeederScheduleSyncMs = now;
    syncFeederSchedules();
  }

  if (now - lastFeederScheduleCheckMs >= FEEDER_SCHEDULE_CHECK_MS) {
    lastFeederScheduleCheckMs = now;
    checkScheduledFeed();
    if (feederRunState != FEEDER_IDLE) return;
  }

  // ─── Feeder state machine tick ───
  processFeederTick();

  // ─── Actuators (pump + aerators) ───
  if (now - lastActuatorSyncMs >= ACTUATOR_SYNC_INTERVAL_MS) {
    lastActuatorSyncMs = now;
    syncActuatorsFromFirestore();
  }

  // ─── Sensors ───

  if (now - lastPollTime >= SENSOR_POLL_MS) {
    lastPollTime = now;

    readAllSensors();

    if (sensorOutputEnabled) printSensorReading();
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
    if (networkAvailable && littlefsMounted && ensureFirebaseReady()) flushOneFeederLog();
    if (networkAvailable && littlefsMounted && countBufferedEntries() > 0) {
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
//    tanks/{tankId}/feeder_commands/{docId}  -> Flutter pushes, ESP32 polls
//    tanks/{tankId}/feeder/status            -> ESP32 writes every 5s
//    tanks/{tankId}/feeder_schedules/{docId} -> Flutter writes, ESP32 reads
//    tanks/{tankId}/feeder_logs/{docId}      -> ESP32 creates (auto-ID)
// ============================================================

// ─── Initialize Feeder ───
void initFeeder() {
  fetchTankId();
  // Restore the last cloud-synced schedules so a reboot during an internet
  // outage can still execute them using the ESP's local clock.
  loadCachedFeederSchedules();
  // Restore the lifetime dispense count so the app's status display doesn't
  // reset to 0 after an ESP reboot.
  loadFeederState();
  ledcSetup(SERVO_LEDC_CHANNEL, SERVO_LEDC_FREQ, SERVO_LEDC_RESOLUTION);
  ledcAttachPin(FEEDER_SERVO_PIN, SERVO_LEDC_CHANNEL);
  _setServoAngle(0);
  feederIsRunning = false;
  feederRunState = FEEDER_IDLE;
  feederCurrentCycle = 0;
  feederInitialized = true;
  recoverFeederLogs();

  // Park the servo closed. Do NOT perform a full sweep at boot: a 90° sweep
  // drops a fraction of feed every time the ESP resets (which also happens on
  // Wi-Fi drops / power flickers). If a physical hardware self-test is
  // needed, add a serial command gated behind a build flag instead.
  Serial.println("[FEEDER] Servo initialized at closed position (0°)");
}

// ─── Process Commands from Firestore ───
// Lists tanks/{tankId}/feeder_commands, safely acknowledges one command, then
// starts its non-blocking feed cycle.
// Reads all docs into local arrays first to avoid fbdo buffer conflicts.
void processFeederCommands() {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) return;   // no tank assigned -> nothing to do
  // Leave queued commands untouched while a feed is already running. This
  // prevents a second Feed Now request from being deleted without execution.
  if (feederRunState != FEEDER_IDLE) return;

  String cmdCol = "tanks/" + currentTankId + "/feeder_commands";
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
    float grams;
    long long issuedAtMs = 0;
    long long expiresAtMs = 0;
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
    e.grams = 20.0f;

    if (response.get(d, base + "command_type/stringValue")) e.action = d.stringValue;
    if (response.get(d, base + "grams/doubleValue")) e.grams = d.doubleValue;
    else if (response.get(d, base + "grams/integerValue")) e.grams = d.stringValue.toFloat();
    if (response.get(d, base + "issued_at/timestampValue")) e.issuedAtMs = firestoreTimestampMillis(d.stringValue);
    if (response.get(d, base + "expires_at/timestampValue")) e.expiresAtMs = firestoreTimestampMillis(d.stringValue);

    if (e.action != "") entryCount++;
  }

  // Process at most one valid feed command per poll. Remaining documents stay
  // queued and are picked up after the current non-blocking feed completes.
  for (int i = 0; i < entryCount; i++) {
    CmdEntry& e = entries[i];
    Serial.printf("[FEEDER CMD] %s id=%s\n",
                  e.action.c_str(), e.docId.c_str());

    if (e.action == "feed_now") {
      startFeed("manual", e.grams, e.docId, e.issuedAtMs, e.expiresAtMs);
      break;
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
  json.set("fields/status/stringValue", feederStatus);
  json.set("fields/command_id/stringValue", feederCommandId);
  json.set("fields/status_reason/stringValue", feederStatusReason);
  json.set("fields/dispenseCount/integerValue", String(feederDispenseCount));
  json.set("fields/lastSeen/integerValue", nowMs);
  if (feederLastCompletedEpoch > 0) {
    json.set("fields/last_dispensed_at/integerValue", epochMillisString((time_t)feederLastCompletedEpoch));
  } else {
    json.set("fields/last_dispensed_at/nullValue", "NULL_VALUE");
  }
  json.set("fields/last_dispensed_grams/doubleValue",
           String(feederLastCompletedGrams, 1));
  if (feedLevelSensorOK) {
    json.set("fields/feed_level/doubleValue", feedLevelPercent);
    json.set("fields/estimated_feed_grams/doubleValue", estimatedFeedGrams);
  }

  String statusDoc = "tanks/" + currentTankId + "/feeder/status";
  if (!Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "",
        statusDoc.c_str(), json.raw(),
        "status,command_id,status_reason,dispenseCount,lastSeen,last_dispensed_at,last_dispensed_grams,feed_level,estimated_feed_grams")) {
    if (fbdo.httpConnected()) {
      Serial.printf("[FEEDER STATUS ERROR] %s\n", fbdo.errorReason().c_str());
    }
  }
}

void saveCachedFeederSchedules() {
  if (!prefs.begin("feedsched", false)) return;
  // Invalidate BEFORE changing the owner or any entries. A reset mid-write
  // must not expose another owner's or a partially written schedule cache.
  if (prefs.putInt("count", 0) != sizeof(int32_t)) { prefs.end(); return; }
  bool saved = prefs.putString("tank", currentTankId) == currentTankId.length();
  saved &= prefs.putLong64("assignment", currentAssignmentAtMs) == sizeof(int64_t);
  for (int i = 0; i < feederScheduleCount; i++) {
    saved &= prefs.putInt(("h" + String(i)).c_str(), feederSchedules[i].hour24) == sizeof(int32_t);
    saved &= prefs.putInt(("m" + String(i)).c_str(), feederSchedules[i].minute) == sizeof(int32_t);
    saved &= prefs.putBool(("e" + String(i)).c_str(), feederSchedules[i].enabled) == sizeof(uint8_t);
    saved &= prefs.putFloat(("g" + String(i)).c_str(), feederSchedules[i].grams) == sizeof(float);
    saved &= prefs.putString(("d" + String(i)).c_str(), feederSchedules[i].days) == feederSchedules[i].days.length();
    saved &= prefs.putString(("k" + String(i)).c_str(), feederSchedules[i].key) == feederSchedules[i].key.length();
    saved &= prefs.putULong(("t" + String(i)).c_str(), feederSchedules[i].effectiveEpoch) == sizeof(uint32_t);
  }
  if (saved) prefs.putInt("count", feederScheduleCount);
  prefs.end();
}

void loadCachedFeederSchedules() {
  prefs.begin("feedsched", true);
  if (currentTankId.isEmpty() || prefs.getString("tank", "") != currentTankId ||
      prefs.getLong64("assignment", 0) != currentAssignmentAtMs) {
    prefs.end();
    feederSchedules.clear();
    feederScheduleCount = 0;
    return;
  }
  feederScheduleCount = max(0, prefs.getInt("count", 0));
  feederSchedules.resize(feederScheduleCount);
  for (int i = 0; i < feederScheduleCount; i++) {
    feederSchedules[i].key = prefs.getString(("k" + String(i)).c_str(), "");
    feederSchedules[i].hour24 = prefs.getInt(("h" + String(i)).c_str(), 6);
    feederSchedules[i].minute = prefs.getInt(("m" + String(i)).c_str(), 0);
    feederSchedules[i].enabled = prefs.getBool(("e" + String(i)).c_str(), true);
    feederSchedules[i].grams = prefs.getFloat(("g" + String(i)).c_str(), 20.0f);
    feederSchedules[i].days = prefs.getString(("d" + String(i)).c_str(), "1111111");
    feederSchedules[i].effectiveEpoch = prefs.getULong(("t" + String(i)).c_str(), 0);
  }
  prefs.end();
  if (feederScheduleCount > 0) {
    Serial.printf("[FEEDER] Restored %d cached schedule(s) for offline operation\n",
                  feederScheduleCount);
  }
}

// Persist the lifetime dispense count separately from schedule cache so the
// "feeds completed" count the app reads from feeder/status survives reboots.
bool saveFeederState() {
  if (!prefs.begin("feederstate", false)) return false;
  prefs.putInt("dispenseCount", feederDispenseCount);
  prefs.putString("tank", currentTankId);
  const bool minuteSaved = prefs.putULong("lastSchedMin", feederLastScheduledMinute) == sizeof(uint32_t);
  prefs.putULong("lastComplete", feederLastCompletedEpoch);
  prefs.putFloat("lastGrams", feederLastCompletedGrams);
  const bool sequenceSaved = prefs.putULong("eventSeq", feederEventSequence) == sizeof(uint32_t);
  prefs.end();
  return minuteSaved && sequenceSaved;
}

void loadFeederState() {
  prefs.begin("feederstate", true);
  feederEventSequence = prefs.getULong("eventSeq", 0);
  feederLastScheduledMinute = prefs.getULong("lastSchedMin", 0);
  if (prefs.getString("tank", "") == currentTankId && !currentTankId.isEmpty()) {
    feederDispenseCount = prefs.getInt("dispenseCount", 0);
    feederLastCompletedEpoch = prefs.getULong("lastComplete", 0);
    feederLastCompletedGrams = prefs.getFloat("lastGrams", 0);
  }
  prefs.end();
  if (feederDispenseCount > 0) {
    Serial.printf("[FEEDER] Restored dispense count: %d\n", feederDispenseCount);
  }
}

// ─── Sync Schedules from Firestore ───
// Fetch every page, then replace the cache. No silent 20-item cutoff.
void syncFeederSchedules() {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) return;   // no tank assigned -> nothing to sync

  String schedCol = "tanks/" + currentTankId + "/feeder_schedules";
  std::vector<FeedSchedule> synced;
  String pageToken;
  do {
  if (!Firebase.Firestore.listDocuments(&fbdo, FIREBASE_PROJECT_ID, "",
        schedCol.c_str(), FEEDER_SCHEDULE_PAGE_SIZE, pageToken.c_str(), "timeValue", "", false)) {
    // Keep the last valid in-memory/NVS schedule set on transient failures.
    Serial.printf("[FEEDER] Schedule sync failed; retaining %d cached schedule(s)\n",
                  feederScheduleCount);
    return;
  }

  FirebaseJson response;
  response.setJsonData(fbdo.payload());
  FirebaseJsonData d;

  pageToken = "";
  if (response.get(d, "nextPageToken")) pageToken = d.stringValue;
  for (int i = 0; i < FEEDER_SCHEDULE_PAGE_SIZE; i++) {
    String namePath = String("documents/[") + i + "]/name";
    if (!response.get(d, namePath)) break;

    String docName = d.stringValue;
    int lastSlash  = docName.lastIndexOf('/');
    String docId   = (lastSlash >= 0) ? docName.substring(lastSlash + 1) : docName;

    FeedSchedule s;
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
    if (response.get(d, base + "enabled/booleanValue")) s.enabled = d.boolValue;
    // Legacy fallback for schedules written by older app builds.
    if (response.get(d, base + "is_active/booleanValue")) s.enabled = d.boolValue;
    s.grams = 20.0f;
    if (response.get(d, base + "grams/doubleValue")) s.grams = d.doubleValue;
    else if (response.get(d, base + "grams/integerValue")) s.grams = d.stringValue.toFloat();
    if (response.get(d, base + "effective_at_ms/integerValue")) {
      s.effectiveEpoch = (unsigned long)(atoll(d.stringValue.c_str()) / 1000LL);
    }

    s.days = "1111111";
    if (response.get(d, base + "days/stringValue")) s.days = d.stringValue;

    synced.push_back(s);
  }
  } while (pageToken.length() > 0);
  bool unchanged = synced.size() == feederSchedules.size();
  for (size_t i = 0; unchanged && i < synced.size(); ++i) {
    const FeedSchedule& a = synced[i];
    const FeedSchedule& b = feederSchedules[i];
    unchanged = a.key == b.key && a.hour24 == b.hour24 && a.minute == b.minute &&
        a.enabled == b.enabled && a.grams == b.grams && a.days == b.days && a.effectiveEpoch == b.effectiveEpoch;
  }
  if (unchanged) return; // Avoid rewriting NVS on every poll.
  feederSchedules.swap(synced);
  feederScheduleCount = feederSchedules.size();

  saveCachedFeederSchedules();
  Serial.printf("[FEEDER] Synced %d schedules from Firestore\n", feederScheduleCount);
}

bool canFeedSafely(String &reason, float requiredGrams) {
  if (!feederConfigReady) {
    reason = "tank sensor settings have not finished syncing";
    return false;
  }
  if (!tempSensorOK || !doSensorOK || !phSensorOK || !turbiditySensorOK) {
    reason = "required water-quality sensor unavailable";
    return false;
  }
  if (smoothedTemp < tempCriticalLow || smoothedTemp > tempCriticalHigh) reason = "temperature outside range";
  else if (dissolvedOxygen < doCriticalLow) reason = "dissolved oxygen too low";
  else if (phLevel < phCriticalLow || phLevel > phCriticalHigh) reason = "pH outside range";
  else if (smoothedTurbidityNTU > turbNtuMax) reason = "turbidity too high";
  else if (!feedLevelSensorOK) reason = "feed-level sensor unavailable";
  else if (feedLevelPercent <= 0.0f) reason = "empty feed hopper";
  else if (estimatedFeedGrams + 0.5f < requiredGrams) reason = "insufficient feed";
  else return true;
  return false;
}

// Feed Now must never race an automatic occurrence. Block the entire
// scheduled minute and the final 60 seconds before it. The app provides the
// wider 15-minute warning; this device-side guard remains authoritative if a
// stale app, delayed command, or another client bypasses that UI.
bool manualFeedConflictsWithSchedule(time_t now, String &scheduleLabel) {
  if (!feederAutoMode || feederScheduleCount == 0 || now < 1700000000) return false;

  struct tm currentTime;
  localtime_r(&now, &currentTime);
  for (int dayOffset = 0; dayOffset <= 1; dayOffset++) {
    for (int i = 0; i < feederScheduleCount; i++) {
      FeedSchedule& s = feederSchedules[i];
      if (!s.enabled) continue;

      struct tm candidateTime = currentTime;
      candidateTime.tm_mday += dayOffset;
      candidateTime.tm_hour = s.hour24;
      candidateTime.tm_min = s.minute;
      candidateTime.tm_sec = 0;
      const time_t candidate = mktime(&candidateTime);
      struct tm normalizedCandidate;
      localtime_r(&candidate, &normalizedCandidate);
      if (s.days.length() >= 7 && s.days.charAt(normalizedCandidate.tm_wday) != '1') continue;
      if (s.effectiveEpoch > (unsigned long)candidate) continue;

      const long secondsUntil = (long)difftime(candidate, now);
      const bool sameMinute = now / 60 == candidate / 60;
      if (sameMinute || (secondsUntil >= 0 && secondsUntil <= 60)) {
        const int hour12 = s.hour24 % 12 == 0 ? 12 : s.hour24 % 12;
        scheduleLabel = String(hour12) + ":" + (s.minute < 10 ? "0" : "") +
                        String(s.minute) + (s.hour24 >= 12 ? " PM" : " AM");
        return true;
      }
    }
  }
  return false;
}

// ─── Check if it's time for a scheduled feed ───
void checkScheduledFeed() {
  if (currentTankId.isEmpty() || !feederAutoMode || feederScheduleCount == 0 || feederRunState != FEEDER_IDLE) return;

  time_t now;
  time(&now);
  if (now < 1700000000) return;
  struct tm* timeinfo = localtime(&now);
  int currentMin = timeinfo->tm_hour * 60 + timeinfo->tm_min;
  // tm_wday is already Sunday-first: 0=Sunday..6=Saturday.
  int dayIdx = timeinfo->tm_wday;

  for (int i = 0; i < feederScheduleCount; i++) {
    FeedSchedule& s = feederSchedules[i];
    if (!s.enabled) continue;

    // Skip if this schedule is not active on today's weekday.
    if (s.days.length() >= 7 && s.days.charAt(dayIdx) != '1') continue;

    int schedMin = s.hour24 * 60 + s.minute;
    // Fire within the same minute (tolerate 0-59s)
    if (schedMin == currentMin) {
      // Check we haven't already fired this minute
      unsigned long nowEpoch = (unsigned long)now;
      if (nowEpoch / 60 > feederLastScheduledMinute && s.effectiveEpoch <= nowEpoch - nowEpoch % 60) {
        Serial.printf("[FEEDER] Scheduled feed at %02d:%02d (%.1fg)\n",
                      s.hour24, s.minute, s.grams);
        // Preserve occurrence identity in the durable device outcome log.
        feederLastScheduleKey = s.key;
        const int hour12 = s.hour24 % 12 == 0 ? 12 : s.hour24 % 12;
        feederScheduleTime = String(hour12) + ":" + (s.minute < 10 ? "0" : "") + String(s.minute) + (s.hour24 >= 12 ? " PM" : " AM");
        startFeed("scheduled", s.grams);
        return;
      }
    }
  }
}

// ─── Start Feed — kicks off non-blocking state machine ───
void startFeed(String source, float grams, String commandId, long long issuedAtMs, long long expiresAtMs) {
  if (feederRunState != FEEDER_IDLE) {
    Serial.println("[FEEDER] Already running, skipping");
    return;
  }
  if (currentTankId.isEmpty()) return;
  time_t startedAt;
  time(&startedAt);
  if (startedAt < 1700000000 || !littlefsMounted) return;
  // A durable command intent is a tombstone until the queued command has
  // been acknowledged. Never restart its motor operation after a reset.
  if (!commandId.isEmpty()) {
    const String base = "/feedlogs/cmd_" + commandId;
    if (LittleFS.exists(base + ".pending") || LittleFS.exists(base + ".json")) {
      flushOneFeederLog();
      return;
    }
  }
  feederCommandId = commandId;
  feederStatusReason = "";
  feederRequestedGrams = grams;
  feederFeedSource = source;
  feederEventTank = currentTankId;
  feederOccurrenceEpoch = source == "scheduled" ? startedAt - startedAt % 60 : startedAt;
  if (source != "scheduled") {
    feederLastScheduleKey = "";
    feederScheduleTime = "";
  }
  ++feederEventSequence;
  feederEventKey = commandId.isEmpty() ? String(feederEventSequence) : "cmd_" + commandId;
  // Persist sequence identity first, but do not reserve the scheduled minute
  // until its interrupted/failed outcome is durable.
  if (!saveFeederState()) {
    feederStatus = "blocked";
    Serial.println("[FEEDER] Cannot reserve execution; refusing to dispense");
    return;
  }
  feederWritingIntent = true;
  pushFeederLog("Feed interrupted - execution could not be confirmed", source == "scheduled" ? "auto" : "manual",
                "failed", grams, -1, -1, -1);
  feederWritingIntent = false;
  if (!LittleFS.exists("/feedlogs/" + feederEventKey + ".pending")) {
    feederStatus = "blocked";
    feederStatusReason = "Cannot persist feed request";
    sendFeederStatus();
    return;
  }
  if (source == "scheduled") {
    feederLastScheduledMinute = startedAt / 60;
    if (!saveFeederState()) return; // Recovery retains and reserves the intent.
  }
  if (!commandId.isEmpty()) {
    const String path = "tanks/" + currentTankId + "/feeder_commands/" + commandId;
    if (!Firebase.Firestore.deleteDocument(&fbdo, FIREBASE_PROJECT_ID, "", path.c_str())) {
      // An ambiguous acknowledgement must never actuate. The outbox retries
      // deletion before it can upload/remove this durable failed outcome.
      feederStatus = "blocked";
      feederStatusReason = "Command acknowledgement not confirmed";
      sendFeederStatus();
      return;
    }
  }
  feederStatus = "checking_feed_level";
  readFeedLevelSensor();
  sendFeederStatus();

  String blockedReason;
  time_t checkedAt;
  time(&checkedAt);
  if (!commandId.isEmpty() && (issuedAtMs <= 0 || issuedAtMs > (long long)checkedAt * 1000 + 5000 ||
                              (long long)checkedAt * 1000 - issuedAtMs > 60000 ||
                              (expiresAtMs > 0 && (long long)checkedAt * 1000 >= expiresAtMs))) {
    blockedReason = "Feed Now request expired or has an invalid timestamp";
  }
  if (!isfinite(grams) || grams < 20 || grams > 200 || fabsf(grams / 20.0f - roundf(grams / 20.0f)) > 0.0001f) {
    blockedReason = "unsupported amount; use 20-200 g in steps of 20 g";
  }
  String nearbySchedule;
  if (blockedReason.length() == 0 && source == "manual" &&
      manualFeedConflictsWithSchedule(checkedAt, nearbySchedule)) {
    blockedReason = "automatic feeding is due at " + nearbySchedule;
  }
  if (blockedReason.length() > 0 || !canFeedSafely(blockedReason, feederRequestedGrams)) {
    feederStatusReason = blockedReason;
    Serial.printf("[FEEDER] BLOCKED: %s\n", blockedReason.c_str());
    time_t blockedAt;
    time(&blockedAt);
    feederLastFeedEpoch = (unsigned long)blockedAt;
    feederStatus = blockedReason == "insufficient feed" ||
                           blockedReason == "empty feed hopper"
                       ? "skipped_insufficient"
                       : "blocked";
    String action = blockedReason == "insufficient feed" ||
                            blockedReason == "empty feed hopper"
                        ? "Skipped - Insufficient feed"
                        : "Feed blocked: " + blockedReason;
    const bool insufficient = blockedReason == "insufficient feed" ||
                              blockedReason == "empty feed hopper";
    pushFeederLog(action, source == "manual" ? "manual" : "auto",
                  insufficient ? "skipped_insufficient" : "blocked",
                  feederRequestedGrams,
                  estimatedFeedGrams, feedLevelPercent, feedLevelPercent);
    sendFeederStatus();
    feederLastScheduleKey = "";
    return;
  }

  feederFeedLevelBefore = feedLevelPercent;
  feederAvailableBefore = estimatedFeedGrams;
  feederMaxCycles = (int)roundf(feederRequestedGrams / 20.0f);

  // Announce readiness while the servo is still parked, then recheck expiry
  // after this potentially blocking call before opening the gate.
  feederStatus = "dispensing";
  sendFeederStatus();
  time(&checkedAt);
  if (!commandId.isEmpty() && ((long long)checkedAt * 1000 - issuedAtMs > 60000 ||
      (expiresAtMs > 0 && (long long)checkedAt * 1000 >= expiresAtMs))) {
    feederStatus = "blocked";
    feederStatusReason = "Feed Now request expired before dispensing";
    pushFeederLog(feederStatusReason, "manual", "blocked", grams,
                  feederAvailableBefore, feederFeedLevelBefore, feederFeedLevelBefore);
    sendFeederStatus();
    return;
  }

  time_t now;
  time(&now);
  feederLastFeedEpoch = (unsigned long)now;
  feederFeedSource = source;
  feederIsRunning = true;
  feederStatus = "dispensing";
  feederCurrentCycle = 0;
  feederRunState = FEEDER_FORWARD;
  feederStartMs = millis();
  feederStepMs = feederStartMs;

  // No blocking cloud call between the expiry check and the motor tick.
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

    case FEEDER_DONE: {
      // Keep isRunning=true for at least 1s so Flutter reliably catches the transition
      if (now - feederStartMs < 1000) break;

      _setServoAngle(0);

      // Update feed count and persist it so a reboot doesn't reset the total
      // the app displays as "feeds completed".
      feederDispenseCount++;
      time_t completedAt;
      time(&completedAt);
      feederLastCompletedEpoch = completedAt;
      feederLastCompletedGrams = feederRequestedGrams;
      saveFeederState();

      feederIsRunning = false;
      feederStatus = "completed";
      feederRunState = FEEDER_IDLE;

      // A level sensor supports confirmation that feed decreased, but it is
      // not a weighing scale and therefore never proves the exact grams.
      readFeedLevelSensor();
      const float levelAfter = feedLevelSensorOK ? feedLevelPercent : -1.0f;
      // Push final status + log
      pushFeederLog(
        feederFeedSource == "scheduled"
          ? "Dispensed feed (Scheduled)"
          : "Dispensed feed (Manual)",
        feederFeedSource == "scheduled" ? "auto" : "manual",
        "completed",
        feederRequestedGrams,
        feederAvailableBefore,
        feederFeedLevelBefore,
        levelAfter
      );
      sendFeederStatus();
      // The log trigger updates the date-scoped outcome, including backfills.

      feederFeedSource = "";
      feederLastScheduleKey = "";
      // Keep the terminal confirmation until the next request starts.
      Serial.println("[FEEDER] Feed complete");
      break;
    }

    default:
      feederRunState = FEEDER_IDLE;
      break;
  }
}

// ─── Push Feeding Log to Firestore ───
// Write locally first. A deterministic ID makes retries safe after reconnect.
void pushFeederLog(String action, String type, String status,
                   float requestedGrams, float availableGrams,
                   float levelBefore, float levelAfter) {
  if (!littlefsMounted || feederEventTank.isEmpty()) return;

  time_t now;
  time(&now);
  const String epochMs = epochMillisString(now);

  FirebaseJson json;
  json.set("fields/action/stringValue",    action);
  json.set("fields/type/stringValue",      type);
  if (!feederCommandId.isEmpty()) json.set("fields/command_id/stringValue", feederCommandId);
  json.set("fields/logged_at/integerValue", String(epochMs));
  json.set("fields/occurrence_at/integerValue", epochMillisString(feederOccurrenceEpoch));
  if (feederLastScheduleKey.length() > 0) {
    json.set("fields/schedule_key/stringValue", feederLastScheduleKey);
    json.set("fields/schedule_time/stringValue", feederScheduleTime);
  }
  json.set("fields/amount_basis/stringValue", "servo_cycle_estimate");
  if (status == "completed") json.set("fields/estimated_dispensed_grams/doubleValue", String(requestedGrams, 1));
  if (status.length() > 0) json.set("fields/status/stringValue", status);
  if (isfinite(requestedGrams) && requestedGrams >= 0.0f) {
    json.set("fields/requested_grams/doubleValue", String(requestedGrams, 1));
  }
  if (availableGrams >= 0.0f) {
    json.set("fields/estimated_available_grams/doubleValue", String(availableGrams, 1));
  }
  if (levelBefore >= 0.0f) {
    json.set("fields/feed_level_before/doubleValue", String(levelBefore, 1));
  }
  if (levelAfter >= 0.0f) {
    json.set("fields/feed_level_after/doubleValue", String(levelAfter, 1));
    json.set("fields/level_change_detected/booleanValue",
             levelBefore >= 0.0f && levelBefore - levelAfter >= 0.5f);
    if (status == "completed" && levelBefore >= 0.0f && levelBefore - levelAfter < 0.5f) {
      json.set("fields/verification_note/stringValue",
               "Possible dispense failure: no detectable feed-level change");
    }
  }

  FirebaseJson envelope;
  envelope.set("tank", feederEventTank);
  envelope.set("id", hardwareId + "_" + feederEventKey);
  envelope.set("command_id", feederCommandId);
  envelope.set("scheduled_minute", type == "auto" ? feederOccurrenceEpoch / 60 : 0);
  envelope.set("payload", String(json.raw()));
  LittleFS.mkdir("/feedlogs");
  const String base = "/feedlogs/" + feederEventKey;
  const String temp = base + ".tmp";
  const String target = base + (feederWritingIntent ? ".pending" : ".json");
  File file = LittleFS.open(temp, "w");
  if (!file) return;
  const String serialized = envelope.raw();
  const size_t written = file.print(serialized);
  file.flush();
  file.close();
  if (written != serialized.length() || !LittleFS.rename(temp, target)) {
    Serial.println("[FEEDER LOG] Local write failed; pending intent retained");
    return;
  }
  if (!feederWritingIntent) LittleFS.remove(base + ".pending");
}

void recoverFeederLogs() {
  if (!littlefsMounted) return;
  LittleFS.mkdir("/feedlogs");
  File dir = LittleFS.open("/feedlogs");
  std::vector<String> pending;
  for (File file = dir.openNextFile(); file; file = dir.openNextFile()) {
    String path = file.path();
    if (path.endsWith(".pending")) pending.push_back(path);
    file.close();
  }
  dir.close();
  for (const String& path : pending) {
    File intent = LittleFS.open(path, "r");
    if (!intent) continue;
    FirebaseJson envelope;
    envelope.setJsonData(intent.readString());
    intent.close();
    FirebaseJsonData field;
    if (envelope.get(field, "scheduled_minute")) {
      const unsigned long reserved = field.intValue;
      if (reserved > 0 && reserved >= feederLastScheduledMinute) {
        feederLastScheduledMinute = reserved;
        if (!saveFeederState()) continue;
      }
    }
    const String target = path.substring(0, path.length() - 8) + ".json";
    // Completion may already be durable if reset happened just before cleanup.
    if (LittleFS.exists(target)) LittleFS.remove(path);
    else LittleFS.rename(path, target);
  }
}

bool flushOneFeederLog() {
  if (!littlefsMounted || currentTankId.isEmpty()) return false;
  recoverFeederLogs(); // Idle only: finalize any intent whose completion write failed.
  File dir = LittleFS.open("/feedlogs");
  if (!dir) return false;
  for (File file = dir.openNextFile(); file; file = dir.openNextFile()) {
    const String path = file.path();
    if (!path.endsWith(".json")) { file.close(); continue; }
    FirebaseJson envelope;
    envelope.setJsonData(file.readString());
    file.close();
    FirebaseJsonData field;
    if (!envelope.get(field, "tank") || field.stringValue != currentTankId) continue;
    if (!envelope.get(field, "id")) continue;
    const String id = field.stringValue;
    if (envelope.get(field, "command_id") && !field.stringValue.isEmpty()) {
      const String commandPath = "tanks/" + currentTankId + "/feeder_commands/" + field.stringValue;
      const bool acknowledged = Firebase.Firestore.deleteDocument(&fbdo, FIREBASE_PROJECT_ID, "", commandPath.c_str());
      if (!acknowledged && fbdo.httpCode() != 404) { dir.close(); return false; }
    }
    if (!envelope.get(field, "payload")) continue;
    const String payload = field.stringValue;
    const String collection = "tanks/" + currentTankId + "/feeder_logs";
    const bool uploaded = Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "",
        collection.c_str(), id.c_str(), payload.c_str(), "");
    const bool duplicate = fbdo.httpCode() == 409;
    dir.close();
    if (uploaded || duplicate) return LittleFS.remove(path);
    return false;
  }
  dir.close();
  return true;
}

void applyTankAssignment(const String& tankId, const String& ownerUid, long long assignedAtMs) {
  if (tankId == currentTankId && ownerUid == currentOwnerUid && assignedAtMs == currentAssignmentAtMs) return;
  currentTankId = tankId;
  currentOwnerUid = ownerUid;
  currentAssignmentAtMs = assignedAtMs;
  resetWindowAggregates(); // A 10-minute window must never span two assignments.
  feederConfigReady = false;
  if (!feederInitialized) return;
  // Loop defers cloud work until the servo is parked. Revoke the cached plan;
  // never carry a previous owner's schedules/counters into the next account.
  feederSchedules.clear();
  feederScheduleCount = 0;
  feederLastScheduleKey = "";
  feederScheduleTime = "";
  feederDispenseCount = 0;
  feederLastCompletedEpoch = 0;
  feederLastCompletedGrams = 0;
  feederStatus = "idle";
  saveCachedFeederSchedules();
  saveFeederState();
  for (int i = 0; i < 3; ++i) actuators[i].controlMode = "";
  // Hold life-support relays at their last state until valid replacement
  // settings arrive; an assignment change must not blindly cut off aeration.
  lastFeederScheduleSyncMs = 0;
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
// Firestore rules allow the dedicated esp32@craycare.com account to update ONLY:
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
//   actuator_type, action, type, logged_at(ms)
// Put "(AUTO)" in `action` so the app surfaces it as an auto-control event.
void pushActuatorLog(int idx, String action, String type) {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) return;

  time_t now;
  time(&now);
  const String epochMs = epochMillisString(now);

  FirebaseJson json;
  json.set("fields/actuator_type/stringValue", actuators[idx].deviceId);
  json.set("fields/action/stringValue",        action);
  json.set("fields/type/stringValue",          type);
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
    // Canonical ASCII format (do not use em/en dashes — the Flutter app
    // and Cloud Function strip prefixes with regex that expects '-'):
    //   manual: "Switched ON - Water Pump"
    //   auto:   "Switched ON (AUTO) - Water Pump - Auto condition met"
    String action = String("Switched ") + (target ? "ON" : "OFF");
    if (a.controlMode == "auto") action += " (AUTO)";
    action += " - " + String(a.label);
    if (a.controlMode == "auto") action += " - " + reason;
    pushActuatorLog(idx, action, type);
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
    if (actuators[i].controlMode.isEmpty()) continue;
    applyActuatorDevice(i);
  }
}
