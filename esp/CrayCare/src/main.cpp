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
 *  tanks/{tankId}/sensor_readings/latest    -> latest payload every 5 seconds
 *  tanks/{tankId}/sensor_readings_history/... -> current-assignment history directly
 *  sensorIngestion/current/history/{docId}  -> buffered/unassigned history fallback
 *
 * Firestore Rules validate current hardware assignment for direct writes.
 * Cloud Functions still route buffered history and legacy ingestion safely.
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
#include <string.h>   // strlen(), memmove()
#include <LittleFS.h>  // offline store-and-forward buffer (data partition)
#include <SPI.h>
#include <SD.h>  // optional SD card: primary offline buffer when present
#include <Wire.h>
#include <LiquidCrystal_I2C.h>  // 16x2 status LCD (SDA 21 / SCL 22)
#include <vector>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include "esp_task_wdt.h"  // task watchdog: reboot (with trail) on silent hang
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
// Live sensors and normal history write directly to tanks/{currentTankId}/.
// Buffered/unassigned history uses sensorIngestion so Functions can quarantine
// stale assignments safely. Device control/config also uses the assigned tank.
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
#define CONFIG_SYNC_INTERVAL_MS 60000   // thresholds re-sync; switch forces immediate
#define FLUSH_INTERVAL_MS 1000           // flush backlog at 1 entry/sec (max)
#define SENSOR_POLL_MS 2000
#define ASSIGNMENT_RECHECK_MS 60000      // refresh hardware assignment once per minute
#define ASSIGNMENT_SEARCH_MS 10000      // aggressive search while missing

// Feeder timing
#define FEEDER_CMD_INTERVAL_MS 1000
#define FEEDER_STATUS_INTERVAL_MS 5000
#define FEEDER_SCHEDULE_SYNC_MS 10000
#define FEEDER_SCHEDULE_CHECK_MS 1000
#define FEEDER_SERVO_PULSE_WIDTH 2000   // microseconds for full rotation
#define FEEDER_SCHEDULE_PAGE_SIZE 20

// Resolve tank_id from hardware_system/currentOwner (used for subcollection paths)
extern FirebaseData fbdo;
bool ensureFirebaseReady();
void applyTankAssignment(const String& tankId, const String& ownerUid = "", long long assignedAtMs = 0);
// Idempotent Firestore GET with one immediate retry on transport-class
// failures (slow-TLS timeouts, dropped connections). Definitive answers —
// 404 missing, 401 auth, 403 rules — return immediately without retry.
// Silent on first-attempt failure; callers print only if both fail.
#define OUTAGE_TRIP_FAILURES 5
#define OUTAGE_PROBE_MS 30000
int cloudTransportFailures = 0;  // consecutive timeout-class failures (session resets)
int cloudOutageStreak = 0;       // consecutive failures (outage mode, never auto-resets down)
bool cloudOutage = false;
unsigned long lastOutageProbeMs = 0;

// Any success clears the streak. On 3 consecutive transport failures the
// shared TLS session is dropped so the next call does a clean handshake
// (counters wedged-session accumulation: connect fd climbing, SSL
// mRunUntil/mConnectSSL timeouts after link flaps).
bool cloudSessionResetPending = false;

void reportCloudResult(bool ok) {
  if (ok) {
    cloudTransportFailures = 0;
    cloudSessionResetPending = false;
    cloudOutageStreak = 0;
    if (cloudOutage) {
      cloudOutage = false;
      Serial.println("[NET] Link recovered — full cloud ops resumed");
    }
    return;
  }
  cloudOutageStreak++;
  if (++cloudTransportFailures >= 3) {
    cloudTransportFailures = 0;
    cloudSessionResetPending = true;
  }
  if (!cloudOutage && cloudOutageStreak >= OUTAGE_TRIP_FAILURES) {
    cloudOutage = true;
    Serial.println("[NET] Outage mode — cloud calls suspended, probing every 30 s");
  }
}

bool firestoreGetDoc(const char* docPath) {
  for (int attempt = 0; attempt < 2; attempt++) {
    if (Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "", docPath)) {
      reportCloudResult(true);
      return true;
    }
    const int code = fbdo.httpCode();
    if (code == 404 || code == 401 || code == 403) return false;
  }
  reportCloudResult(false);
  return false;
}

void fetchTankId() {
  if (!ensureFirebaseReady()) return;
  // Read hardware_system/currentOwner to get tank_id for subcollection paths.
  // A missing doc is a legitimate unassignment; any other failure (e.g. a
  // 403 from rules) is printed so it cannot fail silently on-device.
  if (!firestoreGetDoc("hardware_system/currentOwner")) {
    if (fbdo.httpCode() == 404) {
      applyTankAssignment("");
    } else {
      Serial.printf("[ESP] Assignment read failed, http=%d (%s)\n",
                    fbdo.httpCode(), fbdo.errorReason().c_str());
    }
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

// SD card pins (VSPI) — declared early so initSDCard() below can use them.
// (Also listed in the PINOUT section further down.)
#define SD_SPI_SCK_PIN 18
#define SD_SPI_MISO_PIN 19
#define SD_SPI_MOSI_PIN 23
#define SD_SPI_CS_PIN 15  // GPIO15 (MTDO) needs HIGH at boot — CS idles HIGH via pull-up, so safe.
void initSDCard();
void migrateLittleFSToSD();

bool sdMounted = false;
#define SD_BUFFER_PATH "/craycare/history.jsonl"
#define SD_BUFFER_TMP "/craycare/history.tmp"

// Active write backend: SD card when present, otherwise LittleFS.
static inline fs::FS& bufFS() { return sdMounted ? (fs::FS&)SD : (fs::FS&)LittleFS; }
static inline const char* bufPath() { return sdMounted ? SD_BUFFER_PATH : BUFFER_PATH; }
static inline const char* bufTmpPath() { return sdMounted ? SD_BUFFER_TMP : "/buf/history.tmp"; }

void initOfflineBuffer() {
  if (!LittleFS.begin(true)) {           // formatOnFail on the spiffs partition
    Serial.println("[BUF] LittleFS mount FAILED — LittleFS buffering disabled");
    littlefsMounted = false;
  } else {
    littlefsMounted = true;
    if (!LittleFS.exists("/buf") && !LittleFS.mkdir("/buf")) {
      Serial.println("[BUF] Could not create /buf on LittleFS");
      littlefsMounted = false;
    }
    // Create the append target up front. Some ESP32 VFS/LittleFS builds fail
    // FILE_APPEND on a missing file and emit "no permits for creation".
    if (littlefsMounted && !LittleFS.exists(BUFFER_PATH)) {
      File emptyBuffer = LittleFS.open(BUFFER_PATH, "w");
      if (emptyBuffer) {
        emptyBuffer.close();
      } else {
        Serial.println("[BUF] Could not initialize LittleFS history buffer");
        littlefsMounted = false;
      }
    }
  }
  initSDCard();  // optional — LittleFS remains the fallback when no card is present
  Serial.printf("[BUF] backend=%s buffered=%u\n",
                sdMounted ? "SD" : "LittleFS", (unsigned)countBufferedEntries());
}

// Mount the SD card (VSPI) and migrate any LittleFS backlog onto it so the
// flush order stays oldest-first across the backend switch.
void initSDCard() {
  sdMounted = false;
  SPI.begin(SD_SPI_SCK_PIN, SD_SPI_MISO_PIN, SD_SPI_MOSI_PIN, SD_SPI_CS_PIN);
  if (!SD.begin(SD_SPI_CS_PIN)) {
    Serial.println("[BUF] No SD card — using LittleFS buffer");
    return;
  }
  if (SD.cardType() == CARD_NONE) {
    Serial.println("[BUF] SD slot empty — using LittleFS buffer");
    SD.end();
    return;
  }
  SD.mkdir("/craycare");
  sdMounted = true;
  Serial.println("[BUF] SD card mounted — migrating LittleFS backlog");
  migrateLittleFSToSD();
}

// Move LittleFS backlog lines onto SD (bounded rounds so boot never hangs).
void migrateLittleFSToSD() {
  if (!sdMounted || !littlefsMounted) return;
  for (int round = 0; round < 20; round++) {
    if (!LittleFS.exists(BUFFER_PATH)) return;
    File src = LittleFS.open(BUFFER_PATH, "r");
    if (!src) return;
    if (src.size() == 0) { src.close(); return; }
    File dst = SD.open(SD_BUFFER_PATH, FILE_APPEND);
    if (!dst) { src.close(); return; }
    size_t moved = 0;
    while (src.available() && moved < 512) {
      String line = src.readStringUntil('\n');
      line.trim();
      if (line.length() <= 10) continue;
      dst.println(line);
      moved++;
    }
    src.close();
    dst.close();
    if (moved == 0) { LittleFS.remove(BUFFER_PATH); return; }
    // Drop exactly the moved lines from LittleFS by rewriting the remainder.
    File r = LittleFS.open(BUFFER_PATH, "r");
    File w = LittleFS.open("/buf/history.tmp", "w");
    if (!r || !w) {
      if (r) r.close();
      if (w) w.close();
      return;
    }
    size_t skipped = 0;
    while (r.available()) {
      String line = r.readStringUntil('\n');
      line.trim();
      if (line.length() <= 10) continue;
      if (skipped < moved) { skipped++; continue; }
      w.println(line);
    }
    r.close();
    w.close();
    LittleFS.remove(BUFFER_PATH);
    LittleFS.rename("/buf/history.tmp", BUFFER_PATH);
    if (skipped < moved) return;  // file fully drained
  }
}

static size_t countEntriesIn(fs::FS& fs, const char* path) {
  if (!fs.exists(path)) return 0;
  File f = fs.open(path, "r");
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

size_t countBufferedEntries() {
  size_t n = 0;
  if (littlefsMounted) n += countEntriesIn(LittleFS, BUFFER_PATH);
  if (sdMounted) n += countEntriesIn(SD, SD_BUFFER_PATH);
  return n;
}

bool bufferAppend(const String& jsonLine) {
  if (jsonLine.length() < 10) return false;
  fs::FS& fs = bufFS();
  if (!sdMounted && !littlefsMounted) return false;
  if (!sdMounted && !LittleFS.exists(BUFFER_PATH)) {
    File emptyBuffer = LittleFS.open(BUFFER_PATH, "w");
    if (!emptyBuffer) return false;
    emptyBuffer.close();
  }
  File f = fs.open(bufPath(), FILE_APPEND);
  if (!f) return false;
  f.println(jsonLine);
  f.close();
  return true;
}

// Drop exactly the first valid line while preserving the entire backlog.
// SD drains first (it holds the migrated oldest entries); LittleFS follows.
static bool dropFirstIn(fs::FS& fs, const char* path, const char* tempPath) {
  if (!fs.exists(path)) return false;
  File src = fs.open(path, "r");
  if (!src) return false;
  File dst = fs.open(tempPath, "w");
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
  if (!dropped) { fs.remove(tempPath); return false; }
  fs.remove(path);
  return fs.rename(tempPath, path);
}

bool bufferDropFirst(const String* ignoredLines, size_t ignoredCount) {
  (void)ignoredLines;
  (void)ignoredCount;
  if (sdMounted && SD.exists(SD_BUFFER_PATH))
    return dropFirstIn(SD, SD_BUFFER_PATH, SD_BUFFER_TMP);
  if (!littlefsMounted) return false;
  return dropFirstIn(LittleFS, BUFFER_PATH, "/buf/history.tmp");
}

// Read all buffered lines into a fixed array (bounded). SD first.
size_t bufferReadAll(String* lines, size_t maxLines) {
  if (sdMounted && SD.exists(SD_BUFFER_PATH)) {
    File f = SD.open(SD_BUFFER_PATH, "r");
    if (f) {
      size_t n = 0;
      while (f.available() && n < maxLines) {
        String line = f.readStringUntil('\n');
        line.trim();
        if (line.length() > 10) lines[n++] = line;
      }
      f.close();
      if (n > 0) return n;
    }
  }
  if (!littlefsMounted) return 0;
  if (!LittleFS.exists(BUFFER_PATH)) return 0;
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

  // Deterministic doc ID from the original capture instant (dedup: a buffered
  // fallback uses this same ID as the direct canonical history write).
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
  char docIdBuffer[32];
  snprintf(docIdBuffer, sizeof(docIdBuffer), "r_%llu",
           static_cast<unsigned long long>(capMs > 0 ? capMs : millis()));
  String docId(docIdBuffer);
  String docPath = String("sensorIngestion/current/history/") + docId;

  // Skip if already uploaded (crash between create and buffer-delete).
  if (firestoreGetDoc(docPath.c_str())) {
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
unsigned long lastAssignmentCheckMs = 0;
unsigned long lastPollTime = 0;
unsigned long lastWifiReconnectTime = 0;
bool ntpEverSynced = false;            // set once time() passes the epoch gate
unsigned long lastNtpSyncMs = 0;
#define NTP_RESYNC_INTERVAL_MS 86400000UL  // daily refresh + post-outage recovery

// Feeder state
// LEDC servo control (no ESP32Servo library needed — avoid timer conflicts)
#define SERVO_LEDC_CHANNEL 0
#define SERVO_LEDC_FREQ 50
#define SERVO_LEDC_RESOLUTION 16
#define SERVO_PULSE_MIN 500
#define SERVO_PULSE_MAX 2500

// (Gate servo helper setGateAngle() lives with the GATE defines below;
// it maps 0-180 degrees to GATE_PULSE_MIN/MAX_US on SERVO_LEDC_CHANNEL.)

bool feederAutoMode = true;
unsigned long feederLastFeedEpoch = 0;
bool feederIsRunning = false;
String feederStatus = "idle";
String feederFeedSource = "";          // "manual", "onsite", or "scheduled"
String feederLastScheduleKey = "";     // doc id of the schedule that triggered the latest scheduled feed
int feederDispenseCount = 0;              // total feeds dispensed since boot
float feederRequestedGrams = 1.0f;    // 1 g-only model: N grams = N gate actuations
float feederFeedLevelBefore = -1.0f;
bool feederInitialized = false;
unsigned long feederLastScheduledMinute = 0;
unsigned long feederLastCompletedEpoch = 0;
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

// Firestore REST represents a Timestamp with an RFC 3339 timestampValue.
// Keep epoch milliseconds only for explicit ESP protocol fields such as
// capture/assignment metadata that are compared by the ingestion functions.
String firestoreTimestampString(time_t seconds) {
  if (seconds < 1700000000) return "";
  struct tm utc;
  if (gmtime_r(&seconds, &utc) == nullptr) return "";
  char buffer[25];
  snprintf(buffer, sizeof(buffer), "%04d-%02d-%02dT%02d:%02d:%02dZ",
           utc.tm_year + 1900, utc.tm_mon + 1, utc.tm_mday,
           utc.tm_hour, utc.tm_min, utc.tm_sec);
  return String(buffer);
}

// Non-blocking feeder state machine
enum FeederRunState {
  FEEDER_IDLE,
  FEEDER_PRE_BLOW,   // blower warm-up lead before the first actuation
  FEEDER_FORWARD,    // gate opens to GATE_OPEN_ANGLE
  FEEDER_PAUSE_F,    // gate holds, then closes and the cycle advances
  FEEDER_CLOSE_DWELL,// let the servo physically shut before the next gram
  FEEDER_DONE
};
FeederRunState feederRunState = FEEDER_IDLE;
int feederCurrentCycle = 0;
int feederMaxCycles = 1;               // 1 g-only: cycles = whole grams (5 g = 5 actuations)
unsigned long feederDoneShowMs = 0;    // LCD "Fed Xg OK" banner expiry
unsigned long feederStepMs = 0;
// Onsite override: bypassable block -> 10 s warning window -> 2-tap confirm.
#define OVERRIDE_WINDOW_MS 10000
#define OVERRIDE_CONFIRM_TAPS 2
String overrideWarnReason = "";        // non-empty = warning window open
float overrideGrams = 0;
int overrideConfirmTaps = 0;
unsigned long overrideDeadlineMs = 0;
bool feederForced = false;             // this run bypassed checks via confirm
String feederForceReason = "";
bool feederWaterQualityOverrideUsed = false;
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
bool allowWaterQualityFeeding = false;
unsigned long lastFeederPolicySyncMs = 0;

// ============================================================
//  ACTUATOR STATE — pump + 2 aerators
//  Firestore source of truth: tanks/{tankId}/actuators/{deviceId}
//    control_mode : "on" | "off" | "auto"   (written by Flutter app)
//    current_state: "on" | "off"            (actual relay state — ESP writes back)
//    last_changed : Firestore Timestamp (or null before the first device report)
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
// Hopper (feed) level ultrasonic — second HC-SR04 facing the feed surface.
// ECHO idles at 5V: same 1kΩ (ECHO->GPIO) + 2kΩ (GPIO->GND) divider rule as
// the water HC-SR04. Mount above max feed level, clear of the gate swing.
#define HOPPER_TRIG_PIN 17
#define HOPPER_ECHO_PIN 25

// Feeder gate — SG90 180-degree servo on GPIO5, the ONLY servo.
// 1 g-only model: every open/close actuation drops ~1 g (tune the mechanism
// with GATE_ANGLE/GATE_MS until GATECAL weighs ~10 g for 10 actuations);
// feed grams from the app decide the actuation count (5 g = 5 actuations).
// (GPIO5 has an internal pull-up through reset, and a servo signal line
// never pulls it low, so boot strapping is safe. GPIO25 door servo and
// GPIO13 scatter output are both retired.)
#define GATE_SERVO_PIN 5
#define GATE_MAX_ANGLE 180
#define GATE_PULSE_MIN_US 500
#define GATE_PULSE_MAX_US 2500
#define GATE_OPEN_ANGLE_DFLT 90    // starting point — tune on bench, store via GATE_ANGLE
#define GATE_HOLD_MS_DFLT 800      // starting point — tune on bench, store via GATE_MS
#define GATE_CLOSE_DWELL_MS 300    // let the servo shut between grams (mirrors GATECAL)
int gateOpenAngle = GATE_OPEN_ANGLE_DFLT;  // NVS "gateAngle"
int gateHoldMs = GATE_HOLD_MS_DFLT;        // NVS "gateHold"
int gateAngleNow = 0;

int _servoPulseToDuty(int pulseUs) {
  pulseUs = constrain(pulseUs, 500, 2600);
  return (int)((float)pulseUs / 20000.0f * 65535.0f);
}

void setGateAngle(int angle) {
  angle = constrain(angle, 0, GATE_MAX_ANGLE);
  int pulseUs = map(angle, 0, GATE_MAX_ANGLE,
                    GATE_PULSE_MIN_US, GATE_PULSE_MAX_US);
  ledcWrite(SERVO_LEDC_CHANNEL, _servoPulseToDuty(pulseUs));
  gateAngleNow = angle;
  Serial.printf("[GATE] Position=%d degrees | pulse=%d us\n", angle, pulseUs);
}

// SD card (SPI mode) — primary offline buffer when the internet is down;
// LittleFS remains the fallback when no card is present.
// (SD_SPI_* pins are defined just above the offline-buffer code so the
// mount helper can use them.)

// Onsite manual dispense button (to GND, INPUT_PULLUP, ISR taps).
// GPIO16 went back to the blower relay; GPIO12 is boot-safe for buttons.
#define ONSITE_BUTTON_PIN 12
#define ONSITE_BUTTON_DEBOUNCE_US 50000UL
#define ONSITE_BUTTON_BATCH_MS 1500UL
#define ONSITE_BUTTON_MAX_TAPS 200
volatile uint16_t onsiteButtonTapCount = 0;
volatile uint32_t onsiteButtonLastTapUs = 0;
volatile bool onsiteButtonEnabled = false;
portMUX_TYPE onsiteButtonMux = portMUX_INITIALIZER_UNLOCKED;
String lcdTransientLine0;
String lcdTransientLine1;
unsigned long lcdTransientUntilMs = 0;
bool lcdCloudBootPending = false;
unsigned long lcdCloudBootStartedMs = 0;
unsigned long lcdCloudBootLastDrawMs = 0;
void showLCDBootProgress(const String& label, uint8_t filledPixels);

// Blower (relay module, ACTIVE-LOW like the main relays) on GPIO16.
// Runs 5 s ahead of every feed (manual, cloud, scheduled, onsite) to warm
// up, stays ON through dispensing and for 10 s after the final gate closes.
// Manual control: n4on/n4off serial + GPIO2 physical toggle button.
#define BLOWER_PIN 16
#define BLOWER_PRE_SEC 5              // warm-up lead before every feed
#define BLOWER_POST_SEC 10            // stay ON after the final gate actuation
#define BLOWER_MAX_ON_MS (15UL * 60UL * 1000UL)  // safety timeout for manual runs
bool blowerOn = false;
bool blowerAutoHeld = false;          // true only when auto logic turned it ON
bool blowerPostRunPending = false;
unsigned long blowerOnSinceMs = 0;
unsigned long blowerPostRunStartedMs = 0;

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

float waterLevelLowThreshold = 15.0;
float waterLevelCriticalThreshold = 10.0;

float feedLevelLowThreshold = 20.0f;
float feedLevelCriticalThreshold = 10.0f;
float feedLevelEmptyVoltage = 0.50f;
float feedLevelFullVoltage = 2.80f;


float doVoltageScale = 4.0;
float doVoltageOffset = 0.0;
float phVoltageSlope = -5.70;
float phVoltageIntercept = 21.34;
int phFitPointCount = 2;  // NVS "phFitN"; 3 means provisional three-buffer regression
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
#define CAL_STREAM_DEFAULT_MS 100
#define CAL_STREAM_MIN_MS 20
#define CAL_STREAM_MAX_MS 2000
#define CAL_PH_STABLE_MS 60000UL
#define CAL_DO_STABLE_MS 30000UL
#define CAL_TURB_STABLE_MS 10000UL
#define CAL_PH_STABLE_SPREAD_V 0.010f
#define CAL_DO_STABLE_SPREAD_V 0.010f
#define CAL_TURB_STABLE_SPREAD_V 0.010f
#define CAL_STABLE_MAX_BLOCKS 3200  // >60 s at the minimum 20 ms stream interval
#define CAL_CAPTURE_MATCH_V 0.010f
#define SENSOR_FILTER_WINDOW 5
#define LIVE_PH_STABLE_SPREAD_V 0.010f
#define LIVE_DO_STABLE_SPREAD_V 0.020f
#define LIVE_TURB_STABLE_SPREAD_V 0.020f

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
SemaphoreHandle_t sensorStateMutex = nullptr;
SemaphoreHandle_t sensorIoMutex = nullptr;
SemaphoreHandle_t lcdMutex = nullptr;
SemaphoreHandle_t feederScheduleMutex = nullptr;
bool sensorTaskRunning = false;
bool lcdTaskRunning = false;

class MutexGuard {
 public:
  explicit MutexGuard(SemaphoreHandle_t mutex) : mutex_(mutex) {
    if (mutex_) xSemaphoreTake(mutex_, portMAX_DELAY);
  }
  ~MutexGuard() {
    if (mutex_) xSemaphoreGive(mutex_);
  }

 private:
  SemaphoreHandle_t mutex_;
};

float tempBuffer[SMOOTH_WINDOW];
uint8_t tempCount = 0;
uint8_t tempIndex = 0;
float smoothedTemp = -127.0;
float lastValidTemp = -127.0;
bool tempSensorOK = false;
uint8_t tempSkipCount = 0;
// Serial output is opt-in so continuous readings never interfere with commands.
// Sampling, Firestore uploads, buffering, and automation remain active.
volatile bool sensorOutputEnabled = false;
bool rawStreamEnabled = false;      // `raw on` 1 s voltage stream for calibration
unsigned long lastRawStreamMs = 0;
volatile bool calibrationMode = false;
enum CalibrationSensor : uint8_t { CAL_SENSOR_NONE, CAL_SENSOR_PH, CAL_SENSOR_DO, CAL_SENSOR_TURB };
volatile uint8_t calibrationStreamSensor = CAL_SENSOR_NONE;
uint16_t calibrationStreamIntervalMs = CAL_STREAM_DEFAULT_MS;
unsigned long calibrationLastAdcMs = 0;
unsigned long calibrationLastPrintMs = 0;
unsigned long calibrationStableSinceMs = 0;
uint32_t calibrationAdcSum = 0;
uint32_t calibrationMilliVoltSum = 0;
uint16_t calibrationAdcCount = 0;
uint16_t calibrationAdcMin = 4095;
uint16_t calibrationAdcMax = 0;
uint16_t calibrationMilliVoltMin = UINT16_MAX;
uint16_t calibrationMilliVoltMax = 0;
float calibrationStableVoltage = 0.0f;
float calibrationStableMinVoltage = 0.0f;
float calibrationStableMaxVoltage = 0.0f;
bool calibrationStable = false;
float calibrationBlockAvgVoltage[CAL_STABLE_MAX_BLOCKS];
unsigned long calibrationBlockMs[CAL_STABLE_MAX_BLOCKS];
uint16_t calibrationBlockHead = 0;
uint16_t calibrationBlockCount = 0;

float phVoltageSamples[SENSOR_FILTER_WINDOW] = {};
uint8_t phVoltageSampleCount = 0;
uint8_t phVoltageSampleNext = 0;
float phFilteredVoltage = 0.0f;
bool phReadingStable = false;
float doVoltageSamples[SENSOR_FILTER_WINDOW] = {};
uint8_t doVoltageSampleCount = 0;
uint8_t doVoltageSampleNext = 0;
float doFilteredVoltage = 0.0f;
bool doReadingStable = false;
float turbidityVoltageSamples[SENSOR_FILTER_WINDOW] = {};
uint8_t turbidityVoltageSampleCount = 0;
uint8_t turbidityVoltageSampleNext = 0;
float turbidityFilteredVoltage = 0.0f;
bool turbidityReadingStable = false;
float smoothedTurbidityNTU = 0.0;
bool turbiditySensorOK = false;
float turbidityVoltage = 0.0;

// ─── 10-min window means ───────────────────────────────────────────────
// Accumulated from ACCEPTED readings between history saves, so brief
// each ten-minute history entry stores one average per valid sensor. The ESP
// polls every 2 s, so each window can collect up to ~300 samples per sensor.
// Reset after every history write (or buffer append).
float winTempSum = 0.0f; uint16_t winTempN = 0;
float winTurbSum = 0.0f; uint16_t winTurbN = 0;
float winDOSum = 0.0f; uint16_t winDON = 0;
float winPHSum = 0.0f; uint16_t winPHN = 0;
float winWaterLevelSum = 0.0f; uint16_t winWaterLevelN = 0;
float winFeedLevelSum = 0.0f; uint16_t winFeedLevelN = 0;

void resetWindowAggregatesUnlocked() {
  winTempSum = 0.0f; winTempN = 0;
  winTurbSum = 0.0f; winTurbN = 0;
  winDOSum = 0.0f; winDON = 0;
  winPHSum = 0.0f; winPHN = 0;
  winWaterLevelSum = 0.0f; winWaterLevelN = 0;
  winFeedLevelSum = 0.0f; winFeedLevelN = 0;
}

void resetWindowAggregates() {
  MutexGuard sensorLock(sensorStateMutex);
  resetWindowAggregatesUnlocked();
}

// Accumulate one accepted reading into the 10-min window aggregates.
#define ACCUM_WINDOW(sumV, nV, val) \
  do { \
    (sumV) += (val); (nV)++; \
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

float feedLevelPercent = -1.0f;
float feedLevelVoltage = 0.0f;
bool feedLevelSensorOK = false;
float hopperDistanceCm = -1.0f;   // raw ultrasonic echo (hopper path)
float hopperEmptyCm = -1.0f;      // taught echo, empty hopper (NVS "hopEmpty")
float hopperFullCm = -1.0f;       // taught echo, full hopper (NVS "hopFull")
int feedLevelMode = 1;            // 0 = analog GPIO39, 1 = ultrasonic (NVS "feedMode")
bool hopperSensorOK = false;
const char* feedLevelSource = "none";  // "ultrasonic" | "analog" | "none"


struct TurbidityResult {
  float ntu;
  bool valid;
};

// ============================================================
//  GENERIC HELPERS
// ============================================================
float readAnalogVoltage(uint8_t pin) {
  MutexGuard ioLock(sensorIoMutex);
  long sum = 0;

  for (int i = 0; i < SAMPLE_COUNT; i++) {
    sum += analogRead(pin);
    delay(SAMPLE_DELAY_MS);
  }

  float avg = (float)sum / SAMPLE_COUNT;
  return avg * (3.3f / 4095.0f);
}

// Use the ESP32's eFuse/ADC-characterized millivolt conversion for the pH
// channel. Keep the legacy conversion above for other sensors until their
// existing voltage calibrations are explicitly migrated.
float readPHVoltage() {
  MutexGuard ioLock(sensorIoMutex);
  uint32_t sumMilliVolts = 0;
  for (int i = 0; i < SAMPLE_COUNT; i++) {
    sumMilliVolts += analogReadMilliVolts(PH_PIN);
    delay(SAMPLE_DELAY_MS);
  }
  return ((float)sumMilliVolts / SAMPLE_COUNT) / 1000.0f;
}

float saturationDOmgL(float tempC) {
  // Freshwater oxygen saturation approximation near sea level.
  const float t = constrain(tempC, 0.0f, 40.0f);
  return 14.652f - 0.41022f * t + 0.007991f * t * t -
         0.000077774f * t * t * t;
}

bool saveSensorCalibrations() {
  if (!prefs.begin("sensorcal", false)) return false;
  bool saved = true;
  saved &= prefs.putFloat("phV4Ref", 4.01f) == sizeof(float);
  saved &= prefs.putFloat("phSlope", phVoltageSlope) == sizeof(float);
  saved &= prefs.putFloat("phIntercept", phVoltageIntercept) == sizeof(float);
  saved &= prefs.putInt("phFitN", phFitPointCount) == sizeof(int32_t);
  saved &= prefs.putFloat("doScale", doVoltageScale) == sizeof(float);
  saved &= prefs.putFloat("doOffset", doVoltageOffset) == sizeof(float);
  saved &= prefs.putFloat("tankHeight", waterSensorHeightCm) == sizeof(float);
  saved &= prefs.putFloat("tankDepth", waterLevelCmMax) == sizeof(float);
  saved &= prefs.putFloat("turbClear", turbidityVClear) == sizeof(float);
  saved &= prefs.putFloat("turbDirty", turbidityVDirty) == sizeof(float);
  saved &= prefs.putFloat("turbAir", turbidityVAirMax) == sizeof(float);
  saved &= prefs.putFloat("feedEmpty", feedLevelEmptyVoltage) == sizeof(float);
  saved &= prefs.putFloat("feedFull", feedLevelFullVoltage) == sizeof(float);
  saved &= prefs.putFloat("hopEmpty", hopperEmptyCm) == sizeof(float);
  saved &= prefs.putFloat("hopFull", hopperFullCm) == sizeof(float);
  saved &= prefs.putInt("feedMode", feedLevelMode) == sizeof(int32_t);
  saved &= prefs.putInt("gateAngle", gateOpenAngle) == sizeof(int32_t);
  saved &= prefs.putInt("gateHold", gateHoldMs) == sizeof(int32_t);
  prefs.end();
  return saved;
}

uint32_t saveCalibrationPoint(const char* key, float value) {
  if (!prefs.begin("sensorcal", false)) return 0;
  const uint32_t written = prefs.putFloat(key, value);
  prefs.end();
  return written;
}

void loadSensorCalibrations() {
  prefs.begin("sensorcal", true);
  phVoltageSlope = prefs.getFloat("phSlope", phVoltageSlope);
  phVoltageIntercept = prefs.getFloat("phIntercept", phVoltageIntercept);
  phFitPointCount = prefs.getInt("phFitN", 2);
  if (phFitPointCount != 3) phFitPointCount = 2;
  doVoltageScale = prefs.getFloat("doScale", doVoltageScale);
  doVoltageOffset = prefs.getFloat("doOffset", doVoltageOffset);
  waterSensorHeightCm = prefs.getFloat("tankHeight", waterSensorHeightCm);
  waterLevelCmMax = prefs.getFloat("tankDepth", waterLevelCmMax);
  turbidityVClear = prefs.getFloat("turbClear", turbidityVClear);
  turbidityVDirty = prefs.getFloat("turbDirty", turbidityVDirty);
  turbidityVAirMax = prefs.getFloat("turbAir", turbidityVAirMax);
  feedLevelEmptyVoltage = prefs.getFloat("feedEmpty", feedLevelEmptyVoltage);
  feedLevelFullVoltage = prefs.getFloat("feedFull", feedLevelFullVoltage);
  hopperEmptyCm = prefs.getFloat("hopEmpty", hopperEmptyCm);
  hopperFullCm = prefs.getFloat("hopFull", hopperFullCm);
  feedLevelMode = prefs.getInt("feedMode", feedLevelMode);
  if (feedLevelMode != 0) feedLevelMode = 1;
  gateOpenAngle = constrain(prefs.getInt("gateAngle", gateOpenAngle), 10, GATE_MAX_ANGLE);
  gateHoldMs = constrain(prefs.getInt("gateHold", gateHoldMs), 100, 5000);
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

float pushMedianVoltage(float samples[], uint8_t& count, uint8_t& next,
                        float voltage) {
  samples[next] = voltage;
  next = (next + 1) % SENSOR_FILTER_WINDOW;
  if (count < SENSOR_FILTER_WINDOW) count++;

  float sorted[SENSOR_FILTER_WINDOW];
  for (uint8_t i = 0; i < count; ++i) sorted[i] = samples[i];
  for (uint8_t i = 1; i < count; ++i) {
    const float value = sorted[i];
    int j = i - 1;
    while (j >= 0 && sorted[j] > value) {
      sorted[j + 1] = sorted[j];
      --j;
    }
    sorted[j + 1] = value;
  }
  return sorted[count / 2];
}

float voltageWindowSpread(const float samples[], uint8_t count) {
  if (count == 0) return 0.0f;
  float low = samples[0];
  float high = samples[0];
  for (uint8_t i = 1; i < count; ++i) {
    low = min(low, samples[i]);
    high = max(high, samples[i]);
  }
  return high - low;
}

bool turbidityCalibrationValid() {
  return isfinite(turbidityVClear) && isfinite(turbidityVDirty) &&
      isfinite(turbidityVAirMax) && turbidityVClear <= 3.25f &&
      turbidityVDirty > turbidityVAirMax &&
      turbidityVClear > turbidityVDirty && turbidityVAirMax >= 0.0f;
}

unsigned long calibrationStableWindowMs(uint8_t sensor) {
  switch (sensor) {
    case CAL_SENSOR_PH: return CAL_PH_STABLE_MS;
    case CAL_SENSOR_DO: return CAL_DO_STABLE_MS;
    case CAL_SENSOR_TURB: return CAL_TURB_STABLE_MS;
    default: return CAL_PH_STABLE_MS;
  }
}

float calibrationStableSpreadV(uint8_t sensor) {
  switch (sensor) {
    case CAL_SENSOR_PH: return CAL_PH_STABLE_SPREAD_V;
    case CAL_SENSOR_DO: return CAL_DO_STABLE_SPREAD_V;
    case CAL_SENSOR_TURB: return CAL_TURB_STABLE_SPREAD_V;
    default: return CAL_PH_STABLE_SPREAD_V;
  }
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

  if (!turbidityCalibrationValid() || !isfinite(v) || v < turbidityVAirMax) {
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

void showLCDBoot(const String& line0, const String& line1, unsigned long holdMs = 900);

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
  showLCDBootProgress("Connecting WiFi", 0);
  WiFi.begin(s.c_str(), p.c_str());
  Serial.printf("[WIFI] Trying \"%s\"", s.c_str());
  for (int i = 0; i < 20; i++) {
    if (WiFi.status() == WL_CONNECTED) break;
    delay(500);
    showLCDBootProgress("Connecting WiFi", min(75, (i + 1) * 75 / 20));
    esp_task_wdt_reset();  // 10 s worst case here; keep the watchdog fed
    Serial.print(".");
  }
  Serial.println();
  if (WiFi.status() == WL_CONNECTED) {
    showLCDBootProgress("WiFi connected", 80);
    delay(600);
    showLCDBoot("WiFi network:", s, 1200);
  } else {
    showLCDBoot("WiFi failed", "Trying next...", 900);
  }
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
  showLCDBootProgress("WiFi profiles", 10);
  wifiMigrateLegacy();
  int n = wifiProfileCount();

  if (n == 0) {
    showLCDBoot("WiFi setup", "Use Serial Monitor", 1500);
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
    esp_task_wdt_reset();  // N dead profiles x ~13 s can exceed short timeouts
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
  showLCDBoot("WiFi offline", "Local mode", 900);
  Serial.println("Commands: WIFI_HELP | wifi set <SSID>|<PASS> | wifi list | wifi use <n> | wifiscan | RESET_WIFI");
}

void initTime() {
  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  showLCDBootProgress("Syncing time", 0);

  Serial.print("Syncing time");
  for (int i = 0; i < 20; i++) {
    time_t now;
    time(&now);

    if (now > 1700000000) {
      Serial.println(" OK");
      showLCDBootProgress("Time synced", 80);
      delay(600);
      return;
    }

    Serial.print(".");
    delay(500);
    showLCDBootProgress("Syncing time", min(75, (i + 1) * 75 / 20));
  }

  Serial.println(" skipped");
  showLCDBoot("Time not synced", "Check internet", 1200);
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
  // Tolerate slow TLS reads on weak links (default 10 s -> http -6).
  config.timeout.serverResponse = 30000;
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
  Serial.printf("[FIREBASE] Initial attempt returned after %lu ms; retries are limited to once per 15 minutes.\n",
                lastFirebaseAuthAttemptMs - firebaseBeginStartedMs);
}

String lastFirebaseAuthReport = "";

void printFirebaseAuthStatus(bool force) {
  if (!firebaseStarted) {
    Serial.println("[FIREBASE] Not started; waiting for Wi-Fi.");
    return;
  }
  TokenInfo info = Firebase.authTokenInfo();
  String report = String("[FIREBASE] auth=") + getTokenStatus(info) +
                  " | token=" + getTokenType(info) +
                  " | Wi-Fi=" + (WiFi.status() == WL_CONNECTED ? "connected" : "offline");
  // Idle serial stays quiet: the 10 s loop reporter prints only on change.
  // FIREBASE_STATUS forces a fresh print on demand.
  if (force || report != lastFirebaseAuthReport) {
    Serial.println(report);
    lastFirebaseAuthReport = report;
  }
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
  if (!firestoreGetDoc(path.c_str())) {
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
  if (!firestoreGetDoc(path.c_str())) {
    return false;
  }
  FirebaseJson doc;
  doc.setJsonData(fbdo.payload());
  float low = feedLevelLowThreshold;
  float critical = feedLevelCriticalThreshold;
  bool gotLow = readConfigFloatPath(
    doc, "fields/low_value/doubleValue", low, 1.0f, 50.0f);
  // Accept legacy documents until the app migrates them on read/save.
  if (!gotLow) {
    gotLow = readConfigFloatPath(
      doc, "fields/min_value/doubleValue", low, 1.0f, 50.0f);
  }
  const bool gotCritical = readConfigFloatPath(
    doc, "fields/critical_value/doubleValue", critical, 0.0f, 49.0f);
  if (!gotLow || !gotCritical || critical >= low) {
    Serial.println("[CONFIG] Invalid feed-level settings; retaining previous values.");
    return false;
  }
  feedLevelLowThreshold = low;
  feedLevelCriticalThreshold = critical;
  return true;
}

bool syncWaterLevelConfig() {
  String path = String("tanks/") + currentTankId + "/sensors/water_level";
  if (!firestoreGetDoc(path.c_str())) return false;
  FirebaseJson doc;
  doc.setJsonData(fbdo.payload());
  float low = waterLevelLowThreshold;
  float critical = waterLevelCriticalThreshold;
  bool gotLow = readConfigFloatPath(
    doc, "fields/low_value/doubleValue", low, 1.0f, 95.0f);
  bool gotCritical = readConfigFloatPath(
    doc, "fields/critical_value/doubleValue", critical, 0.0f, 94.0f);
  // Read legacy threshold documents until owners save the new Low/Critical UI.
  if (!gotLow) {
    gotLow = readConfigFloatPath(
      doc, "fields/min_value/doubleValue", low, 1.0f, 95.0f);
  }
  if (!gotCritical && gotLow) {
    float legacyMax = low + 5.0f;
    if (readConfigFloatPath(
          doc, "fields/max_value/doubleValue", legacyMax, 5.0f, 100.0f)) {
      critical = max(0.0f, low - 5.0f);
      gotCritical = true;
    }
  }
  if (!gotLow || !gotCritical || critical >= low) {
    Serial.println("[CONFIG] Invalid water-level thresholds; retaining previous values.");
    return false;
  }
  waterLevelLowThreshold = low;
  waterLevelCriticalThreshold = critical;
  return true;
}

// Thresholds are owned by the currently assigned tank. The tank ID is a
// cached credential refreshed by the assignment block in loop(), never here.
void syncConfigFromFirebase() {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) {
    if (sensorOutputEnabled) Serial.println("[CONFIG] No tank assigned; retaining firmware defaults.");
    return;
  }

  bool changed = true;
  changed &= syncTankRange("temperature",       tempCriticalLow,       tempCriticalHigh,       0.0,   50.0);
  changed &= syncTankRange("turbidity",         turbNtuMin,            turbNtuMax,             0.0, 1000.0);
  changed &= syncTankRange("dissolved_oxygen",  doCriticalLow,         doCriticalHigh,          0.0,   30.0);
  changed &= syncTankRange("ph_level",          phCriticalLow,         phCriticalHigh,          0.0,   14.0);
  changed &= syncWaterLevelConfig();
  changed &= syncFeedLevelConfig();
  // Keep a known-good same-tank configuration through temporary outages, but
  // require a complete fresh sync after startup or assignment changes.
  if (changed) feederConfigReady = true;

  if (changed) {
    Serial.printf("[CONFIG] Tank %s | Temp %.1f-%.1f | Turb %.0f-%.0f | DO %.1f-%.1f | pH %.1f-%.1f | Water critical <=%.1f, low <=%.1fcm\n",
                  currentTankId.c_str(), tempCriticalLow, tempCriticalHigh,
                  turbNtuMin, turbNtuMax, doCriticalLow, doCriticalHigh,
                  phCriticalLow, phCriticalHigh, waterLevelCriticalThreshold, waterLevelLowThreshold);
    Serial.printf("[CONFIG] Feed low <%.0f%% | critical <=%.0f%%\n",
                  feedLevelLowThreshold, feedLevelCriticalThreshold);
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
  // Firebase.ready() (token ready + connected) is the readiness signal and
  // must be checked FIRST. Core.authenticated only flips true after a
  // successful API call, so gating on it deadlocks every cloud path:
  // nothing ever goes out, so the flag never flips.
  // Outage mode: fail fast. Every cloud call site funnels through here, so
  // one gate suspends them all; only the loop probe bypasses (direct call).
  if (cloudOutage) return false;
  if (Firebase.ready()) {
    firebaseReady = true;
    return true;
  }
  // Not ready: throttle re-authentication so a failed email/password
  // sign-in is not retried by every cloud call in loop(), which would
  // quickly trigger Identity Toolkit rate limiting.
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
void buildFirestorePayload(FirebaseJson &json, bool includeTimestamp, time_t capturedAt = 0) {
  String hwId = getHardwareId();
  json.set("fields/hardwareId/stringValue", hwId);
  json.set("fields/source_tank_id/stringValue", currentTankId);
  json.set("fields/source_owner_uid/stringValue", currentOwnerUid);
  json.set("fields/source_assignment_at_ms/integerValue", String(currentAssignmentAtMs));
  if (capturedAt <= 0) time(&capturedAt);
  json.set("fields/captured_at_ms/integerValue", epochMillisString(capturedAt));
  const String recordedAt = firestoreTimestampString(capturedAt);
  if (recordedAt.length() > 0) {
    json.set("fields/recorded_at/timestampValue", recordedAt);
  }

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
    }
    return;
  }

  // ── 10-min HISTORY payload: one mean per available sensor window. ─────
  // Each average uses accepted readings collected since the last history
  // save. Sensors with no valid samples in this window are omitted.

  // Only include sensors that had valid samples in this 10-minute window.
  if (winTempN > 0) {
    json.set("fields/temperature/doubleValue", winTempSum / (float)winTempN);
  }
  if (winTurbN > 0) {
    json.set("fields/turbidity/doubleValue", winTurbSum / (float)winTurbN);
  }
  if (ENABLE_DO_SENSOR && winDON > 0) {
    json.set("fields/dissolved_oxygen/doubleValue", winDOSum / (float)winDON);
  }
  if (ENABLE_PH_SENSOR && winPHN > 0) {
    json.set("fields/ph_level/doubleValue", winPHSum / (float)winPHN);
  }
  if (winWaterLevelN > 0) {
    json.set("fields/water_level/doubleValue", winWaterLevelSum / (float)winWaterLevelN);
  }
  if (winFeedLevelN > 0) {
    json.set("fields/feed_level/doubleValue", winFeedLevelSum / (float)winFeedLevelN);
  }

  // captured_at_ms and recorded_at share the same NTP capture instant so
  // Firestore Rules can validate both direct and staged history documents.
}


// ─── Write latest sensor reading to Firestore ───────────────────────
// Path: tanks/{tankId}/sensor_readings/latest (fixed live document).
// Firestore Rules compare the payload's assignment identity against the
// current hardware_system/currentOwner document before allowing the write.
bool sendLatestToFirestore() {
  if (!ensureFirebaseReady()) return false;
  if (currentTankId.length() == 0 || currentOwnerUid.length() == 0 ||
      currentAssignmentAtMs < 1577836800000LL) {
    Serial.println("[FIRESTORE] Latest skipped: no current hardware assignment");
    return false;
  }

  FirebaseJson content;
  time_t capturedAt;
  time(&capturedAt);
  {
    MutexGuard sensorLock(sensorStateMutex);
    buildFirestorePayload(content, false, capturedAt);
  }
  if (capturedAt < 1577836800 || firestoreTimestampString(capturedAt).length() == 0) {
    Serial.println("[FIRESTORE] Latest skipped: device clock is not synchronized");
    return false;
  }

  // Advertise the pending offline backlog so the app can show
  // "Syncing N offline readings…" while the ESP flushes LittleFS.
  content.set("fields/buffered_entries/integerValue",
              String((unsigned long)countBufferedEntries()));

  const String docPath = "tanks/" + currentTankId + "/sensor_readings/latest";
  // Include every optional sensor field in the mask so omitted values are
  // removed instead of lingering as apparently fresh values from an older
  // reading.
  const char* updateMask = "hardwareId,source_tank_id,source_owner_uid,source_assignment_at_ms,captured_at_ms,recorded_at,buffered_entries,temperature,turbidity,turbidity_air,dissolved_oxygen,ph_level,water_level,feed_level";

  bool latestOk = Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "(default)",
                                                     docPath.c_str(), content.raw(), updateMask);
  reportCloudResult(latestOk);
  if (latestOk) {
    Serial.println("[FIRESTORE] Latest sent");
  } else {
    // Do not retry immediately. A second TLS operation against an already
    // wedged session commonly produces mRunUntil/mConnectSSL errors and puts
    // more pressure on heap. The main loop retries on the next 5-second slot.
    Serial.printf("[FIRESTORE ERROR] code=%d reason=%s | RSSI=%d dBm | heap=%u\n",
                  fbdo.httpCode(), fbdo.errorReason().c_str(), WiFi.RSSI(),
                  (unsigned)ESP.getFreeHeap());
  }
  return latestOk;
}

// ─── Write history entry to Firestore ───────────────────────────────
// Current-assignment history goes directly to its canonical day folder. If
// direct validation fails (for example, assignment changed while the device
// was offline), buffer it; the existing staging route will quarantine it
// rather than assigning old readings to a new owner.
void sendHistoryToFirestore() {
  // Build the payload FIRST (captures the 10-min window aggregates).
  FirebaseJson content;
  time_t capturedAt;
  time(&capturedAt);
  {
    // Snapshot and clear atomically. The sensor task keeps accumulating into
    // the next history window while the synchronous Firestore request runs.
    MutexGuard sensorLock(sensorStateMutex);
    buildFirestorePayload(content, true, capturedAt);
    resetWindowAggregatesUnlocked();
  }

  // WiFi/Firebase down: buffer the reading for later flush. (Previously we
  // returned early here and the reading was LOST — the whole point of the
  // store-and-forward buffer is to survive exactly this case.)
  if (WiFi.status() != WL_CONNECTED || !ensureFirebaseReady()) {
    if (bufferAppend(content.raw())) {
      Serial.printf("[BUF] Offline — buffered entry #%u\n",
                    (unsigned)countBufferedEntries());
    }
    return;
  }

  if (capturedAt < 1577836800 || firestoreTimestampString(capturedAt).length() == 0) {
    if (bufferAppend(content.raw())) {
      Serial.printf("[BUF] Clock unsynchronized; buffered entry #%u\n",
                    (unsigned)countBufferedEntries());
    }
    return;
  }

  // Without an assignment, keep the previous staging behavior so the Cloud
  // Function can retain/quarantine this record safely.
  if (currentTankId.length() == 0 || currentOwnerUid.length() == 0 ||
      currentAssignmentAtMs < 1577836800000LL) {
    const long long capturedMs = atoll(epochMillisString(capturedAt).c_str());
    char fallbackId[32];
    snprintf(fallbackId, sizeof(fallbackId), "r_%llu",
             static_cast<unsigned long long>(capturedMs));
    if (Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "(default)",
          "sensorIngestion/current/history", fallbackId, content.raw(), "")) {
      Serial.println("[FIRESTORE] Unassigned history staged for safe routing");
    } else if (bufferAppend(content.raw())) {
      Serial.printf("[BUF] Unassigned history buffered #%u\n",
                    (unsigned)countBufferedEntries());
    }
    return;
  }

  const long long capturedMs = atoll(epochMillisString(capturedAt).c_str());
  const time_t manilaEpoch = capturedAt + 8 * 60 * 60;
  struct tm manilaTm;
  char dateKey[11] = {0};
  char entryId[32];
  if (gmtime_r(&manilaEpoch, &manilaTm) == nullptr ||
      strftime(dateKey, sizeof(dateKey), "%Y-%m-%d", &manilaTm) == 0) {
    if (bufferAppend(content.raw())) {
      Serial.printf("[BUF] Could not resolve history date; buffered #%u\n",
                    (unsigned)countBufferedEntries());
    }
    return;
  }
  snprintf(entryId, sizeof(entryId), "r_%llu",
           static_cast<unsigned long long>(capturedMs));
  const String collectionPath = "tanks/" + currentTankId +
      "/sensor_readings_history/" + dateKey + "/entries";
  const String documentPath = collectionPath + "/" + entryId;

  bool saved = Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "(default)",
      collectionPath.c_str(), entryId, content.raw(), "");
  // Recover from a lost HTTP response without creating a duplicate history
  // record or placing it in the offline queue.
  if (!saved && fbdo.httpCode() == 409 && firestoreGetDoc(documentPath.c_str())) saved = true;
  reportCloudResult(saved);
  if (saved) {
    Serial.println("[FIRESTORE] History saved directly");
  } else {
    Serial.printf("[FIRESTORE HISTORY ERROR] %s\n", fbdo.errorReason().c_str());
    if (bufferAppend(content.raw())) {
      Serial.printf("[BUF] Buffered entry #%u for validated history routing\n",
                    (unsigned)countBufferedEntries());
    }
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
  turbidityVoltage = fv;
  turbidityFilteredVoltage = fv;
  turbidityVoltageSampleCount = 0;
  turbidityVoltageSampleNext = 0;
  for (uint8_t i = 0; i < SENSOR_FILTER_WINDOW; i++)
    turbidityVoltageSamples[i] = fv;
  turbidityVoltageSampleCount = SENSOR_FILTER_WINDOW;
  TurbidityResult tr = classifyTurbidity(fv);
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
    ACCUM_WINDOW(winTempSum, winTempN, rawTemp);
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
  const float rawVoltage = readAnalogVoltage(TURBIDITY_PIN);
  turbidityVoltage = rawVoltage;
  const float voltage = pushMedianVoltage(turbidityVoltageSamples,
      turbidityVoltageSampleCount, turbidityVoltageSampleNext, rawVoltage);
  turbidityFilteredVoltage = voltage;
  turbidityReadingStable = turbidityVoltageSampleCount == SENSOR_FILTER_WINDOW &&
      voltageWindowSpread(turbidityVoltageSamples, turbidityVoltageSampleCount) <=
          LIVE_TURB_STABLE_SPREAD_V;
  TurbidityResult tr = classifyTurbidity(voltage);

  if (!tr.valid) {
    turbiditySensorOK = false;
    smoothedTurbidityNTU = 0.0;
    if (sensorOutputEnabled) Serial.printf("[TURB] Invalid/air or calibration incomplete (V=%.3f)\n", voltage);
    return;
  }
  turbiditySensorOK = true;
  smoothedTurbidityNTU = tr.ntu;
  ACCUM_WINDOW(winTurbSum, winTurbN, tr.ntu);
}

void readDissolvedOxygenSensor() {
  if (!ENABLE_DO_SENSOR) {
    dissolvedOxygen = -1.0;
    return;
  }

  const float rawVoltage = readAnalogVoltage(DO_PIN);
  dissolvedOxygenVoltage = rawVoltage;
  const float voltage = pushMedianVoltage(doVoltageSamples,
      doVoltageSampleCount, doVoltageSampleNext, rawVoltage);
  doFilteredVoltage = voltage;
  doReadingStable = doVoltageSampleCount == SENSOR_FILTER_WINDOW &&
      voltageWindowSpread(doVoltageSamples, doVoltageSampleCount) <=
          LIVE_DO_STABLE_SPREAD_V;
  if (voltage < 0.05f || voltage > 3.25f) {
    dissolvedOxygen = -1.0f;
    doSensorOK = false;
    if (sensorOutputEnabled) Serial.printf("[DO] Invalid/disconnected voltage: %.3fV\n", dissolvedOxygenVoltage);
    return;
  }
  dissolvedOxygen = voltage * doVoltageScale + doVoltageOffset;
  if (!isfinite(dissolvedOxygen) || dissolvedOxygen < 0.0f || dissolvedOxygen > 20.0f) {
    dissolvedOxygen = -1.0f;
    doSensorOK = false;
    return;
  }
  doSensorOK = true;
  ACCUM_WINDOW(winDOSum, winDON, dissolvedOxygen);
}

void readPHSensor() {
  if (!ENABLE_PH_SENSOR) {
    phLevel = -1.0;
    return;
  }

  const float rawVoltage = readPHVoltage();
  phVoltage = rawVoltage;
  const float voltage = pushMedianVoltage(phVoltageSamples,
      phVoltageSampleCount, phVoltageSampleNext, rawVoltage);
  phFilteredVoltage = voltage;
  phReadingStable = phVoltageSampleCount == SENSOR_FILTER_WINDOW &&
      voltageWindowSpread(phVoltageSamples, phVoltageSampleCount) <=
          LIVE_PH_STABLE_SPREAD_V;
  if (voltage < 0.05f || voltage > 3.25f) {
    phLevel = -1.0f;
    phSensorOK = false;
    if (sensorOutputEnabled) Serial.printf("[PH] Invalid/disconnected voltage: %.3fV\n", phVoltage);
    return;
  }
  phLevel = phVoltageSlope * voltage + phVoltageIntercept;
  if (!isfinite(phLevel) || phLevel < 0.0f || phLevel > 14.0f) {
    phLevel = -1.0f;
    phSensorOK = false;
    return;
  }
  phSensorOK = true;
  ACCUM_WINDOW(winPHSum, winPHN, phLevel);
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
  ACCUM_WINDOW(winWaterLevelSum, winWaterLevelN, waterLevelCm);
}

// Raw hopper echo in cm, or -1 on timeout. Quiet — callers decide logging.
float measureHopperEcho() {
  digitalWrite(HOPPER_TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(HOPPER_TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(HOPPER_TRIG_PIN, LOW);
  const unsigned long durationUs = pulseIn(HOPPER_ECHO_PIN, HIGH, 30000UL);
  if (durationUs == 0) return -1.0f;
  return durationUs * 0.0343f / 2.0f;
}

void readHopperLevelSensor() {
  hopperSensorOK = false;
  hopperDistanceCm = measureHopperEcho();
  if (hopperDistanceCm < 0) {
    if (sensorOutputEnabled) Serial.println("[HOPPER] HC-SR04 timeout/disconnected");
    return;
  }
  if (hopperEmptyCm < 0 || hopperFullCm < 0 || hopperEmptyCm <= hopperFullCm) {
    if (sensorOutputEnabled) Serial.println("[HOPPER] Not calibrated — run hopperempty + hopperfull");
    return;
  }
  // Reject impossible geometry instead of constraining a bad echo into a
  // believable value that could unblock feeding on a false full hopper.
  if (hopperDistanceCm < hopperFullCm - 2.0f || hopperDistanceCm > hopperEmptyCm + 2.0f) {
    if (sensorOutputEnabled) {
      Serial.printf("[HOPPER] Invalid echo: distance=%.1fcm (full=%.1f empty=%.1f)\n",
                    hopperDistanceCm, hopperFullCm, hopperEmptyCm);
    }
    return;
  }
  hopperSensorOK = true;
}

void readFeedLevelSensor() {
  if (!ENABLE_FEED_LEVEL_SENSOR) {
    feedLevelSensorOK = false;
    feedLevelPercent = -1.0f;
    feedLevelSource = "none";
    return;
  }

  // Ultrasonic path first (default). A bad echo falls back to analog so one
  // failed sensor never stalls feeding on its own.
  if (feedLevelMode == 1) {
    readHopperLevelSensor();
    if (hopperSensorOK) {
      const float span = hopperEmptyCm - hopperFullCm;
      feedLevelPercent = constrain(
        (hopperEmptyCm - hopperDistanceCm) * 100.0f / span,
        0.0f,
        100.0f);
      feedLevelSensorOK = true;
      feedLevelSource = "ultrasonic";
      ACCUM_WINDOW(winFeedLevelSum, winFeedLevelN, feedLevelPercent);
      return;
    }
    if (sensorOutputEnabled) Serial.println("[FEED LEVEL] Ultrasonic invalid — falling back to analog");
  }

  feedLevelVoltage = readAnalogVoltage(FEED_LEVEL_PIN);
  const float span = feedLevelFullVoltage - feedLevelEmptyVoltage;
  if (!isfinite(feedLevelVoltage) || fabs(span) < 0.05f ||
      feedLevelVoltage < 0.02f || feedLevelVoltage > 3.28f) {
    feedLevelSensorOK = false;
    feedLevelPercent = -1.0f;
    feedLevelSource = "none";
    if (sensorOutputEnabled)
      Serial.printf("[FEED LEVEL] Invalid/disconnected voltage: %.3fV\n",
                    feedLevelVoltage);
    return;
  }

  feedLevelPercent = constrain(
    (feedLevelVoltage - feedLevelEmptyVoltage) * 100.0f / span,
    0.0f,
    100.0f);
  feedLevelSensorOK = true;
  feedLevelSource = "analog";
  ACCUM_WINDOW(winFeedLevelSum, winFeedLevelN, feedLevelPercent);
}

void readFeedLevelSensorSafely() {
  MutexGuard sensorLock(sensorStateMutex);
  readFeedLevelSensor();
}

void readAllSensors() {
  MutexGuard sensorLock(sensorStateMutex);
  readTemperatureSensor();
  readTurbiditySensor();
  readDissolvedOxygenSensor();
  readPHSensor();
  readWaterLevelSensor();
  readFeedLevelSensor();
}

void printSensorReading() {
  MutexGuard sensorLock(sensorStateMutex);
  Serial.printf("[SENSOR] Temp: %.1f C | Turb: %.0f NTU (%.3fV,%s) | DO: %.1f mg/L (%.3fV,%s) | pH: %.2f (%.3fV,%s) | Level: %.1f cm | Feed: %.1f%%\n",
                smoothedTemp, smoothedTurbidityNTU, turbidityVoltage,
                turbidityReadingStable ? "STABLE" : "SETTLING",
                dissolvedOxygen, dissolvedOxygenVoltage,
                doReadingStable ? "STABLE" : "SETTLING",
                phLevel, phVoltage, phReadingStable ? "STABLE" : "SETTLING",
                waterLevelCm, feedLevelPercent);
}

// One raw-voltage snapshot for calibration stability checks. Reuses the
// latest smoothed values (no extra ADC traffic); called by `raw` and by
// the 1 s `raw on` stream.
void printRawReading() {
  MutexGuard sensorLock(sensorStateMutex);
  Serial.printf("[RAW] pH=%.3fV DO=%.3fV Turb=%.3fV HC-SR04=%.1fcm Water=%.1fcm Feed=%.3fV/%.0f%% Hopper=%.1fcm(%s)\n",
                phVoltage, dissolvedOxygenVoltage, turbidityVoltage,
                waterDistanceCm, waterLevelCm, feedLevelVoltage,
                feedLevelPercent,
                hopperDistanceCm, feedLevelSource);
}

void printCalibrationHelp() {
  Serial.println("\n=== CALIBRATION COMMANDS ===");
  Serial.println("CALMODE ON/OFF          Pause Wi-Fi/Firebase for calibration");
  Serial.println("CALSTREAM PH|DO|TURB [ms] Stream one ADC (20-2000 ms; default 100)");
  Serial.println("CALSTOP / CALSTATUS     Stop stream / show calibration state");
  Serial.println("CALSHOW                 Show saved calibration values from NVM");
  Serial.println("phcal4                  Save stable-average voltage in pH 4.01 buffer");
  Serial.println("phcal9 9.18             Save stable-average voltage in pH 9.18 buffer");
  Serial.println("phfit                   Apply 2-point pH 4.01 + 9.18 calibration");
  Serial.println("phrefit                 Alias for phfit / refit saved points");
  Serial.println("doread                   Show current DO voltage/value");
  Serial.println("doclear                  Calibrate DO in air-saturated water");
  Serial.println("turbclear [VOLTS]        Save stable clear-water voltage");
  Serial.println("turbdirty [VOLTS]        Save stable dirty-water voltage");
  Serial.println("turbair [VOLTS]          Save stable out-of-water threshold");
  Serial.println("feedempty                Save voltage with an empty hopper");
  Serial.println("feedfull                 Save voltage with a full hopper");
  Serial.println("hopperempty              Teach ultrasonic empty-hopper echo");
  Serial.println("hopperfull               Teach ultrasonic full-hopper echo");
  Serial.println("FEEDMODE <0|1>           0=analog GPIO39, 1=ultrasonic");
  Serial.println("hopperheight <cm>        Manual sensor height (empty point)");
  Serial.println("hopperdepth <cm>         Manual max feed depth");
  Serial.println("BUFSTATUS                Offline buffer backend + counts");
  Serial.println("tankheight <CM>          Sensor-to-tank-bottom distance");
  Serial.println("tankdepth <CM>           Maximum water depth");
  Serial.println("tankcal                  Show tank calibration");
  Serial.println("raw [on|off]             Legacy raw snapshot / 1 s stream (normal mode)");
}

void resetCalibrationStream() {
  calibrationStreamSensor = CAL_SENSOR_NONE;
  calibrationLastAdcMs = millis();
  calibrationLastPrintMs = millis();
  calibrationStableSinceMs = 0;
  calibrationAdcSum = 0;
  calibrationMilliVoltSum = 0;
  calibrationAdcCount = 0;
  calibrationAdcMin = 4095;
  calibrationAdcMax = 0;
  calibrationMilliVoltMin = UINT16_MAX;
  calibrationMilliVoltMax = 0;
  calibrationStableVoltage = 0.0f;
  calibrationStableMinVoltage = 0.0f;
  calibrationStableMaxVoltage = 0.0f;
  calibrationStable = false;
  calibrationBlockHead = 0;
  calibrationBlockCount = 0;
}

uint8_t calibrationSensorForName(const String& name) {
  if (name == "PH") return CAL_SENSOR_PH;
  if (name == "DO") return CAL_SENSOR_DO;
  if (name == "TURB" || name == "TURBIDITY") return CAL_SENSOR_TURB;
  return CAL_SENSOR_NONE;
}

const char* calibrationSensorName(uint8_t sensor) {
  switch (sensor) {
    case CAL_SENSOR_PH: return "PH";
    case CAL_SENSOR_DO: return "DO";
    case CAL_SENSOR_TURB: return "TURB";
    default: return "NONE";
  }
}

uint8_t calibrationSensorPin(uint8_t sensor) {
  switch (sensor) {
    case CAL_SENSOR_PH: return PH_PIN;
    case CAL_SENSOR_DO: return DO_PIN;
    case CAL_SENSOR_TURB: return TURBIDITY_PIN;
    default: return 0;
  }
}

bool isSensorCalibrationCommand(const String& cmd) {
  return cmd == "phcal4" || cmd == "phcal7" || cmd == "phcal686" || cmd == "phcal9" ||
      cmd.startsWith("phcal9 ") || cmd == "phfit" || cmd == "phrefit" || cmd == "doread" || cmd == "doclear" ||
      cmd == "turbclear" || cmd.startsWith("turbclear ") ||
      cmd == "turbdirty" || cmd.startsWith("turbdirty ") ||
      cmd == "turbair" || cmd.startsWith("turbair ");
}

bool isAllowedDuringCalibration(const String& cmd) {
  return cmd == "HELP" || cmd == "help" || cmd == "?" ||
      cmd == "CAL_HELP" || cmd == "cal help" || cmd == "CALSTATUS" ||
      cmd == "CALSHOW" || cmd == "CALMODE OFF" || cmd == "CALSTOP" ||
      cmd.startsWith("CALSTREAM ") || isSensorCalibrationCommand(cmd);
}

void printSavedSensorCalibrations() {
  if (!prefs.begin("sensorcal", true)) {
    Serial.println("[CAL NVM] Could not open sensor calibration storage.");
    return;
  }
  const float ref4 = prefs.getFloat("phV4Ref", 4.01f);
  const float v4 = prefs.getFloat("phV4", -1.0f);
  const float v7 = prefs.getFloat("phV7", -1.0f);
  const float ref7 = prefs.getFloat("phV7Ref", 7.0f);
  const float v9 = prefs.getFloat("phV9", -1.0f);
  const float ref9 = prefs.getFloat("phV9Ref", 9.0f);
  const int pair = prefs.getInt("phPair", 4);
  prefs.end();
  Serial.printf("[CAL NVM] pH V4=%.4f (ref %.2f) V7=%.4f (ref %.2f) V9=%.4f (ref %.2f), pair=%d, fit=%d-point, slope=%.5f intercept=%.5f\n",
                v4, ref4, v7, ref7, v9, ref9, pair, phFitPointCount,
                phVoltageSlope, phVoltageIntercept);
  Serial.printf("[CAL NVM] DO scale=%.5f offset=%.5f | Turb clear=%.4f dirty=%.4f air=%.4f V mapping=%s\n",
                doVoltageScale, doVoltageOffset, turbidityVClear,
                turbidityVDirty, turbidityVAirMax,
                turbidityCalibrationValid() ? "VALID" : "INVALID/INCOMPLETE");
}

bool applySavedPHFit() {
  if (!prefs.begin("sensorcal", true)) {
    Serial.println("[CAL NVM] Cannot read saved pH points.");
    return false;
  }
  const float v4 = prefs.getFloat("phV4", -1.0f);
  const float ref4 = prefs.getFloat("phV4Ref", 4.01f);
  const float v7 = prefs.getFloat("phV7", -1.0f);
  const float ref7 = prefs.getFloat("phV7Ref", 7.0f);
  const float v9 = prefs.getFloat("phV9", -1.0f);
  const float ref9 = prefs.getFloat("phV9Ref", 9.0f);
  const int pair = prefs.getInt("phPair", 4);
  prefs.end();

  float nextSlope = 0.0f;
  float nextIntercept = 0.0f;
  int nextFitPointCount = 2;
  float appliedSpan = 0.0f;
  bool endpointTwoPointFit = false;
  const bool have3 = v4 > 0.05f && v4 <= 3.25f &&
      v7 > 0.05f && v7 <= 3.25f && v9 > 0.05f && v9 <= 3.25f &&
      isfinite(ref4) && isfinite(ref7) && isfinite(ref9);
  const bool haveEndpoints = v4 > 0.05f && v4 <= 3.25f &&
      v9 > 0.05f && v9 <= 3.25f && isfinite(ref4) && isfinite(ref9);
  const float totalSpan = max(v4, max(v7, v9)) - min(v4, min(v7, v9));

  // New pH calibration path: when phcal9 selected pair 9 and both endpoints
  // exist, use exactly pH 4.01 and 9.18 (ignore any stale legacy pH 7 point).
  if (pair == 9 && haveEndpoints) {
    const float voltageDelta = v9 - v4;
    appliedSpan = fabsf(voltageDelta);
    if (appliedSpan < 0.001f) {
      Serial.printf("[CAL] pH 4.01/9.18 points differ by only %.2fmV; cannot calculate a safe fit.\n",
                    appliedSpan * 1000.0f);
      return false;
    }
    nextSlope = (ref9 - ref4) / voltageDelta;
    nextIntercept = ref4 - nextSlope * v4;
    endpointTwoPointFit = true;
  } else if (pair != 9 && have3 && totalSpan > 0.05f &&
             ((v4 < v7 && v7 < v9) || (v4 > v7 && v7 > v9))) {
    const float meanV = (v4 + v7 + v9) / 3.0f;
    const float meanPH = (ref4 + ref7 + ref9) / 3.0f;
    const float numerator = (v4 - meanV) * (ref4 - meanPH) +
        (v7 - meanV) * (ref7 - meanPH) +
        (v9 - meanV) * (ref9 - meanPH);
    const float denominator = (v4 - meanV) * (v4 - meanV) +
        (v7 - meanV) * (v7 - meanV) +
        (v9 - meanV) * (v9 - meanV);
    if (denominator <= 0.0f) return false;
    nextSlope = numerator / denominator;
    nextIntercept = meanPH - nextSlope * meanV;
    nextFitPointCount = 3;
    appliedSpan = totalSpan;
  } else if (pair == 4) {
    const float otherV = v4;
    const float otherPH = ref4;
    if (v7 <= 0.05f || v7 > 3.25f || otherV <= 0.05f || otherV > 3.25f ||
        fabsf(v7 - otherV) <= 0.05f) {
      Serial.printf("[CAL] No fit applied: selected points differ by %.1fmV; need >50mV. Three-point fallback needs ordered points spanning >50mV.\n",
                    fabsf(v7 - otherV) * 1000.0f);
      return false;
    }
    nextSlope = (ref7 - otherPH) / (v7 - otherV);
    nextIntercept = ref7 - nextSlope * v7;
    appliedSpan = fabsf(v7 - otherV);
  } else {
    Serial.println("[CAL] No fit applied: pH 4.01/9.18 endpoint points are incomplete or invalid; previous fit retained.");
    return false;
  }

  const float oldSlope = phVoltageSlope;
  const float oldIntercept = phVoltageIntercept;
  const int oldFitPointCount = phFitPointCount;
  phVoltageSlope = nextSlope;
  phVoltageIntercept = nextIntercept;
  phFitPointCount = nextFitPointCount;
  if (!saveSensorCalibrations()) {
    phVoltageSlope = oldSlope;
    phVoltageIntercept = oldIntercept;
    phFitPointCount = oldFitPointCount;
    Serial.println("[CAL NVM] Could not save the new pH fit; previous active fit retained.");
    return false;
  }
  if (endpointTwoPointFit) {
    Serial.printf("[CAL NVM] Applied 2-point pH 4.01/9.18 fit: slope=%.5f intercept=%.5f; predictions=%.2f / %.2f; span=%.1fmV.\n",
                  phVoltageSlope, phVoltageIntercept,
                  phVoltageSlope * v4 + phVoltageIntercept,
                  phVoltageSlope * v9 + phVoltageIntercept,
                  appliedSpan * 1000.0f);
  } else {
    Serial.printf("[CAL NVM] Applied %d-point pH fit: slope=%.5f intercept=%.5f; predicted pH at saved V4/V7/V9 = %.2f / %.2f / %.2f.\n",
                  phFitPointCount, phVoltageSlope, phVoltageIntercept,
                  phVoltageSlope * v4 + phVoltageIntercept,
                  phVoltageSlope * v7 + phVoltageIntercept,
                  phVoltageSlope * v9 + phVoltageIntercept);
  }
  if (endpointTwoPointFit && appliedSpan < 0.05f) {
    Serial.printf("[CAL WARNING] 4.01/9.18 span is only %.1fmV; 10mV noise can shift pH by about %.2f. Fit saved, but verify carefully.\n",
                  appliedSpan * 1000.0f, fabsf(phVoltageSlope) * 0.010f);
  }
  if (phFitPointCount == 3 && totalSpan < 0.10f) {
    Serial.printf("[CAL WARNING] Three-point span is only %.1fmV; voltage noise can cause large pH changes. Treat as temporary; verify against buffers before using tank readings.\n",
                  totalSpan * 1000.0f);
  }
  return true;
}

void applyOfflineActuatorDefaults();

bool handleCalibrationControlCommand(String& cmd) {
  String upper = cmd;
  upper.toUpperCase();
  if (upper == "CALMODE ON") {
    if (calibrationMode) {
      Serial.println("[CAL] Already in calibration mode.");
    } else if (feederRunState != FEEDER_IDLE || feederIsRunning) {
      Serial.println("[CAL] Cannot enter while a feed is active; wait for it to finish.");
    } else {
      rawStreamEnabled = false;
      sensorOutputEnabled = false;
      resetCalibrationStream();
      calibrationMode = true;
      // Wait for any in-progress background scan to finish before starting a
      // selected-pin stream; subsequent polling cycles see calibrationMode.
      { MutexGuard sensorLock(sensorStateMutex); }
      // Drop Wi-Fi as well as pausing the main loop, so Firebase/auth traffic
      // cannot continue in the background during calibration.
      Firebase.reconnectWiFi(false);
      WiFi.disconnect(false, false);
      applyOfflineActuatorDefaults();
      Serial.println("[CAL] MODE ON — Wi-Fi/Firebase paused; serial calibration commands ready.");
      Serial.println("[CAL] Start with CALSTREAM PH|DO|TURB [20-2000 ms].");
    }
    cmd = "";
    return true;
  }
  if (upper == "CALMODE OFF") {
    if (!calibrationMode) {
      Serial.println("[CAL] Calibration mode is already OFF.");
    } else {
      calibrationStable = false;
      resetWindowAggregates();  // Do not mix calibration time with history means.
      resetCalibrationStream();
      calibrationMode = false;
      lastHistorySendTime = millis();
      lastFirebaseSendTime = millis();
      lastWifiReconnectTime = millis();
      Firebase.reconnectWiFi(true);
      WiFi.reconnect();
      Serial.println("[CAL] MODE OFF — normal sensing/cloud operation resuming; waiting for Wi-Fi.");
    }
    cmd = "";
    return true;
  }
  if (upper == "CALSTOP") {
    resetCalibrationStream();
    Serial.println("[CAL] Raw stream stopped; calibration mode remains ON.");
    cmd = "";
    return true;
  }
  if (upper == "CALSTATUS") {
    Serial.printf("[CAL] mode=%s stream=%s interval=%u ms stable=%s value=%.4fV Wi-Fi=%s\n",
                  calibrationMode ? "ON" : "OFF",
                  calibrationSensorName(calibrationStreamSensor),
                  calibrationStreamIntervalMs,
                  calibrationStable ? "YES" : "NO", calibrationStableVoltage,
                  WiFi.status() == WL_CONNECTED ? "connected" : "offline");
    cmd = "";
    return true;
  }
  if (upper == "CALSHOW") {
    printSavedSensorCalibrations();
    cmd = "";
    return true;
  }
  if (upper.startsWith("CALSTREAM ")) {
    if (!calibrationMode) {
      Serial.println("[CAL] Run CALMODE ON first; calibration stream is offline-only.");
    } else {
      String args = upper.substring(10);
      args.trim();
      const int split = args.indexOf(' ');
      const String sensorName = split < 0 ? args : args.substring(0, split);
      const uint8_t sensor = calibrationSensorForName(sensorName);
      if (sensor == CAL_SENSOR_NONE) {
        Serial.println("Usage: CALSTREAM PH|DO|TURB [20-2000 ms]");
      } else {
        int interval = CAL_STREAM_DEFAULT_MS;
        if (split >= 0) {
          String intervalText = args.substring(split + 1);
          intervalText.trim();
          interval = intervalText.toInt();
          if (interval < CAL_STREAM_MIN_MS || interval > CAL_STREAM_MAX_MS) {
            Serial.println("[CAL] Interval must be 20-2000 ms (default 100 ms).");
            cmd = "";
            return true;
          }
        }
        calibrationStreamIntervalMs = (uint16_t)interval;
        calibrationStreamSensor = sensor;
        phVoltageSampleCount = doVoltageSampleCount = turbidityVoltageSampleCount = 0;
        phVoltageSampleNext = doVoltageSampleNext = turbidityVoltageSampleNext = 0;
        calibrationLastAdcMs = millis();
        calibrationLastPrintMs = millis();
        calibrationStableSinceMs = 0;
        calibrationAdcSum = 0;
        calibrationMilliVoltSum = 0;
        calibrationAdcCount = 0;
        calibrationAdcMin = 4095;
        calibrationAdcMax = 0;
        calibrationMilliVoltMin = UINT16_MAX;
        calibrationMilliVoltMax = 0;
        calibrationStable = false;
        calibrationStableSinceMs = 0;
        calibrationStableMinVoltage = 0.0f;
        calibrationStableMaxVoltage = 0.0f;
        calibrationBlockHead = 0;
        calibrationBlockCount = 0;
        Serial.printf("[CAL] Streaming %s GPIO%u every %u ms; stable needs %lu s within %.0f mV across block averages.\n",
                      calibrationSensorName(sensor), calibrationSensorPin(sensor),
                      calibrationStreamIntervalMs,
                      calibrationStableWindowMs(sensor) / 1000UL,
                      calibrationStableSpreadV(sensor) * 1000.0f);
        Serial.println("[CALRAW] ms,sensor,adc_avg,Vadc,blockMinAvgV,blockMaxAvgV,rawMinV,rawMaxV,n,blocks,stable");
      }
    }
    cmd = "";
    return true;
  }
  return false;
}

bool calibrationCaptureReady(uint8_t sensor) {
  if (!calibrationMode) {
    Serial.println("[CAL] Enter CALMODE ON first; sensor calibration is offline-only.");
    return false;
  }
  if (calibrationStreamSensor != sensor) {
    Serial.printf("[CAL] Select this sensor first: CALSTREAM %s\n",
                  calibrationSensorName(sensor));
    return false;
  }
  if (!calibrationStable) {
    Serial.println("[CAL] Not stable yet — keep the probe in its reference and wait for stable=YES.");
    return false;
  }
  return true;
}

bool calibrationVoltageMatchesStable(float measuredVoltage) {
  const float tolerance = calibrationStableSpreadV(calibrationStreamSensor);
  if (fabsf(measuredVoltage - calibrationStableVoltage) > tolerance) {
    Serial.printf("[CAL] Capture rejected: entered %.4fV differs from stable-window average %.4fV by more than %.0fmV.\n",
                  measuredVoltage, calibrationStableVoltage,
                  tolerance * 1000.0f);
    return false;
  }
  return true;
}

float analogVoltageForCalibration(uint8_t sensor) {
  // Match the live pH path's eFuse-calibrated conversion rather than the
  // nominal 3.3/4095 scale used for the other ADC channels.
  if (sensor == CAL_SENSOR_PH) {
    uint32_t sumMilliVolts = 0;
    for (uint8_t i = 0; i < SAMPLE_COUNT; ++i) {
      sumMilliVolts += analogReadMilliVolts(PH_PIN);
      delay(SAMPLE_DELAY_MS);
    }
    return ((float)sumMilliVolts / SAMPLE_COUNT) / 1000.0f;
  }
  return readAnalogVoltage(calibrationSensorPin(sensor));
}

void runCalibrationStream() {
  const uint8_t sensor = calibrationStreamSensor;
  if (!calibrationMode || sensor == CAL_SENSOR_NONE) return;
  const unsigned long now = millis();
  if (now - calibrationLastAdcMs >= 2UL) {
    calibrationLastAdcMs = now;
    MutexGuard ioLock(sensorIoMutex);
    const uint16_t raw = analogRead(calibrationSensorPin(sensor));
    calibrationAdcSum += raw;
    calibrationAdcCount++;
    if (raw < calibrationAdcMin) calibrationAdcMin = raw;
    if (raw > calibrationAdcMax) calibrationAdcMax = raw;
    if (sensor == CAL_SENSOR_PH) {
      const uint16_t milliVolts = (uint16_t)analogReadMilliVolts(PH_PIN);
      calibrationMilliVoltSum += milliVolts;
      if (milliVolts < calibrationMilliVoltMin) calibrationMilliVoltMin = milliVolts;
      if (milliVolts > calibrationMilliVoltMax) calibrationMilliVoltMax = milliVolts;
    }
  }
  if (now - calibrationLastPrintMs < calibrationStreamIntervalMs ||
      calibrationAdcCount == 0) return;

  const float adcAvg = (float)calibrationAdcSum / calibrationAdcCount;
  const bool calibratedPH = sensor == CAL_SENSOR_PH && calibrationAdcCount > 0;
  const float avgV = calibratedPH
      ? ((float)calibrationMilliVoltSum / calibrationAdcCount) / 1000.0f
      : adcAvg * (3.3f / 4095.0f);
  const float rawMinV = calibratedPH
      ? calibrationMilliVoltMin / 1000.0f
      : calibrationAdcMin * (3.3f / 4095.0f);
  const float rawMaxV = calibratedPH
      ? calibrationMilliVoltMax / 1000.0f
      : calibrationAdcMax * (3.3f / 4095.0f);

  // Judge stability from successive interval averages, not individual ADC
  // extrema. A rolling 5-second range tolerates isolated raw spikes while
  // still detecting sustained drift in the averaged signal.
  if (calibrationBlockCount == CAL_STABLE_MAX_BLOCKS) {
    calibrationBlockHead = (calibrationBlockHead + 1) % CAL_STABLE_MAX_BLOCKS;
    calibrationBlockCount--;
  }
  const uint16_t tail = (calibrationBlockHead + calibrationBlockCount) % CAL_STABLE_MAX_BLOCKS;
  calibrationBlockAvgVoltage[tail] = avgV;
  calibrationBlockMs[tail] = now;
  calibrationBlockCount++;

  // Keep at least one sample that is >=5 s old. If we evict as soon as the
  // oldest block crosses 5 s, normal print-interval jitter can leave only 50
  // blocks spanning ~4.9 s forever, so stable=YES is never reached. Drop the
  // oldest only once the next-oldest block also preserves the full window.
  const unsigned long stableWindowMs = calibrationStableWindowMs(sensor);
  while (calibrationBlockCount > 1) {
    const uint16_t nextHead = (calibrationBlockHead + 1) % CAL_STABLE_MAX_BLOCKS;
    if (now - calibrationBlockMs[nextHead] < stableWindowMs) break;
    calibrationBlockHead = nextHead;
    calibrationBlockCount--;
  }

  calibrationStableMinVoltage = avgV;
  calibrationStableMaxVoltage = avgV;
  for (uint16_t i = 0; i < calibrationBlockCount; ++i) {
    const uint16_t index = (calibrationBlockHead + i) % CAL_STABLE_MAX_BLOCKS;
    calibrationStableMinVoltage = min(calibrationStableMinVoltage,
                                      calibrationBlockAvgVoltage[index]);
    calibrationStableMaxVoltage = max(calibrationStableMaxVoltage,
                                      calibrationBlockAvgVoltage[index]);
  }
  const bool fullStabilityWindow = calibrationBlockCount > 1 &&
      now - calibrationBlockMs[calibrationBlockHead] >= stableWindowMs;
  float blockSum = 0.0f;
  calibrationStable = fullStabilityWindow &&
      calibrationStableMaxVoltage - calibrationStableMinVoltage <=
          calibrationStableSpreadV(sensor);
  for (uint16_t i = 0; i < calibrationBlockCount; ++i) {
    const uint16_t index = (calibrationBlockHead + i) % CAL_STABLE_MAX_BLOCKS;
    blockSum += calibrationBlockAvgVoltage[index];
  }
  calibrationStableSinceMs = calibrationStable
      ? calibrationBlockMs[calibrationBlockHead] : 0;
  calibrationStableVoltage = calibrationBlockCount > 0
      ? blockSum / calibrationBlockCount : avgV;
  Serial.printf("[CALRAW] %lu,%s,%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%u,%u,%s\n",
                now, calibrationSensorName(sensor), adcAvg, avgV,
                calibrationStableMinVoltage, calibrationStableMaxVoltage,
                rawMinV, rawMaxV, calibrationAdcCount, calibrationBlockCount,
                calibrationStable ? "YES" : "NO");
  calibrationLastPrintMs = now;
  calibrationAdcSum = 0;
  calibrationMilliVoltSum = 0;
  calibrationAdcCount = 0;
  calibrationAdcMin = 4095;
  calibrationAdcMax = 0;
  calibrationMilliVoltMin = UINT16_MAX;
  calibrationMilliVoltMax = 0;
}

void printSerialHelp() {
  Serial.println("\n=== SERIAL COMMANDS ===");
  Serial.println("HELP                     Show this menu");
  Serial.println("SENSOR_ON                Print readings every 2 seconds");
  Serial.println("SENSOR_OFF               Stop periodic sensor printing");
  Serial.println("SENSOR_READ              Take and print one fresh reading");
  Serial.println("CAL_HELP                 Show calibration commands");
  Serial.println("CALMODE ON/OFF           Pause Wi-Fi/Firebase during sensor calibration");
  Serial.println("CALSTREAM PH|DO|TURB [ms] Stream selected ADC (20-2000 ms)");
  Serial.println("WIFI_HELP                Show Wi-Fi commands");
  Serial.println("FIREBASE_STATUS          Show cloud authentication status");
  Serial.println("FEED                     Start a 1 g manual feed");
  Serial.println("GATE_TEST                One gate actuation (GPIO5 SG90)");
  Serial.println("GATECAL                  10 actuations for weighing (~10 g)");
  Serial.println("GATE_ANGLE <10-180>      Gate open angle (NVS)");
  Serial.println("GATE_MS <100-5000>       Gate hold ms (NVS)");
  Serial.println("GPIO12 button            Onsite feed: taps = grams (1-200)");
  Serial.println("GPIO2 button             Blower manual ON/OFF toggle");
  Serial.println("n1on / n1off             Water pump (offline fallback forces ON)");
  Serial.println("n2on / n2off             Aerator 1 (offline fallback forces ON)");
  Serial.println("n3on / n3off             Aerator 2 (offline fallback forces ON)");
  Serial.println("n4on / n4off             Blower ON/OFF (GPIO16)");
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
void initBlower();
void setBlower(bool on, bool autoHeld);
void blowerAutoOff();
void blowerSafetyTick();
void initBlowerButton();
void pollBlowerButton();
void initLCD();
extern bool lcdReady;
void updateLCD();
void sensorPollingTask(void*);
void lcdDisplayTask(void*);
void showLCDBoot(const String& line0, const String& line1, unsigned long holdMs);
void showLCDTransient(const String& line0, const String& line1, unsigned long holdMs = 1800);
void initOnsiteButton();
void processOnsiteButton();
void armFeedOverride(float grams, const String& reason);
void pollFeedOverride();
void processFeederCommands();
void sendFeederStatus();
void syncFeederSchedules();
void loadCachedFeederSchedules();
void saveCachedFeederSchedules();
void loadFeederState();
bool saveFeederState();
void checkScheduledFeed();
void startFeed(String source, float grams = 1.0f, String commandId = "", long long issuedAtMs = 0, long long expiresAtMs = 0, bool forceOverride = false);
void processFeederTick();
void pushFeederLog(String action, String type, String status = "",
                   float requestedGrams = -1.0f,
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
  const char* resetReasonText = "unknown";
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: resetReasonText = "power-on"; break;
    case ESP_RST_EXT: resetReasonText = "external pin"; break;
    case ESP_RST_SW: resetReasonText = "software (esp_restart)"; break;
    case ESP_RST_PANIC: resetReasonText = "panic/exception"; break;
    case ESP_RST_INT_WDT: resetReasonText = "interrupt watchdog"; break;
    case ESP_RST_TASK_WDT: resetReasonText = "task watchdog"; break;
    case ESP_RST_WDT: resetReasonText = "other watchdog"; break;
    case ESP_RST_DEEPSLEEP: resetReasonText = "deep sleep wake"; break;
    case ESP_RST_BROWNOUT: resetReasonText = "brownout"; break;
    case ESP_RST_SDIO: resetReasonText = "SDIO"; break;
    default: break;
  }
  Serial.printf("[BOOT] Reset reason: %s\n", resetReasonText);

  // Task watchdog: the Arduino core pre-inits it at 5 s, and a bare
  // esp_task_wdt_init() is a no-op once initialized — so deinit first.
  // 60 s covers the worst legit block (30 s TLS x 2 attempts, GATECAL at
  // max hold) while still catching true hangs with a TASK_WDT trail.
  esp_task_wdt_deinit();
  esp_task_wdt_init(60, true);
  esp_task_wdt_add(NULL);

  sensorStateMutex = xSemaphoreCreateMutex();
  sensorIoMutex = xSemaphoreCreateMutex();
  lcdMutex = xSemaphoreCreateMutex();
  feederScheduleMutex = xSemaphoreCreateMutex();
  if (!sensorStateMutex || !sensorIoMutex || !lcdMutex || !feederScheduleMutex) {
    Serial.println("[TASK] Mutex allocation failed; using loop-based sensor/LCD updates");
  }

  // Energize life-support relays before sensor warm-up and network startup.
  initActuators();
  initLCD();
  showLCDBootProgress("CrayCare boot", 5);
  initOnsiteButton();

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  pinMode(WATER_LEVEL_TRIG_PIN, OUTPUT);
  digitalWrite(WATER_LEVEL_TRIG_PIN, LOW);
  pinMode(WATER_LEVEL_ECHO_PIN, INPUT);
  pinMode(HOPPER_TRIG_PIN, OUTPUT);
  digitalWrite(HOPPER_TRIG_PIN, LOW);
  pinMode(HOPPER_ECHO_PIN, INPUT);
  pinMode(FEED_LEVEL_PIN, INPUT);

  sensors.begin();
  loadSensorCalibrations();
  // Main firmware must keep using the saved 4.01/9.18 calibration pair.
  // The calibration command saves points and fit in NVS; rebuild once at boot
  // so stale legacy pH6.86 data cannot silently become the active curve.
  if (prefs.begin("sensorcal", true)) {
    const int savedPHCalibrationPair = prefs.getInt("phPair", 4);
    prefs.end();
    if (savedPHCalibrationPair == 9) {
      applySavedPHFit();
    }
  }

  showLCDBootProgress("Starting sensors", 20);
  primeTemperatureBuffer();
  primeTurbidityBuffer();
  showLCDBootProgress("Sensors ready", 80);
  delay(400);

  connectWiFi();
  initOfflineBuffer();  // LittleFS store-and-forward (mounted before loop)
  getHardwareId();  // resolve MAC-based ID after WiFi is up
  initFeeder();
  initBlower();
  initBlowerButton();
  // Larger read side for Firestore payloads: fewer -6 payload timeouts.
  fbdo.setResponseSize(8192);
  fbdo.setBSSLBufferSize(4096, 2048);
  if (WiFi.status() == WL_CONNECTED) {
    initTime();
    { time_t st; time(&st); if (st > 1700000000) { ntpEverSynced = true; lastNtpSyncMs = millis(); } }
    showLCDBootProgress("Starting cloud", 0);
    connectFirebase();
    lcdCloudBootPending = true;
    lcdCloudBootStartedMs = millis();
  } else {
    showLCDBoot("WiFi offline", "Local mode", 1300);
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
  onsiteButtonEnabled = true;
  if (!lcdCloudBootPending) {
    showLCDBoot("CrayCare ready", "Local mode", 1200);
  }

  if (sensorStateMutex && sensorIoMutex &&
      xTaskCreatePinnedToCore(sensorPollingTask, "sensor_poll", 8192, nullptr,
                              2, nullptr, 1) == pdPASS) {
    sensorTaskRunning = true;
    Serial.println("[SENSOR] Background polling task started (2 s interval)");
  } else {
    Serial.println("[SENSOR] Background task unavailable; polling in main loop");
  }

  if (lcdReady && lcdMutex && feederScheduleMutex &&
      xTaskCreatePinnedToCore(lcdDisplayTask, "lcd_display", 6144, nullptr,
                              1, nullptr, 1) == pdPASS) {
    lcdTaskRunning = true;
    Serial.println("[LCD] Background display task started (3 s page rotation)");
  } else {
    Serial.println("[LCD] Background task unavailable; display in main loop");
  }
}

// ============================================================
//  LOOP
// ============================================================
void loop() {
  esp_task_wdt_reset();  // fed every pass (< 1 s normally)
  processOnsiteButton();
  pollBlowerButton();
  pollFeedOverride();
  // Motor timing must never wait behind a blocking cloud/sensor operation.
  if (feederRunState != FEEDER_IDLE) {
    processFeederTick();
    if (!lcdTaskRunning) updateLCD();
    delay(1);
    return;
  }
  unsigned long now = millis();

  // ─── Serial Commands ───
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (!handleCalibrationControlCommand(cmd)) {
      if (calibrationMode && !isAllowedDuringCalibration(cmd)) {
        Serial.println("[CAL] Command blocked while calibrating; use CALMODE OFF to resume normal commands.");
        cmd = "";
      } else if (!calibrationMode && isSensorCalibrationCommand(cmd)) {
        Serial.println("[CAL] Enter CALMODE ON first so Firebase/Wi-Fi are paused during calibration.");
        cmd = "";
      }
    }
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
      printFirebaseAuthStatus(true);
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
    if (cmd == "timesync" || cmd == "ntp sync" || cmd == "ntpsync") {
      initTime();
      time_t nt2;
      time(&nt2);
      if (nt2 > 1700000000) {
        ntpEverSynced = true;
        lastNtpSyncMs = millis();
        Serial.println("[TIME] Manual NTP sync OK");
      } else {
        Serial.println("[TIME] Manual NTP sync failed (offline?)");
      }
    }
    if (cmd == "FEED") {
      startFeed("manual");
      if (feederRunState != FEEDER_IDLE) return;
    }
    if (cmd == "GATE_TEST" || cmd == "gate test") {
      if (feederRunState != FEEDER_IDLE) {
        Serial.println("[GATE] Feeder busy — try after the feed finishes");
      } else {
        Serial.printf("[GATE] Test: one actuation 0 -> %d -> 0\n", gateOpenAngle);
        setGateAngle(gateOpenAngle);
        delay(gateHoldMs);
        setGateAngle(0);
        delay(300);
        Serial.println("[GATE] Test complete");
      }
    }
    if (cmd == "GATECAL" || cmd == "gatecal") {
      if (feederRunState != FEEDER_IDLE) {
        Serial.println("[GATE] Feeder busy — try after the feed finishes");
      } else {
        Serial.println("[GATE] Calibration: 10 actuations — catch and weigh the output.");
        Serial.println("[GATE] Target ~10 g total (1 g each). If off, adjust with");
        Serial.println("[GATE] GATE_ANGLE / GATE_MS and repeat until 10 actuations = ~10 g.");
        for (int i = 0; i < 10; i++) {
          setGateAngle(gateOpenAngle);
          delay(gateHoldMs);
          setGateAngle(0);
          delay(300);
          esp_task_wdt_reset();  // 10 cycles x (hold + dwell) exceeds short timeouts
          Serial.printf("[GATE] Actuation %d/10\n", i + 1);
        }
        Serial.println("[GATE] Done — weigh total (expect ~10 g for the 1 g-only model)");
      }
    }
    if (cmd.startsWith("GATE_ANGLE ") || cmd.startsWith("gate_angle ")) {
      int v = cmd.substring(cmd.lastIndexOf(' ') + 1).toInt();
      if (v < 10 || v > GATE_MAX_ANGLE) {
        Serial.println("Usage: GATE_ANGLE <10-180>");
      } else {
        gateOpenAngle = v;
        saveSensorCalibrations();
        Serial.printf("[GATE] Open angle %d saved\n", gateOpenAngle);
      }
    }
    if (cmd.startsWith("GATE_MS ") || cmd.startsWith("gate_ms ")) {
      int v = cmd.substring(cmd.lastIndexOf(' ') + 1).toInt();
      if (v < 100 || v > 5000) {
        Serial.println("Usage: GATE_MS <100-5000>");
      } else {
        gateHoldMs = v;
        saveSensorCalibrations();
        Serial.printf("[GATE] Hold %d ms saved\n", gateHoldMs);
      }
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
    if (cmd == "phcal7" || cmd == "phcal686" || cmd == "phcal4" || cmd == "phcal9" ||
        cmd.startsWith("phcal9 ")) {
      const bool isNeutral = cmd == "phcal7" || cmd == "phcal686";
      const float neutralReference = cmd == "phcal686" ? 6.86f : 7.00f;
      const bool isNine = cmd == "phcal9" || cmd.startsWith("phcal9 ");
      float nineReference = 9.0f;
      if (cmd.startsWith("phcal9 ")) {
        String valueText = cmd.substring(7);
        valueText.trim();
        char* end = nullptr;
        nineReference = strtof(valueText.c_str(), &end);
        if (end == valueText.c_str() || *end != '\0' ||
            !isfinite(nineReference) || nineReference < 8.0f ||
            nineReference > 10.0f) {
          Serial.println("[CAL] Usage: phcal9 [buffer pH from 8.00 to 10.00]");
          return;
        }
      }
      if (!calibrationCaptureReady(CAL_SENSOR_PH)) return;
      const float v = calibrationStableVoltage;
      if (v <= 0.05f || v > 3.25f) {
        Serial.printf("[CAL] pH point rejected: stable-window voltage %.4fV is outside ADC range.\n", v);
        return;
      }
      if (!prefs.begin("sensorcal", false)) {
        Serial.println("[CAL NVM] Could not open sensor calibration storage; pH point not saved.");
        return;
      }
      bool pointSaved = prefs.putFloat(isNeutral ? "phV7" : isNine ? "phV9" : "phV4", v) == sizeof(float);
      if (cmd == "phcal4") prefs.putFloat("phV4Ref", 4.01f);
      if (isNeutral) prefs.putFloat("phV7Ref", neutralReference);
      if (isNine) {
        prefs.putFloat("phV9Ref", nineReference);
        prefs.putInt("phPair", 9);
      } else if (cmd == "phcal4") {
        prefs.putInt("phPair", 4);
      }
      pointSaved &= prefs.getFloat(isNeutral ? "phV7" : isNine ? "phV9" : "phV4", -1.0f) == v;
      prefs.end();
      if (!pointSaved) {
        Serial.println("[CAL NVM] pH calibration point write failed; check NVS and retry.");
        return;
      }
      Serial.printf("[CAL NVM] Saved stable-average %.4fV for %s; attempting fit from saved buffer points.\n",
                    v, cmd.c_str());
      applySavedPHFit();
    }
    if (cmd == "phrefit" || cmd == "phfit") {
      if (!calibrationMode) {
        Serial.println("[CAL] Enter CALMODE ON first; sensor calibration is offline-only.");
      } else {
        if (cmd == "phfit") {
          if (!prefs.begin("sensorcal", false)) {
            Serial.println("[CAL NVM] Could not select the pH 4.01/9.18 endpoint pair.");
            return;
          }
          prefs.putInt("phPair", 9);
          prefs.end();
        }
        applySavedPHFit();
      }
    }
    if (cmd == "doread") {
      if (!calibrationMode) {
        Serial.println("[CAL] Enter CALMODE ON first.");
      } else if (calibrationStreamSensor != CAL_SENSOR_DO) {
        Serial.println("[CAL] Select DO first: CALSTREAM DO");
      } else {
        const float v = calibrationStable
            ? calibrationStableVoltage
            : doVoltageSampleCount ? doFilteredVoltage : readAnalogVoltage(DO_PIN);
        float tempC;
        {
          MutexGuard sensorLock(sensorStateMutex);
          tempC = smoothedTemp;
        }
        const float oxygen = v > 0.05f
            ? v * doVoltageScale + doVoltageOffset : -1.0f;
        Serial.printf("[CAL] DO voltage=%.4fV current=%.2fmg/L temp=%.1fC calibration-stable=%s\n",
                      v, oxygen, tempC, calibrationStable ? "YES" : "NO");
      }
    }
    if (cmd == "doclear") {
      if (!calibrationCaptureReady(CAL_SENSOR_DO)) return;
      const float v = calibrationStableVoltage;
      float tempC;
      bool tempValid;
      {
        MutexGuard sensorLock(sensorStateMutex);
        readTemperatureSensor();
        tempC = smoothedTemp;
        tempValid = tempSensorOK && isfinite(tempC) && tempC > -10.0f && tempC < 60.0f;
      }
      if (!tempValid) {
        Serial.println("[CAL] DO calibration not saved: water temperature sensor is not valid.");
      } else if (v > 0.05f && v <= 3.25f) {
        doVoltageScale = saturationDOmgL(tempC) / v;
        doVoltageOffset = 0.0f;
        if (saveSensorCalibrations()) {
          Serial.printf("[CAL NVM] DO saved from stable-window average %.4fV at %.1fC, scale=%.4f\n",
                        v, tempC, doVoltageScale);
        } else {
          Serial.println("[CAL NVM] DO fit could not be saved; check NVS and retry.");
        }
      } else if (v <= 0.05f || v > 3.25f) {
        Serial.printf("[CAL] DO calibration not saved: invalid ADC voltage %.4fV\n", v);
      }
    }
    // Calibration commands capture the rolling stable-window voltage when no
    // explicit value is supplied. Saving points independently supports sensor
    // divider values that differ greatly from the original factory defaults.
    if (cmd == "turbclear" || cmd.startsWith("turbclear ")) {
      const bool hasArgument = cmd.length() > 9;
      if (!calibrationCaptureReady(CAL_SENSOR_TURB)) return;
      const float v = hasArgument ? cmd.substring(10).toFloat() : calibrationStableVoltage;
      if (hasArgument && !calibrationVoltageMatchesStable(v)) return;
      if (!isfinite(v) || v <= 0.0f || v > 3.3f) {
        Serial.printf("[CAL] turbclear rejected: stable/entered value must be 0 < V <= 3.25, got %.4fV\n", v);
        return;
      }
      const float previous = turbidityVClear;
      turbidityVClear = v;
      if (!saveSensorCalibrations()) { turbidityVClear = previous; Serial.println("[CAL NVM] Turbidity point not saved."); return; }
      Serial.printf("[CAL NVM] Clear-water point saved: %.4fV. Mapping %s.\n", v,
                    turbidityCalibrationValid() ? "VALID" : "incomplete; save dirty and air points");
    }
    if (cmd == "turbdirty" || cmd.startsWith("turbdirty ")) {
      const bool hasArgument = cmd.length() > 9;
      if (!calibrationCaptureReady(CAL_SENSOR_TURB)) return;
      const float v = hasArgument ? cmd.substring(10).toFloat() : calibrationStableVoltage;
      if (hasArgument && !calibrationVoltageMatchesStable(v)) return;
      if (!isfinite(v) || v <= 0.0f || v > 3.3f) {
        Serial.printf("[CAL] turbdirty rejected: stable/entered value must be 0 < V <= 3.25, got %.4fV\n", v);
        return;
      }
      const float previous = turbidityVDirty;
      turbidityVDirty = v;
      if (!saveSensorCalibrations()) { turbidityVDirty = previous; Serial.println("[CAL NVM] Turbidity point not saved."); return; }
      Serial.printf("[CAL NVM] Dirty-water point saved: %.4fV. Mapping %s.\n", v,
                    turbidityCalibrationValid() ? "VALID" : "incomplete; save clear and air points");
    }
    if (cmd == "turbair" || cmd.startsWith("turbair ")) {
      const bool hasArgument = cmd.length() > 7;
      if (!calibrationCaptureReady(CAL_SENSOR_TURB)) return;
      const float v = hasArgument ? cmd.substring(8).toFloat() : calibrationStableVoltage;
      if (hasArgument && !calibrationVoltageMatchesStable(v)) return;
      if (!isfinite(v) || v < 0.0f || v > 3.3f) {
        Serial.printf("[CAL] turbair rejected: stable/entered threshold must be 0 <= V <= 3.25, got %.4fV\n", v);
        return;
      }
      const float previous = turbidityVAirMax;
      turbidityVAirMax = v;
      if (!saveSensorCalibrations()) { turbidityVAirMax = previous; Serial.println("[CAL NVM] Turbidity threshold not saved."); return; }
      Serial.printf("[CAL NVM] Air/no-water threshold saved: %.4fV. Mapping %s.\n", v,
                    turbidityCalibrationValid() ? "VALID" : "incomplete; save all points in Vclear > Vdirty > Vair order");
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
    if (cmd == "hopperempty") {
      float d = measureHopperEcho();
      if (d < 0) {
        Serial.println("[CAL] hopperempty failed: no echo — check TRIG 17 / ECHO 25 wiring");
      } else {
        hopperEmptyCm = d;
        saveSensorCalibrations();
        Serial.printf("[CAL] Hopper EMPTY echo = %.1fcm\n", hopperEmptyCm);
      }
    }
    if (cmd == "hopperfull") {
      float d = measureHopperEcho();
      if (d < 0) {
        Serial.println("[CAL] hopperfull failed: no echo — check TRIG 17 / ECHO 25 wiring");
      } else if (d >= hopperEmptyCm) {
        Serial.printf("[CAL] hopperfull rejected: full echo %.1fcm must be SHORTER than empty %.1fcm\n",
                      d, hopperEmptyCm);
      } else {
        hopperFullCm = d;
        saveSensorCalibrations();
        Serial.printf("[CAL] Hopper FULL echo = %.1fcm (span %.1fcm)\n",
                      hopperFullCm, hopperEmptyCm - hopperFullCm);
      }
    }
    if (cmd.startsWith("FEEDMODE ") || cmd.startsWith("feedmode ")) {
      int v = cmd.substring(cmd.lastIndexOf(' ') + 1).toInt();
      if (v != 0 && v != 1) {
        Serial.println("Usage: FEEDMODE <0|1>  (0=analog GPIO39, 1=ultrasonic)");
      } else {
        feedLevelMode = v;
        saveSensorCalibrations();
        Serial.printf("[CAL] Feed level source = %s\n", v == 1 ? "ultrasonic" : "analog");
      }
    }
    if (cmd.startsWith("hopperheight ")) {
      const float v = cmd.substring(13).toFloat();
      if (v > 5.0f && v < 200.0f) {
        hopperEmptyCm = v;
        saveSensorCalibrations();
        Serial.printf("[CAL] Hopper sensor height = %.1f cm (empty point)\n", v);
      } else {
        Serial.println("Usage: hopperheight <5-200>  (sensor height above hopper floor, cm)");
      }
    }
    if (cmd.startsWith("hopperdepth ")) {
      const float v = cmd.substring(12).toFloat();
      if (v > 1.0f && v < hopperEmptyCm) {
        hopperFullCm = hopperEmptyCm - v;
        saveSensorCalibrations();
        Serial.printf("[CAL] Hopper max depth = %.1f cm (full echo %.1fcm)\n", v, hopperFullCm);
      } else {
        Serial.println("Usage: hopperdepth <1-empty>  (max feed depth, cm)");
      }
    }
    if (cmd == "raw") {
      printRawReading();
    }
    if (cmd == "raw on" || cmd == "raw stream") {
      rawStreamEnabled = true;
      lastRawStreamMs = 0;  // stream prints on the next loop pass
      Serial.println("[RAW] Stream ON (1 s, 'raw off' to stop)");
      printRawReading();
    }
    if (cmd == "raw off" || cmd == "raw stop") {
      rawStreamEnabled = false;
      Serial.println("[RAW] Stream OFF");
    }
    if (cmd == "BUFSTATUS" || cmd == "bufstatus") {
      size_t lfs = littlefsMounted ? countEntriesIn(LittleFS, BUFFER_PATH) : 0;
      size_t sdc = sdMounted ? countEntriesIn(SD, SD_BUFFER_PATH) : 0;
      Serial.printf("[BUF] backend=%s LittleFS=%u SD=%u total=%u\n",
                    sdMounted ? "SD" : "LittleFS",
                    (unsigned)lfs, (unsigned)sdc, (unsigned)(lfs + sdc));
      Serial.printf("[BUF] heap=%uB min=%uB uptime=%lus ntp=%s\n",
                    (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getMinFreeHeap(),
                    millis() / 1000UL, ntpEverSynced ? "synced" : "unsynced");
      if (sdMounted) {
        uint64_t total = SD.cardSize(), used = SD.usedBytes();
        Serial.printf("[BUF] SD type=%u size=%lluMB used=%lluMB file=%s\n",
                      (unsigned)SD.cardType(),
                      total / (1024ULL * 1024ULL), used / (1024ULL * 1024ULL),
                      SD_BUFFER_PATH);
      } else {
        Serial.println("[BUF] No SD card — LittleFS active");
      }
    }
    // Relay test commands (local only — cloud mode re-asserts on next sync)
    if (cmd == "n1on")  { setActuatorRelay(0, true);  reportActuatorState(0, true); }
    if (cmd == "n1off") { setActuatorRelay(0, false); reportActuatorState(0, true); }
    if (cmd == "n2on")  { setActuatorRelay(1, true);  reportActuatorState(1, true); }
    if (cmd == "n2off") { setActuatorRelay(1, false); reportActuatorState(1, true); }
    if (cmd == "n3on")  { setActuatorRelay(2, true);  reportActuatorState(2, true); }
    if (cmd == "n3off") { setActuatorRelay(2, false); reportActuatorState(2, true); }
    if (cmd == "n4on" || cmd == "n4off") {
      setBlower(cmd == "n4on", false);
    }
    if (cmd == "relay status" || cmd == "relaystatus") {
      for (int i = 0; i < 3; i++) {
        Serial.printf("  %s (GPIO %d): %s | mode=%s\n",
                      actuators[i].label, actuators[i].pin,
                      actuators[i].relayOn ? "ON" : "OFF",
                      actuators[i].controlMode.c_str());
      }
      Serial.printf("  Blower (GPIO %d): %s%s\n", BLOWER_PIN, blowerOn ? "ON" : "OFF",
                    blowerAutoHeld ? " (auto)" : "");
    }
  }

  if (calibrationMode) {
    runCalibrationStream();
    if (!lcdTaskRunning) updateLCD();
    delay(1);
    return;  // Do not reconnect Wi-Fi or run any cloud/control work in CALMODE.
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

  // Time maintenance: boot sync happens in setup; re-sync daily while online
  // (clock drift + post-outage/offline-boot recovery). Deferred while feeding;
  // the bounded ~10 s initTime() block is WDT-safe at 60 s. The stamp updates
  // on every attempt so a dead NTP server cannot wedge the loop.
  if (networkAvailable && feederRunState == FEEDER_IDLE &&
      (!ntpEverSynced || now - lastNtpSyncMs >= NTP_RESYNC_INTERVAL_MS)) {
    initTime();
    time_t nt;
    time(&nt);
    if (nt > 1700000000) ntpEverSynced = true;
    lastNtpSyncMs = millis();
    now = lastNtpSyncMs;
  }

  // Start Firebase only after Wi-Fi exists. Never block serial commands while
  // offline or while email/password authentication is still in progress.
  if (networkAvailable && !firebaseStarted) connectFirebase();
  if (networkAvailable && firebaseStarted && !cloudBootstrapComplete &&
      now - lastFirebaseAuthReportMs >= 10000UL) {
    lastFirebaseAuthReportMs = now;
    printFirebaseAuthStatus(false);
  }
  if (networkAvailable && firebaseStarted && !cloudBootstrapComplete &&
      ensureFirebaseReady()) {
    firebaseReady = true;
    fetchTankId();
    syncConfigFromFirebase();
    syncFeederSchedules();
    cloudBootstrapComplete = true;
    Serial.println("[FIREBASE] Connected; cloud control is active.");
    showLCDTransient("Firebase ready", "Cloud controls on", 2500);
    now = millis();
  }
  if (lcdCloudBootPending) {
    if (cloudBootstrapComplete) {
      lcdCloudBootPending = false;
      showLCDBootProgress("CrayCare ready", 80);
    } else if (firebaseAuthAttemptFailed) {
      lcdCloudBootPending = false;
      showLCDTransient("Firebase error", "See Serial Monitor", 4000);
    } else if (now - lcdCloudBootStartedMs >= 30000UL) {
      lcdCloudBootPending = false;
      showLCDTransient("Firebase pending", "Check Serial log", 4000);
    } else if (now - lcdCloudBootLastDrawMs >= 400UL) {
      lcdCloudBootLastDrawMs = now;
      // Moving bar means waiting, not a fabricated authentication percentage.
      showLCDBootProgress("Starting cloud", (now / 100UL) % 80UL + 1);
    }
  }

  // ─── Assignment (cached credentials) ───
  // Held assignment: slow switch-detector. Missing: aggressive search until
  // resolved. Transport failures keep the old cache (fetch only overwrites
  // on success, 404, or a definitive read).
  {
    const bool haveAssignment = currentTankId.length() > 0;
    const unsigned long assignInterval =
        haveAssignment ? ASSIGNMENT_RECHECK_MS : ASSIGNMENT_SEARCH_MS;
    if (now - lastAssignmentCheckMs >= assignInterval) {
      String prevTank = currentTankId;
      fetchTankId();
      lastAssignmentCheckMs = millis();
      now = lastAssignmentCheckMs;
      // A fresh switch/unassign forces an immediate config re-sync.
      if (currentTankId != prevTank) lastConfigSyncTime = 0;
    }
  }

  // ─── Sensors + live Latest (first: the realtime path never queues) ───

  if (!sensorTaskRunning && now - lastPollTime >= SENSOR_POLL_MS) {
    readAllSensors();
    lastPollTime = millis();
    now = lastPollTime;

    if (sensorOutputEnabled) printSensorReading();
  }

  // Continuous raw-voltage stream for calibration stability checks
  // (`raw on` / `raw off`). Reuses cached values; zero extra ADC load.
  if (rawStreamEnabled && now - lastRawStreamMs >= 1000UL) {
    lastRawStreamMs = now;
    printRawReading();
  }

  if (now - lastFirebaseSendTime >= FIREBASE_SEND_INTERVAL_MS) {
    // Firestore is synchronous, so maintain at least a 5-second interval
    // between attempts. A slow request coalesces missed intervals; never
    // queue catch-up writes. Sensor and LCD tasks continue during the request.
    // Sensor writes go to Firestore; Cloud Functions add recorded_at server timestamps.
    // Whether this succeeds or fails, wait for the next normal slot. Immediate
    // retries amplify weak-link TLS failures and can exhaust the SSL layer.
    sendLatestToFirestore();
    lastFirebaseSendTime = millis();
    now = lastFirebaseSendTime;
  }

  // Outage probe: the ONLY network call allowed in outage mode. A single
  // attempt (no retry); success clears the outage via reportCloudResult and
  // normal ops resume. Everything else stays fail-fast until then.
  if (cloudOutage && now - lastOutageProbeMs >= OUTAGE_PROBE_MS) {
    lastOutageProbeMs = now;
    bool probeOk = Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "",
                                                  "hardware_system/currentOwner");
    reportCloudResult(probeOk);
    now = millis();
  }

  // ─── Feeder ───
  // Observe assignment changes before consuming commands or running a plan.
  if (now - lastConfigSyncTime >= CONFIG_SYNC_INTERVAL_MS) {
    syncConfigFromFirebase();
    lastConfigSyncTime = millis();
    now = lastConfigSyncTime;
  }
  // Cloud commands/status/schedule refresh need network. Already-synced
  // schedules continue to execute locally below while offline.
  if (networkAvailable && now - lastFeederCmdCheckMs >= FEEDER_CMD_INTERVAL_MS) {
    processFeederCommands();
    lastFeederCmdCheckMs = millis();
    now = lastFeederCmdCheckMs;
    if (feederRunState != FEEDER_IDLE) return;
  }

  if (networkAvailable && now - lastFeederStatusMs >= FEEDER_STATUS_INTERVAL_MS) {
    sendFeederStatus();
    lastFeederStatusMs = millis();
    now = lastFeederStatusMs;
  }

  if (networkAvailable && now - lastFeederScheduleSyncMs >= FEEDER_SCHEDULE_SYNC_MS) {
    syncFeederSchedules();
    lastFeederScheduleSyncMs = millis();
    now = lastFeederScheduleSyncMs;
  }

  if (now - lastFeederScheduleCheckMs >= FEEDER_SCHEDULE_CHECK_MS) {
    lastFeederScheduleCheckMs = now;
    checkScheduledFeed();
    if (feederRunState != FEEDER_IDLE) return;
  }

  // ─── Feeder state machine tick ───
  processFeederTick();

  // ─── Blower manual-run safety timeout ───
  blowerSafetyTick();

  // ─── LCD status screens (non-blocking) ───
  if (!lcdTaskRunning) updateLCD();

  // ─── Actuators (pump + aerators) ───
  if (now - lastActuatorSyncMs >= ACTUATOR_SYNC_INTERVAL_MS) {
    syncActuatorsFromFirestore();
    lastActuatorSyncMs = millis();
    now = lastActuatorSyncMs;
  }

  if (now - lastHistorySendTime >= HISTORY_SEND_INTERVAL_MS) {
    sendHistoryToFirestore();
    lastHistorySendTime = millis();
    now = lastHistorySendTime;
  }

  // ─── Offline buffer flush (store-and-forward) ───
  // Runs whenever Firebase is reachable; 1 entry/sec max so the live
  // 5-sec + 10-min writes are never starved. Oldest entry goes first.
  if (now - lastFlushTime >= FLUSH_INTERVAL_MS) {
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
    lastFlushTime = millis();
    now = lastFlushTime;
  }

  // Drop a TLS session wedged by repeated transport failures (BearSSL
  // mRunUntil/mConnectSSL timeouts, climbing fds). All payloads are consumed
  // inline by their callers, so clearing here is safe; the next cloud call
  // does a clean handshake.
  if (cloudSessionResetPending) {
    cloudSessionResetPending = false;
    fbdo.clear();
    Serial.println("[NET] TLS session reset after repeated transport failures");
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
  ledcAttachPin(GATE_SERVO_PIN, SERVO_LEDC_CHANNEL);
  setGateAngle(0);
  feederIsRunning = false;
  feederRunState = FEEDER_IDLE;
  feederCurrentCycle = 0;
  feederInitialized = true;
  recoverFeederLogs();

  // Park the gate closed. Do NOT actuate at boot: every swing drops feed,
  // and resets also happen on Wi-Fi drops / power flickers. Use GATE_TEST
  // for a physical hardware self-test instead.
  Serial.printf("[GATE] SG90 gate parked closed at 0 degrees on GPIO %d (1 g-only model)\n",
                GATE_SERVO_PIN);
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
      startFeed("manual", e.grams, e.docId, e.issuedAtMs, e.expiresAtMs,
                false);
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
  const String heartbeatAt = firestoreTimestampString(now);
  if (heartbeatAt.isEmpty()) {
    Serial.println("[FEEDER STATUS] Skipped Firestore write: system clock is not synchronized");
    return;
  }

  FirebaseJson json;
  // Match FeederService's canonical status fields and keep the heartbeat fresh.
  json.set("fields/status/stringValue", feederStatus);
  json.set("fields/command_id/stringValue", feederCommandId);
  json.set("fields/status_reason/stringValue", feederStatusReason);
  json.set("fields/dispenseCount/integerValue", String(feederDispenseCount));
  json.set("fields/lastSeen/timestampValue", heartbeatAt);
  const String lastDispensedAt = feederLastCompletedEpoch > 0
      ? firestoreTimestampString((time_t)feederLastCompletedEpoch)
      : "";
  if (!lastDispensedAt.isEmpty()) {
    json.set("fields/last_dispensed_at/timestampValue", lastDispensedAt);
  } else {
    json.set("fields/last_dispensed_at/nullValue", "NULL_VALUE");
  }
  if (feedLevelSensorOK) {
    json.set("fields/feed_level/doubleValue", feedLevelPercent);
  }
  String statusDoc = "tanks/" + currentTankId + "/feeder/status";
  if (!Firebase.Firestore.patchDocument(&fbdo, FIREBASE_PROJECT_ID, "",
        statusDoc.c_str(), json.raw(),
        "status,command_id,status_reason,dispenseCount,lastSeen,last_dispensed_at,feed_level")) {
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
  MutexGuard scheduleLock(feederScheduleMutex);
  prefs.begin("feedsched", true);
  const String cachedTank = prefs.getString("tank", "");
  const long long cachedAssignment = prefs.getLong64("assignment", 0);
  const int cachedCount = max(0, prefs.getInt("count", 0));
  // On an offline cold boot, restore the assignment identity stored alongside
  // the last complete cloud schedule snapshot so that local execution can
  // identify which tank the cached schedule belongs to. A later successful
  // Firebase assignment read replaces or clears this identity as needed.
  if (currentTankId.isEmpty() && !cachedTank.isEmpty() && cachedCount > 0) {
    currentTankId = cachedTank;
    currentAssignmentAtMs = cachedAssignment;
    Serial.printf("[FEEDER] Offline boot: restored cached tank %s for local schedules\n",
                  currentTankId.c_str());
  }
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

  // One owner-level policy applies to manual Feed Now and every schedule. Do
  // not trust an old opt-in indefinitely while offline; it expires after three
  // normal schedule-sync intervals (30 seconds).
  String policyPath = "tanks/" + currentTankId + "/feeder/feeder_policy";
  bool policyLoaded = firestoreGetDoc(policyPath.c_str());
  if (!policyLoaded && fbdo.httpCode() == 404) {
    // Backward compatibility until the old Firestore document is retired.
    policyPath = "tanks/" + currentTankId + "/feeder/schedule_policy";
    policyLoaded = firestoreGetDoc(policyPath.c_str());
  }
  if (policyLoaded) {
    FirebaseJson policyResponse;
    FirebaseJsonData policyValue;
    policyResponse.setJsonData(fbdo.payload());
    bool enabled = policyResponse.get(
        policyValue, "fields/allow_water_quality_override/booleanValue") &&
        policyValue.boolValue;
    if (enabled != allowWaterQualityFeeding) {
      Serial.printf("[FEEDER] Shared water-quality range override %s\n",
                    enabled ? "enabled" : "disabled");
    }
    allowWaterQualityFeeding = enabled;
    // Retired policy is deliberately ignored. The shared opt-in covers all
    // four water-quality sensor ranges for manual and scheduled feedings.
    lastFeederPolicySyncMs = millis();
  } else if (fbdo.httpCode() == 404) {
    allowWaterQualityFeeding = false;
    lastFeederPolicySyncMs = millis();
  } else {
    Serial.printf("[FEEDER] Shared feeder policy sync failed; retaining the last value temporarily, http=%d\n",
                  fbdo.httpCode());
  }

  String schedCol = "tanks/" + currentTankId + "/feeder_schedules";
  std::vector<FeedSchedule> synced;
  String pageToken;
  int pages = 0;
  do {
  if (!Firebase.Firestore.listDocuments(&fbdo, FIREBASE_PROJECT_ID, "",
        schedCol.c_str(), FEEDER_SCHEDULE_PAGE_SIZE, pageToken.c_str(), "", "", false)) {
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
    bool hasCanonicalTime = false;

    // Canonical Firestore value is one zero-padded 24-hour "HH:mm" string.
    const bool hasScheduledTimeField = response.get(d, base + "scheduled_time");
    if (hasScheduledTimeField) {
      if (!response.get(d, base + "scheduled_time/stringValue")) {
        Serial.printf("[FEEDER] Skipping schedule %s with non-string scheduled_time\n",
                      docId.c_str());
        continue;
      }
      const String scheduledTime = d.stringValue;
      if (scheduledTime.length() == 5 && scheduledTime.charAt(2) == ':' &&
          isDigit(scheduledTime.charAt(0)) && isDigit(scheduledTime.charAt(1)) &&
          isDigit(scheduledTime.charAt(3)) && isDigit(scheduledTime.charAt(4))) {
        const int hour24 = scheduledTime.substring(0, 2).toInt();
        const int minuteOfHour = scheduledTime.substring(3, 5).toInt();
        if (hour24 >= 0 && hour24 <= 23 && minuteOfHour >= 0 && minuteOfHour <= 59) {
          timeValue = hour24 * 60 + minuteOfHour;
          hasCanonicalTime = true;
        }
      }
      if (!hasCanonicalTime) {
        Serial.printf("[FEEDER] Skipping schedule %s with invalid scheduled_time\n",
                      docId.c_str());
        continue;
      }
    }

    // Read legacy fields during rollout so pre-migration schedules still run.
    if (!hasScheduledTimeField) {
      if (response.get(d, base + "timeValue/integerValue")) {
        timeValue = d.stringValue.toInt();
      }
      if (response.get(d, base + "time/stringValue")) timeStr = d.stringValue;
      if (response.get(d, base + "ampm/stringValue")) ampm = d.stringValue;
      if (response.get(d, base + "feed_time/stringValue") && timeStr == "6:00") {
        timeStr = d.stringValue;
      }
    }

    int hour = 6;
    int minute = 0;

    if (timeValue >= 0 && timeValue < 1440) {
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
    esp_task_wdt_reset();  // multi-page syncs must not trip the watchdog
    if (++pages >= 5) break;  // hard cap: 100 schedules is plenty
  } while (pageToken.length() > 0);
  {
    MutexGuard scheduleLock(feederScheduleMutex);
    bool unchanged = synced.size() == feederSchedules.size();
    for (size_t i = 0; unchanged && i < synced.size(); ++i) {
      const FeedSchedule& a = synced[i];
      const FeedSchedule& b = feederSchedules[i];
      unchanged = a.key == b.key && a.hour24 == b.hour24 && a.minute == b.minute &&
          a.enabled == b.enabled && a.grams == b.grams && a.days == b.days &&
          a.effectiveEpoch == b.effectiveEpoch;
    }
    if (unchanged) return; // Avoid rewriting NVS on every poll.
    feederSchedules.swap(synced);
    feederScheduleCount = feederSchedules.size();
  }

  saveCachedFeederSchedules();
  Serial.printf("[FEEDER] Synced %d schedules from Firestore\n", feederScheduleCount);
}

// Override policy for the onsite physical button: after a 2-tap confirm
// inside the warning window, these blocks may be bypassed (force path).
// Never bypassable: missing tank/clock/storage, persist/ack failures,
// bad grams, stale/duplicate commands, busy feeder.
bool feedBlockBypassable(const String& reason) {
  if (reason.startsWith("automatic feeding is due at")) return true;
  if (reason == "tank sensor settings have not finished syncing") return true;
  if (reason == "required water-quality sensor unavailable") return true;
  if (reason == "temperature outside range") return true;
  if (reason == "dissolved oxygen too low") return true;
  if (reason == "dissolved oxygen too high") return true;
  if (reason == "pH outside range") return true;
  if (reason == "turbidity below range") return true;
  if (reason == "turbidity too high") return true;
  if (reason == "feed-level sensor unavailable") return true;
  return false;
}

bool canFeedSafely(String &reason, bool allowHighTurbidityRange = false,
                   bool allowWaterQualityRanges = false) {
  if (!feederConfigReady) {
    reason = "tank sensor settings have not finished syncing";
    return false;
  }
  const bool turbidityAirAllowed =
      allowWaterQualityRanges && !turbiditySensorOK &&
      turbidityVoltage < turbidityVAirMax;
  if (!tempSensorOK || !doSensorOK || !phSensorOK ||
      (!turbiditySensorOK && !turbidityAirAllowed)) {
    reason = "required water-quality sensor unavailable";
    return false;
  }
  if (!allowWaterQualityRanges &&
      (smoothedTemp < tempCriticalLow || smoothedTemp > tempCriticalHigh)) reason = "temperature outside range";
  else if (!allowWaterQualityRanges && dissolvedOxygen < doCriticalLow) reason = "dissolved oxygen too low";
  else if (!allowWaterQualityRanges && dissolvedOxygen > doCriticalHigh) reason = "dissolved oxygen too high";
  else if (!allowWaterQualityRanges &&
           (phLevel < phCriticalLow || phLevel > phCriticalHigh)) reason = "pH outside range";
  else if (!allowWaterQualityRanges && smoothedTurbidityNTU < turbNtuMin) reason = "turbidity below range";
  else if (!allowWaterQualityRanges && !allowHighTurbidityRange &&
           smoothedTurbidityNTU > turbNtuMax) reason = "turbidity too high";
  else if (!feedLevelSensorOK) reason = "feed-level sensor unavailable";
  else if (feedLevelPercent <= feedLevelCriticalThreshold) reason = "critical feed level";
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
        startFeed("scheduled", s.grams, "", 0, 0, false);
        return;
      }
    }
  }
}

// ─── Start Feed — kicks off non-blocking state machine ───
void startFeed(String source, float grams, String commandId, long long issuedAtMs, long long expiresAtMs, bool forceOverride) {
  const bool sharedPolicyFresh = lastFeederPolicySyncMs > 0 &&
      millis() - lastFeederPolicySyncMs <= FEEDER_SCHEDULE_SYNC_MS * 3UL;
  const bool allowWaterQualityOverride =
      (source == "manual" || source == "scheduled") &&
      allowWaterQualityFeeding && sharedPolicyFresh;
  feederWaterQualityOverrideUsed = false;
  if (!forceOverride) { feederForced = false; feederForceReason = ""; }
  if (feederRunState != FEEDER_IDLE) {
    feederStatusReason = "Feeder busy";
    Serial.println("[FEEDER] Already running, skipping");
    return;
  }
  feederStatusReason = "";
  if (currentTankId.isEmpty()) {
    feederStatusReason = "Tank not assigned";
    Serial.println("[FEEDER] BLOCKED: tank assignment is not available");
    return;
  }
  time_t startedAt;
  time(&startedAt);
  if (startedAt < 1700000000 || !littlefsMounted) {
    feederStatusReason = startedAt < 1700000000 ? "Clock not synced" : "Storage unavailable";
    Serial.printf("[FEEDER] BLOCKED: %s\n", feederStatusReason.c_str());
    return;
  }
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
  {
    MutexGuard lcdLock(lcdMutex);
    feederFeedSource = source;
  }
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
                "failed", grams, -1, -1);
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
  readFeedLevelSensorSafely();
  sendFeederStatus();
  String blockedReason;
  time_t checkedAt;
  time(&checkedAt);
  if (!commandId.isEmpty() && feederLastCompletedEpoch > 0 &&
      issuedAtMs <= (long long)feederLastCompletedEpoch * 1000 + 999) {
    blockedReason = "Another feeding completed after this request was issued; submit a new request";
  }
  if (!commandId.isEmpty() && (issuedAtMs <= 0 || issuedAtMs > (long long)checkedAt * 1000 + 5000 ||
                              (long long)checkedAt * 1000 - issuedAtMs > 60000 ||
                              (expiresAtMs > 0 && (long long)checkedAt * 1000 >= expiresAtMs))) {
    blockedReason = "Feed Now request expired or has an invalid timestamp";
  }
  if (!isfinite(grams) || grams < 1 || grams > 200 || roundf(grams) != grams) {
    blockedReason = "unsupported amount; use 1-200 whole grams";
  }
  String nearbySchedule;
  if (blockedReason.length() == 0 && (source == "manual" || source == "onsite") &&
      manualFeedConflictsWithSchedule(checkedAt, nearbySchedule)) {
    blockedReason = "automatic feeding is due at " + nearbySchedule;
  }
  if (blockedReason.isEmpty()) {
    String sensorRangeReason;
    if (!canFeedSafely(sensorRangeReason)) {
      const bool waterQualityRangeOverride =
          (source == "manual" || source == "scheduled") &&
          allowWaterQualityOverride &&
          ((sensorRangeReason == "required water-quality sensor unavailable" &&
            !turbiditySensorOK && turbidityVoltage < turbidityVAirMax) ||
           sensorRangeReason == "temperature outside range" ||
           sensorRangeReason == "dissolved oxygen too low" ||
           sensorRangeReason == "dissolved oxygen too high" ||
           sensorRangeReason == "pH outside range" ||
           sensorRangeReason == "turbidity below range" ||
           sensorRangeReason == "turbidity too high");
      if (waterQualityRangeOverride) {
        String remainingSafetyReason;
        if (canFeedSafely(remainingSafetyReason, false, true)) {
          feederWaterQualityOverrideUsed = true;
          Serial.printf("[FEEDER] Water-quality range override accepted (source=%s); sensors and feed-level checks passed\n",
                        source.c_str());
        } else {
          blockedReason = remainingSafetyReason;
        }
      } else {
        blockedReason = sensorRangeReason;
      }
    }
  }
  if (blockedReason.length() > 0) {
    if (forceOverride && feedBlockBypassable(blockedReason)) {
      feederForced = true;
      Serial.printf("[FEEDER] Override confirmed — bypassing: %s\n", blockedReason.c_str());
    } else {
      feederStatusReason = blockedReason;
      Serial.printf("[FEEDER] BLOCKED: %s\n", blockedReason.c_str());
      time_t blockedAt;
      time(&blockedAt);
      feederLastFeedEpoch = (unsigned long)blockedAt;
      const bool insufficient = blockedReason == "critical feed level";
      feederStatus = insufficient ? "skipped_insufficient" : "blocked";
      pushFeederLog(
        insufficient ? "Skipped - Critical feed level" : "Feed blocked: " + blockedReason,
        source == "manual" ? "manual" : "auto",
        insufficient ? "skipped_insufficient" : "blocked",
        feederRequestedGrams,
        feedLevelPercent, feedLevelPercent);
      if (source == "scheduled") {
        // Consume the occurrence after its terminal safety decision so one
        // blocked schedule is logged once rather than retried each loop pass.
        feederLastScheduledMinute = (unsigned long)blockedAt / 60;
        saveFeederState();
      }
      sendFeederStatus();
      feederLastScheduleKey = "";
      // Bypassable onsite block: open the 10 s warning window instead of a
      // silent abort. Taps inside the window confirm; grams stay locked.
      if (source == "onsite" && feedBlockBypassable(blockedReason)) {
        armFeedOverride(feederRequestedGrams, blockedReason);
      }
      return;
    }
  }

  feederFeedLevelBefore = feedLevelPercent;
  // 1 g-only: 5 g from the app = exactly 5 gate swings.
  feederMaxCycles = max(1, min(200, (int)roundf(feederRequestedGrams)));

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
                  feederFeedLevelBefore, feederFeedLevelBefore);
    sendFeederStatus();
    return;
  }

  // Recheck after the blocking status upload, immediately before activation.
  if ((source == "manual" || source == "onsite") &&
      manualFeedConflictsWithSchedule(checkedAt, nearbySchedule)) {
    if (forceOverride) {
      Serial.printf("[FEEDER] Override confirmed — bypassing: %s\n",
                    ("automatic feeding is due at " + nearbySchedule).c_str());
    } else {
      feederStatus = "blocked";
      feederStatusReason = "automatic feeding is due at " + nearbySchedule;
    pushFeederLog(feederStatusReason, "manual", "blocked", grams,
                  feederFeedLevelBefore, feederFeedLevelBefore);
      sendFeederStatus();
      return;
    }
  }
  feederLastFeedEpoch = (unsigned long)checkedAt;
  {
    MutexGuard lcdLock(lcdMutex);
    feederFeedSource = source;
  }
  feederIsRunning = true;
  feederStatus = "dispensing";
  feederCurrentCycle = 0;
  feederRunState = FEEDER_PRE_BLOW;
  feederStartMs = millis();
  feederStepMs = feederStartMs;

  // Blower warms up first on every feed (manual, cloud, scheduled, onsite).
  setBlower(true, true);
  // No blocking cloud call between the expiry check and the motor tick.
  Serial.printf("[FEEDER] Start feed (source=%s, %.1fg = %d actuations)\n",
                source.c_str(), feederRequestedGrams, feederMaxCycles);
}

// ─── Non-blocking feeder tick — call every loop() ───
void processFeederTick() {
  if (feederRunState == FEEDER_IDLE) return;

  unsigned long now = millis();

  switch (feederRunState) {

    case FEEDER_PRE_BLOW:
      // Blower was switched auto-ON at startFeed; wait out the warm-up lead.
      if (now - feederStepMs >= (unsigned long)BLOWER_PRE_SEC * 1000UL) {
        feederRunState = FEEDER_FORWARD;
        feederStepMs = now;
      }
      break;

    case FEEDER_FORWARD:
      setGateAngle(gateOpenAngle);
      feederStepMs = now;
      feederRunState = FEEDER_PAUSE_F;
      Serial.printf("[FEEDER] Gate open %d/%d (1 g each)\n",
        feederCurrentCycle + 1, feederMaxCycles);
      break;

    case FEEDER_PAUSE_F:
      if (now - feederStepMs >= (unsigned long)gateHoldMs) {
        setGateAngle(0);
        feederStepMs = now;
        feederCurrentCycle++;
        feederRunState = FEEDER_CLOSE_DWELL;
      }
      break;

    case FEEDER_CLOSE_DWELL:
      // Without this dwell the next FORWARD fires within one fast loop pass
      // and the servo (~150 ms transit) never shuts: N grams merge into a
      // single long open. GATECAL has the same 300 ms gap per actuation.
      if (now - feederStepMs >= GATE_CLOSE_DWELL_MS) {
        if (feederCurrentCycle >= feederMaxCycles) {
          // Begin the blower tail as soon as the final gate has closed, not
          // later when the completion log/status work finishes.
          blowerAutoOff();
          feederRunState = FEEDER_DONE;
        } else {
          // Next 1 g actuation
          feederRunState = FEEDER_FORWARD;
        }
      }
      break;

    case FEEDER_DONE: {
      // Keep isRunning=true for at least 1s so Flutter reliably catches the transition
      if (now - feederStartMs < 1000) break;

      setGateAngle(0);
      // Update feed count and persist it so a reboot doesn't reset the total
      // the app displays as "feeds completed".
      feederDispenseCount++;
      time_t completedAt;
      time(&completedAt);
      feederLastCompletedEpoch = completedAt;
      feederDoneShowMs = millis() + 5000;  // LCD feeding-complete banner
      saveFeederState();

      feederIsRunning = false;
      feederStatus = "completed";
      feederRunState = FEEDER_IDLE;

      // Confirm the level change after dispensing. This is a confirmation aid,
      // not a direct measurement of the exact grams dispensed.
      readFeedLevelSensorSafely();
      const float levelAfter = feedLevelSensorOK ? feedLevelPercent : -1.0f;
      // Make the shared water-quality override visible in the audit log.
      String completionAction = feederFeedSource == "scheduled"
          ? String("Dispensed feed (Scheduled)") +
                (feederWaterQualityOverrideUsed ? " - water-quality range override" : "")
          : feederFeedSource == "onsite"
              ? (feederForced ? "Dispensed feed (Onsite Button, override: " + feederForceReason + ")"
                              : "Dispensed feed (Onsite Button)")
              : String("Dispensed feed (Manual)") +
                    (feederWaterQualityOverrideUsed ? " - water-quality range override" : "");
      // Push final status + log
      pushFeederLog(
        completionAction,
        feederFeedSource == "scheduled" ? "auto" : "manual",
        feederForced ? "forced" : "completed",
        feederRequestedGrams,
        feederFeedLevelBefore,
        levelAfter
      );
      sendFeederStatus();
      // The log trigger updates the date-scoped outcome, including backfills.

      {
        MutexGuard lcdLock(lcdMutex);
        feederFeedSource = "";
      }
      feederLastScheduleKey = "";
      feederForced = false;
      feederForceReason = "";
      feederWaterQualityOverrideUsed = false;
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
                   float requestedGrams, float levelBefore, float levelAfter) {
  if (!littlefsMounted || feederEventTank.isEmpty()) return;

  time_t now;
  time(&now);
  const String loggedAt = firestoreTimestampString(now);
  if (loggedAt.isEmpty()) {
    Serial.println("[FEEDER LOG] Skipped Firestore write: system clock is not synchronized");
    return;
  }

  FirebaseJson json;
  json.set("fields/action/stringValue",    action);
  json.set("fields/type/stringValue",      type);
  if (!feederCommandId.isEmpty()) json.set("fields/command_id/stringValue", feederCommandId);
  json.set("fields/logged_at/timestampValue", loggedAt);
  if (feederOccurrenceEpoch > 0) {
    const String occurrenceAt =
        firestoreTimestampString((time_t)feederOccurrenceEpoch);
    if (!occurrenceAt.isEmpty()) {
      json.set("fields/occurrence_at/timestampValue", occurrenceAt);
    }
  }
  if (feederLastScheduleKey.length() > 0) {
    json.set("fields/schedule_key/stringValue", feederLastScheduleKey);
    json.set("fields/schedule_time/stringValue", feederScheduleTime);
  }
  json.set("fields/trigger_source/stringValue",
           feederFeedSource == "onsite" ? "physical_button" :
           feederFeedSource == "scheduled" ? "schedule" : "manual_request");
  if (status.length() > 0) json.set("fields/status/stringValue", status);
  if (isfinite(requestedGrams) && requestedGrams >= 0.0f) {
    json.set("fields/requested_grams/doubleValue", String(requestedGrams, 1));
    if (status == "completed" || status == "forced") {
      // Servo-cycle estimate, not a directly weighed amount.
      json.set("fields/estimated_dispensed_grams/doubleValue",
               String(requestedGrams, 1));
      json.set("fields/amount_basis/stringValue", "servo_cycle_estimate");
    }
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
  const bool hadAssignment = currentTankId.length() > 0 && currentOwnerUid.length() > 0;
  const bool hasAssignment = tankId.length() > 0 && ownerUid.length() > 0;
  if (hadAssignment || hasAssignment) {
    if (!hasAssignment) {
      Serial.println("[ASSIGNMENT] Hardware is now unassigned; sensor data will remain staged until an owner is assigned.");
    } else if (hadAssignment && (tankId != currentTankId || ownerUid != currentOwnerUid)) {
      Serial.printf("[ASSIGNMENT] Hardware owner changed (%s -> %s); refreshing tank configuration and clearing old cached schedules.\n",
                    currentOwnerUid.c_str(), ownerUid.c_str());
    } else {
      Serial.printf("[ASSIGNMENT] Assignment metadata refreshed for tank %s.\n", tankId.c_str());
    }
  }
  currentTankId = tankId;
  currentOwnerUid = ownerUid;
  currentAssignmentAtMs = assignedAtMs;
  resetWindowAggregates(); // A 10-minute window must never span two assignments.
  feederConfigReady = false;
  if (!feederInitialized) return;
  // Loop defers cloud work until the servo is parked. Revoke the cached plan;
  // never carry a previous owner's schedules/counters into the next account.
  {
    MutexGuard scheduleLock(feederScheduleMutex);
    feederSchedules.clear();
    feederScheduleCount = 0;
  }
  allowWaterQualityFeeding = false;
  lastFeederPolicySyncMs = 0;
  feederLastScheduleKey = "";
  feederScheduleTime = "";
  feederDispenseCount = 0;
  feederLastCompletedEpoch = 0;
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
//    last_changed : Firestore Timestamp (or null before the first device report)
//  Logs: tanks/{tankId}/actuator_logs  (ESP creates a doc on every state change)
//  Note: relays are ACTIVE-LOW — digitalWrite(LOW) turns the relay ON.
// ============================================================

// ─── Initialize life-support relays ON as the offline-safe default ───
void initActuators() {
  for (int i = 0; i < 3; i++) {
    pinMode(actuators[i].pin, OUTPUT);
    digitalWrite(actuators[i].pin, LOW);   // active-LOW: LOW = relay ON
    actuators[i].relayOn = true;
    // The cloud may override this safe default as soon as its modes are read.
    actuators[i].cloudReported = false;
    actuators[i].cloudReportedState = "";
    actuators[i].lastChangeMs = 0;
  }
  Serial.println("[ACT] Offline-safe startup: pump=GPIO26, aerator1=GPIO27, aerator2=GPIO14 (all ON until cloud modes load)");
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

// ─── Blower (GPIO16, ACTIVE-LOW relay) ───
// Serial + physical button for now; future app ID "blower" is reserved.
// Auto logic only ever switches OFF what it switched ON (blowerAutoHeld);
// a manually-started blower is never touched by the feed cycle.
void initBlower() {
  pinMode(BLOWER_PIN, OUTPUT);
  digitalWrite(BLOWER_PIN, HIGH);   // HIGH = relay OFF
  blowerOn = false;
  blowerAutoHeld = false;
  Serial.println("[BLOWER] GPIO16 initialized OFF");
}

void setBlower(bool on, bool autoHeld) {
  if (blowerOn == on) {
    if (on && autoHeld) {
      blowerAutoHeld = true;
      blowerPostRunPending = false;  // a new feed cancels the prior tail timer
    }
    return;
  }
  blowerOn = on;
  digitalWrite(BLOWER_PIN, on ? LOW : HIGH);
  if (on) {
    blowerOnSinceMs = millis();
    blowerPostRunPending = false;
    if (autoHeld) blowerAutoHeld = true;
  } else {
    blowerPostRunPending = false;
    blowerAutoHeld = false;
  }
  Serial.printf("[BLOWER] -> %s%s\n", on ? "ON" : "OFF", autoHeld ? " (auto)" : " (manual)");
}

void blowerAutoOff() {
  if (!blowerOn || !blowerAutoHeld) return;
  if (BLOWER_POST_SEC == 0) {
    setBlower(false, true);
    return;
  }
  blowerPostRunStartedMs = millis();
  blowerPostRunPending = true;
  Serial.printf("[BLOWER] Final gate closed; staying ON for %u s\n",
                (unsigned)BLOWER_POST_SEC);
}

// Safety timeout for manual runs — call every loop().
void blowerSafetyTick() {
  const unsigned long now = millis();
  if (blowerOn && blowerAutoHeld && blowerPostRunPending &&
      now - blowerPostRunStartedMs >= (unsigned long)BLOWER_POST_SEC * 1000UL) {
    blowerPostRunPending = false;
    setBlower(false, true);
    Serial.println("[BLOWER] Post-feed 10 s run complete — OFF");
    return;
  }
  if (blowerOn && !blowerAutoHeld && now - blowerOnSinceMs >= BLOWER_MAX_ON_MS) {
    setBlower(false, false);
    Serial.println("[BLOWER] Manual safety timeout — OFF");
  }
}

// Blower manual button (GPIO2 -> GND, INPUT_PULLUP). Toggle ON/OFF.
// Ignored while a feed auto-holds the blower; the 15-minute manual
// timeout from blowerSafetyTick() still applies. Polled (no ISR needed).
#define BLOWER_BUTTON_PIN 2
#define BLOWER_BUTTON_DEBOUNCE_MS 50
#define BLOWER_BUTTON_BOOT_LOCK_MS 3000
bool blowerBtnRaw = HIGH, blowerBtnStable = HIGH;
unsigned long blowerBtnChangeMs = 0;

void initBlowerButton() {
  pinMode(BLOWER_BUTTON_PIN, INPUT_PULLUP);
  Serial.println("[BUTTON] Blower toggle ready on GPIO2 (to GND, INPUT_PULLUP)");
}

void pollBlowerButton() {
  unsigned long now = millis();
  if (now < BLOWER_BUTTON_BOOT_LOCK_MS) return;
  bool raw = digitalRead(BLOWER_BUTTON_PIN);
  if (raw != blowerBtnRaw) { blowerBtnRaw = raw; blowerBtnChangeMs = now; return; }
  if (now - blowerBtnChangeMs < BLOWER_BUTTON_DEBOUNCE_MS || raw == blowerBtnStable) return;
  blowerBtnStable = raw;
  if (raw != LOW) return;
  if (blowerOn && blowerAutoHeld && feederRunState != FEEDER_IDLE) {
    Serial.println("[BUTTON] Feed owns blower now — ignored");
    return;
  }
  setBlower(!blowerOn, false);
}

// ─── 16x2 status LCD (SDA 21 / SCL 22, addr 0x27) ───
// Silent-disable on no-ACK so a missing LCD never affects the firmware.
#define LCD_ADDR 0x27
#define LCD_COLS 16
#define LCD_ROWS 2
#define LCD_ROTATE_MS 3000
LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS);
bool lcdReady = false;
unsigned long lastLcdMs = 0;
unsigned long lastLcdRenderMs = 0;
int lcdScreen = 0;

static void lcdPrint16(int row, const String& text) {
  char buf[17];
  snprintf(buf, sizeof(buf), "%-16.16s", text.c_str());
  lcd.setCursor(0, row);
  lcd.print(buf);
}

void initLCD() {
  Wire.begin(21, 22);
  Wire.beginTransmission(LCD_ADDR);
  if (Wire.endTransmission() != 0) {
    Serial.println("[LCD] No ACK at 0x27 — LCD disabled (check wiring/address)");
    lcdReady = false;
    return;
  }
  lcd.init();
  lcd.backlight();
  lcdReady = true;
  lcdPrint16(0, "CrayCare");
  lcdPrint16(1, "starting...");
  Serial.println("[LCD] 16x2 ready at 0x27");
}

void showLCDBoot(const String& line0, const String& line1, unsigned long holdMs) {
  if (!lcdReady) return;
  MutexGuard lcdLock(lcdMutex);
  lcdPrint16(0, line0);
  lcdPrint16(1, line1);
  if (holdMs > 0) delay(holdMs);
}

void showLCDBootProgress(const String& label, uint8_t filledPixels) {
  if (!lcdReady) return;
  MutexGuard lcdLock(lcdMutex);
  if (filledPixels > 80) filledPixels = 80;
  const uint8_t fullCells = filledPixels / 5;
  const uint8_t partialPixels = filledPixels % 5;
  uint8_t fullGlyph[8] = {0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F, 0x1F};
  lcd.createChar(1, fullGlyph);
  if (partialPixels > 0) {
    uint8_t partialGlyph[8];
    const uint8_t row = (uint8_t)(0x1F << (5 - partialPixels));
    for (uint8_t i = 0; i < 8; ++i) partialGlyph[i] = row;
    lcd.createChar(0, partialGlyph);
  }
  lcdPrint16(0, label);
  lcdPrint16(1, "                ");
  lcd.setCursor(0, 1);
  for (uint8_t i = 0; i < fullCells; ++i) lcd.write((uint8_t)1);
  if (partialPixels > 0 && fullCells < 16) lcd.write((uint8_t)0);
}

void showLCDTransient(const String& line0, const String& line1, unsigned long holdMs) {
  if (!lcdReady) return;
  MutexGuard lcdLock(lcdMutex);
  lcdTransientLine0 = line0;
  lcdTransientLine1 = line1;
  lcdTransientUntilMs = millis() + holdMs;
  lcdPrint16(0, line0);
  lcdPrint16(1, line1);
}

void IRAM_ATTR onsiteButtonISR() {
  if (!onsiteButtonEnabled) return;
  const uint32_t nowUs = micros();
  portENTER_CRITICAL_ISR(&onsiteButtonMux);
  if (onsiteButtonTapCount < ONSITE_BUTTON_MAX_TAPS &&
      (uint32_t)(nowUs - onsiteButtonLastTapUs) >= ONSITE_BUTTON_DEBOUNCE_US) {
    ++onsiteButtonTapCount;
    onsiteButtonLastTapUs = nowUs;
  }
  portEXIT_CRITICAL_ISR(&onsiteButtonMux);
}

void initOnsiteButton() {
  pinMode(ONSITE_BUTTON_PIN, INPUT_PULLUP);
  onsiteButtonLastTapUs = micros();
  attachInterrupt(digitalPinToInterrupt(ONSITE_BUTTON_PIN), onsiteButtonISR, FALLING);
  Serial.printf("[BUTTON] Onsite dispense button ready on GPIO%d (tap count = grams)\n",
                ONSITE_BUTTON_PIN);
}

void armFeedOverride(float grams, const String& reason) {
  overrideGrams = grams;
  {
    MutexGuard lcdLock(lcdMutex);
    overrideWarnReason = reason;
  }
  overrideConfirmTaps = 0;
  overrideDeadlineMs = millis() + OVERRIDE_WINDOW_MS;
  Serial.printf("[FEEDER] BLOCKED (bypassable): %s — tap 2x within 10 s to force-dispense\n",
                reason.c_str());
}

void clearFeedOverride() {
  {
    MutexGuard lcdLock(lcdMutex);
    overrideWarnReason = "";
  }
  overrideGrams = 0;
  overrideConfirmTaps = 0;
  overrideDeadlineMs = 0;
}

// Expiry watchdog for the warning window — call every loop().
void pollFeedOverride() {
  if (calibrationMode) {
    if (overrideWarnReason.length() > 0) clearFeedOverride();
    return;
  }
  if (overrideWarnReason.length() == 0) return;
  if ((long)(millis() - overrideDeadlineMs) >= 0) {
    Serial.println("[FEEDER] Override expired — feed cancelled");
    clearFeedOverride();
  }
}

void processOnsiteButton() {
  if (calibrationMode) {
    portENTER_CRITICAL(&onsiteButtonMux);
    onsiteButtonTapCount = 0;
    portEXIT_CRITICAL(&onsiteButtonMux);
    return;
  }
  if (!onsiteButtonEnabled) return;
  // Confirmation taps inside an override warning window: counted
  // immediately (no settle) and never converted to grams.
  if (overrideWarnReason.length() > 0) {
    if (feederRunState != FEEDER_IDLE) { clearFeedOverride(); return; }
    uint16_t fresh = 0;
    portENTER_CRITICAL(&onsiteButtonMux);
    fresh = onsiteButtonTapCount;
    onsiteButtonTapCount = 0;
    portEXIT_CRITICAL(&onsiteButtonMux);
    if (fresh == 0) return;
    overrideConfirmTaps += fresh;
    Serial.printf("[BUTTON] Override confirm %d/%d\n",
                  overrideConfirmTaps, OVERRIDE_CONFIRM_TAPS);
    if (overrideConfirmTaps >= OVERRIDE_CONFIRM_TAPS) {
      float g = overrideGrams;
      String r = overrideWarnReason;
      clearFeedOverride();
      feederForceReason = r;
      startFeed("onsite", g, "", 0, 0, true);
      if (feederRunState == FEEDER_IDLE) {
        // Forced attempt hit a hard (non-bypassable) block.
        feederForced = false;
        feederForceReason = "";
        const String reason2 = feederStatusReason.length() > 0
            ? feederStatusReason.substring(0, 16) : "See Serial Monitor";
        showLCDTransient("Feed blocked", reason2, 2500);
      }
    }
    return;
  }
  uint16_t tapsToFeed = 0;
  bool tapsIgnoredBusy = false;
  portENTER_CRITICAL(&onsiteButtonMux);
  if (feederRunState != FEEDER_IDLE && onsiteButtonTapCount > 0) {
    onsiteButtonTapCount = 0;
    tapsIgnoredBusy = true;
  } else if (feederRunState == FEEDER_IDLE && onsiteButtonTapCount > 0 &&
             (uint32_t)(micros() - onsiteButtonLastTapUs) >=
                 ONSITE_BUTTON_BATCH_MS * 1000UL) {
    tapsToFeed = onsiteButtonTapCount;
    onsiteButtonTapCount = 0;
  }
  portEXIT_CRITICAL(&onsiteButtonMux);

  if (tapsIgnoredBusy) {
    Serial.println("[BUTTON] Tap ignored: feeder busy");
    return;
  }
  if (tapsToFeed == 0) return;

  Serial.printf("[BUTTON] %u tap(s) -> onsite dispense %u g\n",
                tapsToFeed, tapsToFeed);
  startFeed("onsite", (float)tapsToFeed);
  if (feederRunState == FEEDER_IDLE && overrideWarnReason.length() == 0) {
    const String reason = feederStatusReason.length() > 0
        ? feederStatusReason.substring(0, 16) : "See Serial Monitor";
    showLCDTransient("Feed blocked", reason, 2500);
  }
}

void getNextScheduleLines(String& line0, String& line1) {
  MutexGuard scheduleLock(feederScheduleMutex);
  time_t now;
  time(&now);
  if (now < 1700000000) {
    line0 = "Next feeding";
    line1 = "Clock unavailable";
    return;
  }
  if (feederScheduleCount == 0) {
    line0 = "No feed schedule";
    line1 = "Set schedule in app";
    return;
  }

  time_t nextAt = 0;
  float nextGrams = 0;
  for (int dayOffset = 0; dayOffset <= 7; ++dayOffset) {
    for (int i = 0; i < feederScheduleCount; ++i) {
      const FeedSchedule& schedule = feederSchedules[i];
      if (!schedule.enabled) continue;
      struct tm candidateTm;
      localtime_r(&now, &candidateTm);
      candidateTm.tm_mday += dayOffset;
      candidateTm.tm_hour = schedule.hour24;
      candidateTm.tm_min = schedule.minute;
      candidateTm.tm_sec = 0;
      const time_t candidate = mktime(&candidateTm);
      struct tm normalized;
      localtime_r(&candidate, &normalized);
      if (schedule.days.length() >= 7 &&
          schedule.days.charAt(normalized.tm_wday) != '1') continue;
      if (schedule.effectiveEpoch > (unsigned long)candidate || candidate <= now) continue;
      if (nextAt == 0 || candidate < nextAt) {
        nextAt = candidate;
        nextGrams = schedule.grams;
      }
    }
    if (nextAt != 0) break;
  }

  if (nextAt == 0) {
    line0 = "No upcoming feed";
    line1 = "Check app schedule";
    return;
  }
  struct tm nextTm;
  localtime_r(&nextAt, &nextTm);
  char timeText[12];
  strftime(timeText, sizeof(timeText), "%I:%M %p", &nextTm);
  if (timeText[0] == '0') memmove(timeText, timeText + 1, strlen(timeText));
  line0 = String("Next ") + timeText;
  line1 = String("Dose: ") + String(nextGrams, 0) + "g";
}

// Non-blocking: refresh at most every LCD_ROTATE_MS, immediate on feed events.
void updateLCD() {
  if (!lcdReady) return;
  MutexGuard sensorLock(sensorStateMutex);
  MutexGuard lcdLock(lcdMutex);
  unsigned long now = millis();
  if (lastLcdRenderMs != 0 && now - lastLcdRenderMs < 250UL) return;
  String l0, l1;
  if (calibrationMode) {
    l0 = "CALIBRATION MODE";
    l1 = WiFi.status() == WL_CONNECTED ? "Cloud paused" : "Wi-Fi offline";
  } else if (lcdCloudBootPending && feederRunState == FEEDER_IDLE &&
             onsiteButtonTapCount == 0 && overrideWarnReason.length() == 0) {
    return;
  } else if (feederRunState == FEEDER_PRE_BLOW) {
    l0 = "Blower warm-up";
    l1 = "Please wait...";
  } else if (feederRunState != FEEDER_IDLE) {
    const String source = feederFeedSource == "onsite" ? "Onsite" :
                          feederFeedSource == "scheduled" ? "Schedule" : "App";
    l0 = source + " " + String(feederRequestedGrams, 0) + "g";
    l1 = String("Gate ") + String(min(feederCurrentCycle + 1, feederMaxCycles)) +
         "/" + String(feederMaxCycles);
  } else if ((long)(now - feederDoneShowMs) < 0) {  // rollover-safe expiry
    l0 = "Feeding completed";
    l1 = "Gate cycles done";
  } else if (overrideWarnReason.length() > 0) {
    l0 = overrideWarnReason.substring(0, 16);
    l1 = "Tap 2x to force";
  } else if (onsiteButtonTapCount > 0) {
    uint16_t taps;
    portENTER_CRITICAL(&onsiteButtonMux);
    taps = onsiteButtonTapCount;
    portEXIT_CRITICAL(&onsiteButtonMux);
    l0 = String("Onsite taps: ") + String(taps);
    l1 = "Pause to dispense";
  } else if ((long)(now - lcdTransientUntilMs) < 0) {  // rollover-safe expiry
    l0 = lcdTransientLine0;
    l1 = lcdTransientLine1;
  } else {
    if (lastLcdMs == 0) {
      lastLcdMs = now;
    } else if (now - lastLcdMs >= LCD_ROTATE_MS) {
      lastLcdMs = now;
      lcdScreen = (lcdScreen + 1) % 4;
    } else if (lastLcdMs != 0) {
      return;
    }
    if (lcdScreen == 0) {
      l0 = String("Temp: ") + (smoothedTemp > -100 ? String(smoothedTemp, 1) + " C" : "--");
      l1 = String("pH: ") + (phLevel >= 0 ? String(phLevel, 1) : "--");
    } else if (lcdScreen == 1) {
      l0 = String("DO:") + (dissolvedOxygen >= 0 ? String(dissolvedOxygen, 1) : "--") + "mg/L";
      l1 = String("Turb:") + (smoothedTurbidityNTU >= 0 ? String(smoothedTurbidityNTU, 0) : "--") + " NTU";
    } else if (lcdScreen == 2) {
      l0 = String("Water:") + (waterLevelCm >= 0 ? String(waterLevelCm, 0) + "cm" : "--");
      l1 = String("Hopper:") + (feedLevelPercent >= 0 ? String(feedLevelPercent, 0) + "%" : "--");
    } else {
      getNextScheduleLines(l0, l1);
    }
  }
  lcdPrint16(0, l0);
  lcdPrint16(1, l1);
  lastLcdRenderMs = now;
}

// Keep sensor acquisition and LCD rotation off the Firebase/control loop.
// The network library's WiFiClient is not safe to use from multiple FreeRTOS
// tasks, so all Firebase calls remain serialized in loop(); these tasks never
// perform network work.
void sensorPollingTask(void*) {
  for (;;) {
    if (!calibrationMode) {
      readAllSensors();
      if (sensorOutputEnabled) printSensorReading();
    }
    // Match the prior loop behavior: wait the configured interval after the
    // completed scan, so a long scan never triggers a catch-up burst.
    vTaskDelay(pdMS_TO_TICKS(SENSOR_POLL_MS));
  }
}

void lcdDisplayTask(void*) {
  for (;;) {
    updateLCD();
    vTaskDelay(pdMS_TO_TICKS(50));
  }
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
  if (!firestoreGetDoc(path.c_str())) {
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
  const String nowTimestamp = firestoreTimestampString(now);
  if (nowTimestamp.isEmpty()) {
    Serial.println("[ACT] Cannot report relay state before clock synchronization");
    return;
  }

  FirebaseJson json;
  json.set("fields/current_state/stringValue", state);
  json.set("fields/last_changed/timestampValue", nowTimestamp);

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
//   actuator_type, action, type, logged_at (Firestore Timestamp)
// Put "(AUTO)" in `action` so the app surfaces it as an auto-control event.
void pushActuatorLog(int idx, String action, String type) {
  if (!ensureFirebaseReady()) return;
  if (currentTankId.length() == 0) return;

  time_t now;
  time(&now);
  const String loggedAt = firestoreTimestampString(now);
  if (loggedAt.isEmpty()) {
    Serial.println("[ACT LOG] Skipped Firestore write: system clock is not synchronized");
    return;
  }

  FirebaseJson json;
  json.set("fields/actuator_type/stringValue", actuators[idx].deviceId);
  json.set("fields/action/stringValue",        action);
  json.set("fields/type/stringValue",          type);
  json.set("fields/logged_at/timestampValue", loggedAt);

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
  // Offline/unassigned operation must keep water circulation and aeration on;
  // stale cached cloud modes must not switch these life-support outputs off.
  if (WiFi.status() != WL_CONNECTED || cloudOutage || !ensureFirebaseReady() ||
      currentTankId.length() == 0) {
    applyOfflineActuatorDefaults();
    return;
  }

  for (int i = 0; i < 3; i++) {
    String mode;
    if (readActuatorMode(i, mode)) {
      actuators[i].controlMode = mode;
    } else if (cloudOutage) {
      applyOfflineActuatorDefaults();
      return;
    }
    if (actuators[i].controlMode.isEmpty()) continue;
    applyActuatorDevice(i);
  }
}

void applyOfflineActuatorDefaults() {
  for (int i = 0; i < 3; i++) {
    setActuatorRelay(i, true);
  }
}
