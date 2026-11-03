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
 *  tanks/{tankId}/sensor_readings/latest    -> latest averaged payload every 10 seconds
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
#include <stddef.h>   // offsetof()
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
Preferences historyPrefs;
String ssid;
String pass;
#define WIFI_MAX_PROFILES 5

enum SystemModeOverride : uint8_t {
  SYSTEM_MODE_AUTO = 0,
  SYSTEM_MODE_FORCE_OFFLINE = 1,
  SYSTEM_MODE_FORCE_ONLINE = 2
};
SystemModeOverride systemModeOverride = SYSTEM_MODE_AUTO;

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
bool systemCloudModeInitialized = false;
bool systemCloudModeActive = false;

bool hasCurrentTankAssignment() {
  return !currentTankId.isEmpty() && !currentOwnerUid.isEmpty() &&
      currentAssignmentAtMs >= 1577836800000LL;
}

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

#define FIREBASE_SEND_INTERVAL_MS 10000
#define HISTORY_SLOT_SECONDS 600        // fixed 10-minute history windows
#define CONFIG_SYNC_INTERVAL_MS 60000   // thresholds re-sync; switch forces immediate
#define FLUSH_INTERVAL_MS 1000           // flush backlog at 1 entry/sec (max)
#define NON_PH_SENSOR_POLL_MS 2000
#define PH_SENSOR_POLL_MS 1000
#define LIVE_SENSOR_AVERAGE_WINDOW_MS 5000UL
#define ASSIGNMENT_RECHECK_MS 60000      // refresh hardware assignment once per minute
#define ASSIGNMENT_SEARCH_MS 10000      // aggressive search while missing

// Feeder timing
#define FEEDER_CMD_INTERVAL_MS 1000
#define FEEDER_STATUS_INTERVAL_MS 15000
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
  if (WiFi.status() != WL_CONNECTED) return;
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
time_t nextHistorySlotEndEpoch = 0;
unsigned long lastFlushTime = 0;

// ─── Offline buffer (LittleFS store-and-forward) ─────────────────────
// History entries that fail to upload (WiFi outage / Firebase unreachable)
// are appended here as Firestore wire-format JSON lines. When connectivity
// returns, loop() flushes them oldest-first at 1 entry/sec, deleting each
// line only after Firestore confirms the write (or finds a duplicate doc).
#define BUFFER_PATH "/buf/history.jsonl"
bool littlefsMounted = false;
bool feederLogsReady = true;

size_t countBufferedEntries();  // forward decl (used by initOfflineBuffer)

// SD card pins (VSPI) — declared early so initSDCard() below can use them.
// (Also listed in the PINOUT section further down.)
#define SD_SPI_SCK_PIN 18
#define SD_SPI_MISO_PIN 19
#define SD_SPI_MOSI_PIN 23
#define SD_SPI_CS_PIN 15  // GPIO15 (MTDO) needs HIGH at boot — CS idles HIGH via pull-up, so safe.
void initSDCard();
void migrateLittleFSToSD();
void migrateFeederLogsToSD();

bool sdMounted = false;
#define SD_BUFFER_PATH "/craycare/history.jsonl"
#define SD_BUFFER_TMP "/craycare/history.tmp"

// Active write backend: SD card when present, otherwise LittleFS.
static inline fs::FS& bufFS() { return sdMounted ? (fs::FS&)SD : (fs::FS&)LittleFS; }
static inline const char* bufPath() { return sdMounted ? SD_BUFFER_PATH : BUFFER_PATH; }
static inline const char* bufTmpPath() { return sdMounted ? SD_BUFFER_TMP : "/buf/history.tmp"; }
static inline fs::FS& feederLogFS() { return sdMounted ? (fs::FS&)SD : (fs::FS&)LittleFS; }
static inline String feederLogRoot() { return sdMounted ? "/craycare/feedlogs" : "/feedlogs"; }
static inline String feederLogPath(const String& name) {
  return feederLogRoot() + "/" + name;
}
static inline bool removeFeederLogIfPresent(fs::FS& fileSystem,
                                            const String& path) {
  return !fileSystem.exists(path) || fileSystem.remove(path);
}
static bool ensureFeederLogDirectory() {
  fs::FS& fs = feederLogFS();
  const String root = feederLogRoot();
  if (sdMounted && !fs.exists("/craycare") && !fs.mkdir("/craycare")) return false;
  if (!fs.exists(root) && !fs.mkdir(root)) return false;
  return fs.exists(root);
}

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
  if (!ensureFeederLogDirectory()) {
    feederLogsReady = false;
    Serial.println("[FEEDER LOG] Could not create /craycare/feedlogs on SD; local log retry paused");
  } else {
    feederLogsReady = true;
  }
  Serial.println("[BUF] SD card mounted — migrating LittleFS backlog and feeder intents");
  migrateFeederLogsToSD();
  migrateLittleFSToSD();
}

// Migrate legacy offline feeder journals and pending intents to SD when
// available, preserving them before switching the active queue backend.
void migrateFeederLogsToSD() {
  if (!sdMounted || !littlefsMounted || !LittleFS.exists("/feedlogs")) return;
  if (!SD.exists("/craycare/feedlogs") && !SD.mkdir("/craycare/feedlogs")) {
    Serial.println("[FEEDER LOG] Could not create SD log directory; retaining LittleFS logs");
    feederLogsReady = false;
    return;
  }

  File dir = LittleFS.open("/feedlogs");
  if (!dir || !dir.isDirectory()) {
    if (dir) dir.close();
    feederLogsReady = false;
    Serial.println("[FEEDER LOG] Could not inspect legacy LittleFS logs; feed requests blocked for safety");
    return;
  }
  std::vector<String> copiedPaths;
  for (File src = dir.openNextFile(); src; src = dir.openNextFile()) {
    const String oldPath = src.path();
    const int slash = oldPath.lastIndexOf('/');
    const String name = slash >= 0 ? oldPath.substring(slash + 1) : oldPath;
    if (!name.endsWith(".pending") && !name.endsWith(".json")) {
      src.close();
      continue;
    }
    const String newPath = feederLogPath(name);
    File dst = SD.open(newPath, "w");
    if (!dst) {
      Serial.printf("[FEEDER LOG] Could not migrate %s to SD; retaining source\n",
                    oldPath.c_str());
      feederLogsReady = false;
      src.close();
      continue;
    }
    const size_t expected = src.size();
    size_t copied = 0;
    while (src.available()) {
      const int byteValue = src.read();
      if (byteValue < 0 || dst.write((uint8_t)byteValue) != 1) break;
      ++copied;
    }
    dst.flush();
    dst.close();
    src.close();
    if (copied == expected) copiedPaths.push_back(oldPath);
    else {
      feederLogsReady = false;
      Serial.printf("[FEEDER LOG] Incomplete migration of %s; retaining source\n",
                    oldPath.c_str());
    }
  }
  dir.close();
  for (const String& oldPath : copiedPaths) LittleFS.remove(oldPath);
  if (!copiedPaths.empty()) {
    Serial.printf("[FEEDER LOG] Migrated %u pending/completed file(s) to SD\n",
                  (unsigned)copiedPaths.size());
  }
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

bool bufferAppend(const String& jsonLine, long long capturedAtMs = 0) {
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
  // Keep the deterministic history key beside the JSON in the device-local
  // queue. This prefix is stripped before upload, so it is never a Firestore
  // field. Older buffered rows without the prefix remain supported below.
  String queuedLine = jsonLine;
  if (capturedAtMs > 0) {
    char prefix[32];
    snprintf(prefix, sizeof(prefix), "@%llu\t",
             static_cast<unsigned long long>(capturedAtMs));
    queuedLine = String(prefix) + jsonLine;
  }
  const size_t previousSize = f.size();
  const size_t written = f.println(queuedLine);
  f.flush();
  const bool writeOk = written >= queuedLine.length() + 1 &&
      f.size() >= previousSize + queuedLine.length() + 1;
  f.close();
  return writeOk;
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

  // Deterministic doc ID from local queue metadata. The metadata is not part
  // of the Firestore payload. Old buffer rows used captured_at_ms in their
  // payload, so retain that parser for rows queued by previous firmware.
  long long capMs = 0;
  String payloadLine = lines[0];
  int separator = payloadLine.indexOf('\t');
  if (payloadLine.startsWith("@") && separator > 1) {
    capMs = atoll(payloadLine.substring(1, separator).c_str());
    payloadLine = payloadLine.substring(separator + 1);
  }
  int idx = payloadLine.indexOf("\"captured_at_ms\"");
  if (idx >= 0) {
    int st = payloadLine.indexOf("\"integerValue\":\"", idx);
    if (st >= 0) {
      st += 17;  // length of "\"integerValue\":\"" (17 chars)
      int en = payloadLine.indexOf('"', st);
      if (en > st && capMs <= 0) capMs = atoll(payloadLine.substring(st, en).c_str());
    }
  }
  // Previous firmware queued both timestamps. When recorded_at is present,
  // remove the redundant field before staging the old payload. Truly legacy
  // rows without recorded_at keep their only timestamp for the router's
  // compatibility fallback.
  if (idx >= 0 && payloadLine.indexOf("\"recorded_at\"") >= 0) {
    FirebaseJson legacyPayload;
    if (legacyPayload.setJsonData(payloadLine) &&
        legacyPayload.remove("fields/captured_at_ms")) {
      payloadLine = legacyPayload.raw();
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
                                        docId.c_str(), payloadLine.c_str(), "")) {
    Serial.printf("[BUF] Flushed entry -> %s\n", docPath.c_str());
    return bufferDropFirst(lines, n);
  }
  Serial.printf("[BUF] Flush failed (%s) — will retry\n", fbdo.errorReason().c_str());
  return false;
}
unsigned long lastConfigSyncTime = 0;
unsigned long lastAssignmentCheckMs = 0;
unsigned long lastNonPhPollTime = 0;
unsigned long lastPhPollTime = 0;
unsigned long lastWifiReconnectTime = 0;
bool ntpEverSynced = false;            // set once time() passes the epoch gate
unsigned long lastNtpSyncMs = 0;
time_t feederBootEpoch = 0;            // wall-clock time first established this boot
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
String feederWaterQualityWarning = "";
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
// the old GPIO13 scatter output are retired.)
#define GATE_SERVO_PIN 5
#define GATE_MAX_ANGLE 180
#define GATE_PULSE_MIN_US 500
#define GATE_PULSE_MAX_US 2500
#define GATE_OPEN_ANGLE_DFLT 90    // starting point — tune on bench, store via GATE_ANGLE
#define GATE_CLOSE_ANGLE_DFLT 0    // starting point — tune on bench, store via GATE_CLOSE_ANGLE
#define GATE_HOLD_MS_DFLT 800      // starting point — tune on bench, store via GATE_MS
#define GATE_CLOSE_DWELL_MS_DEFAULT 1000UL
#define GATE_CLOSE_DWELL_MS_MAX 60000UL
unsigned long gateCloseDwellMs = GATE_CLOSE_DWELL_MS_DEFAULT; // persisted runtime setting
int gateOpenAngle = GATE_OPEN_ANGLE_DFLT;  // NVS "gateAngle"
int gateCloseAngle = GATE_CLOSE_ANGLE_DFLT; // NVS "gateClose"
bool gateCloseAngleConfigured = false;     // require explicit calibration before actuating
int gateHoldMs = GATE_HOLD_MS_DFLT;        // NVS "gateHold"
int gateAngleNow = 0;
bool gateServoAttached = false;

bool loadRuntimeSettings() {
  if (!prefs.begin("runtime", true)) return false;
  const int savedMode = prefs.isKey("mode")
      ? prefs.getInt("mode", SYSTEM_MODE_AUTO) : SYSTEM_MODE_AUTO;
  systemModeOverride = savedMode >= SYSTEM_MODE_AUTO && savedMode <= SYSTEM_MODE_FORCE_ONLINE
      ? (SystemModeOverride)savedMode : SYSTEM_MODE_AUTO;
  const uint32_t savedDwell = prefs.isKey("gateDwell")
      ? prefs.getUInt("gateDwell", GATE_CLOSE_DWELL_MS_DEFAULT)
      : GATE_CLOSE_DWELL_MS_DEFAULT;
  gateCloseDwellMs = savedDwell <= GATE_CLOSE_DWELL_MS_MAX
      ? savedDwell : GATE_CLOSE_DWELL_MS_DEFAULT;
  prefs.end();
  return true;
}

bool saveRuntimeSetting(const char* key, uint32_t value) {
  if (!prefs.begin("runtime", false)) return false;
  const bool saved = prefs.putUInt(key, value) == sizeof(uint32_t);
  prefs.end();
  return saved;
}

bool saveSystemMode(SystemModeOverride mode) {
  if (!prefs.begin("runtime", false)) return false;
  const bool saved = prefs.putInt("mode", (int)mode) == sizeof(int32_t);
  prefs.end();
  return saved;
}

const char* systemModeName() {
  switch (systemModeOverride) {
    case SYSTEM_MODE_FORCE_OFFLINE: return "OFFLINE";
    case SYSTEM_MODE_FORCE_ONLINE: return "ONLINE";
    default: return "AUTO";
  }
}

bool cloudModeForcedOffline() {
  return systemModeOverride == SYSTEM_MODE_FORCE_OFFLINE;
}

int _servoPulseToDuty(int pulseUs) {
  pulseUs = constrain(pulseUs, 500, 2600);
  return (int)((float)pulseUs / 20000.0f * 65535.0f);
}

void setGateAngle(int angle) {
  angle = constrain(angle, 0, GATE_MAX_ANGLE);
  if (!gateServoAttached) {
    ledcAttachPin(GATE_SERVO_PIN, SERVO_LEDC_CHANNEL);
    gateServoAttached = true;
  }
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
// Use GPIO13 for the onsite feed button; GPIO12 is an ESP32 strapping pin.
// Pump transitions can create false edges, so the ISR also has timed lockouts.
#define ONSITE_BUTTON_PIN 13
#define ONSITE_BUTTON_DEBOUNCE_US 50000UL
#define ONSITE_BUTTON_BATCH_MS 1500UL
#define ONSITE_BUTTON_MAX_TAPS 200
#define ONSITE_BOOT_LOCKOUT_US 15000000UL
#define ONSITE_PUMP_LOCKOUT_US 3000000UL
volatile uint16_t onsiteButtonTapCount = 0;
volatile uint32_t onsiteButtonLastTapUs = 0;
volatile uint32_t onsiteButtonLockoutStartedUs = 0;
volatile uint32_t onsiteButtonLockoutDurationUs = 0;
volatile bool onsiteButtonLockoutActive = false;
volatile bool onsiteButtonEnabled = false;
portMUX_TYPE onsiteButtonMux = portMUX_INITIALIZER_UNLOCKED;

bool isOnsiteButtonLockedOut() {
  const uint32_t nowUs = micros();
  portENTER_CRITICAL(&onsiteButtonMux);
  if (onsiteButtonLockoutActive &&
      (uint32_t)(nowUs - onsiteButtonLockoutStartedUs) >=
          onsiteButtonLockoutDurationUs) {
    onsiteButtonLockoutActive = false;
  }
  const bool lockedOut = onsiteButtonLockoutActive;
  portEXIT_CRITICAL(&onsiteButtonMux);
  return lockedOut;
}

void beginOnsiteButtonLockout(uint32_t durationUs) {
  portENTER_CRITICAL(&onsiteButtonMux);
  onsiteButtonTapCount = 0;
  onsiteButtonLastTapUs = micros();
  onsiteButtonLockoutStartedUs = onsiteButtonLastTapUs;
  onsiteButtonLockoutDurationUs = durationUs;
  onsiteButtonLockoutActive = true;
  portEXIT_CRITICAL(&onsiteButtonMux);
}
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
//  Two-point field calibration: clear water voltage must exceed dirty voltage.
//  No independent air/no-water classification is used in this mode.
// ============================================================
float turbidityVClear = 1.50;          // Voltage for clear water (0 NTU)
float turbidityVDirty = 1.40;          // Voltage for very dirty water (500 NTU)

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
constexpr float FEED_LEVEL_CRITICAL_DEFAULT = 10.0f;
float feedLevelCriticalThreshold = FEED_LEVEL_CRITICAL_DEFAULT;
float feedLevelEmptyVoltage = 0.50f;
float feedLevelFullVoltage = 2.80f;


float doVoltageScale = 4.0;
float doVoltageOffset = 0.0;
float phVoltageSlope = -5.70;
float phVoltageIntercept = 21.34;
// Optional empirical correction after the two-point voltage-to-pH fit.
// Stored magnitude defaults to +1.50 pH, but it is disabled until activated.
float phReadingOffset = 1.50f;
bool phReadingOffsetEnabled = false;
int phFitPointCount = 2;  // NVS "phFitN"; number of points in the active fit
int phFitMode = 2;        // NVS "phFitMode"; selected algorithm: 2-point or 3-point
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
#define CAL_PH_RAW_MAX_BLOCKS 80
#define CAL_PH_MIN_STABLE_BLOCKS 30
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
// Non-CALMODE pH calibration needs a stable 60 s window of live FIT_V blocks.
bool rawPHCalibrationStable = false;
float rawPHCalibrationMinV = 0.0f;
float rawPHCalibrationMaxV = 0.0f;
float rawPHCalibrationSumV = 0.0f;
uint16_t rawPHCalibrationSamples = 0;
float rawPHCalibrationAverageV = 0.0f;
float rawPHCalibrationBlocks[CAL_PH_RAW_MAX_BLOCKS] = {};
unsigned long rawPHCalibrationBlockMs[CAL_PH_RAW_MAX_BLOCKS] = {};
uint8_t rawPHCalibrationHead = 0;
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
// each ten-minute history entry stores one average per valid sensor. Non-pH
// sensors poll every 2 s and pH every 1 s, so counts vary by sensor.
// Reset after every history write (or buffer append).
float winTempSum = 0.0f; uint16_t winTempN = 0;
float winTurbSum = 0.0f; uint16_t winTurbN = 0;
float winDOSum = 0.0f; uint16_t winDON = 0;
float winPHSum = 0.0f; uint16_t winPHN = 0;
float winWaterLevelSum = 0.0f; uint16_t winWaterLevelN = 0;
float winFeedLevelSum = 0.0f; uint16_t winFeedLevelN = 0;

// A small NVS checkpoint preserves the in-progress window across resets.
// The pending JSON is stored in the same blob so snapshot/reset is atomic.
constexpr uint32_t HISTORY_STATE_MAGIC = 0x43524857; // "CRHW"
constexpr uint16_t HISTORY_STATE_VERSION = 1;
constexpr size_t HISTORY_PENDING_JSON_CAP = 1200;
struct PersistedHistoryState {
  uint32_t magic;
  uint16_t version;
  uint16_t reserved;
  int64_t nextSlotEndEpoch;
  int64_t assignmentAtMs;
  char tankId[80];
  char ownerUid[128];
  float tempSum;
  uint16_t tempN;
  float turbSum;
  uint16_t turbN;
  float doSum;
  uint16_t doN;
  float phSum;
  uint16_t phN;
  float waterLevelSum;
  uint16_t waterLevelN;
  float feedLevelSum;
  uint16_t feedLevelN;
  int64_t pendingCapturedAtMs;
  char pendingJson[HISTORY_PENDING_JSON_CAP];
  uint32_t checksum;
};
PersistedHistoryState persistedHistoryState{};
bool historyWindowRecovered = false;
unsigned long lastHistoryCheckpointMs = 0;

uint32_t historyStateChecksum(const PersistedHistoryState& state) {
  const uint8_t* bytes = reinterpret_cast<const uint8_t*>(&state);
  uint32_t hash = 2166136261UL;
  for (size_t i = 0; i < offsetof(PersistedHistoryState, checksum); ++i) {
    hash = (hash ^ bytes[i]) * 16777619UL;
  }
  return hash;
}

bool writeHistoryState(PersistedHistoryState& state) {
  state.magic = HISTORY_STATE_MAGIC;
  state.version = HISTORY_STATE_VERSION;
  state.checksum = historyStateChecksum(state);
  if (!historyPrefs.begin("histwin", false)) return false;
  const size_t written = historyPrefs.putBytes("state", &state, sizeof(state));
  historyPrefs.end();
  return written == sizeof(state);
}

bool saveHistoryWindowCheckpoint() {
  PersistedHistoryState next = persistedHistoryState;
  {
    MutexGuard sensorLock(sensorStateMutex);
    next.nextSlotEndEpoch = nextHistorySlotEndEpoch;
    next.tempSum = winTempSum; next.tempN = winTempN;
    next.turbSum = winTurbSum; next.turbN = winTurbN;
    next.doSum = winDOSum; next.doN = winDON;
    next.phSum = winPHSum; next.phN = winPHN;
    next.waterLevelSum = winWaterLevelSum; next.waterLevelN = winWaterLevelN;
    next.feedLevelSum = winFeedLevelSum; next.feedLevelN = winFeedLevelN;
    // Keep the recovered identity while booted offline; the next successful
    // assignment read will either confirm it or clear the old window.
    if (!historyWindowRecovered || hasCurrentTankAssignment()) {
      strlcpy(next.tankId, currentTankId.c_str(), sizeof(next.tankId));
      strlcpy(next.ownerUid, currentOwnerUid.c_str(), sizeof(next.ownerUid));
      next.assignmentAtMs = currentAssignmentAtMs;
    }
  }
  if (!writeHistoryState(next)) return false;
  persistedHistoryState = next;
  if (hasCurrentTankAssignment()) historyWindowRecovered = false;
  return true;
}

bool loadHistoryWindowCheckpoint() {
  PersistedHistoryState loaded{};
  if (!historyPrefs.begin("histwin", true)) return false;
  const size_t length = historyPrefs.getBytesLength("state");
  const size_t read = length == sizeof(loaded)
      ? historyPrefs.getBytes("state", &loaded, sizeof(loaded)) : 0;
  historyPrefs.end();
  if (read != sizeof(loaded) || loaded.magic != HISTORY_STATE_MAGIC ||
      loaded.version != HISTORY_STATE_VERSION ||
      loaded.checksum != historyStateChecksum(loaded)) {
    return false;
  }
  persistedHistoryState = loaded;
  nextHistorySlotEndEpoch = static_cast<time_t>(loaded.nextSlotEndEpoch);
  const bool assignmentKnown = hasCurrentTankAssignment();
  const bool sameAssignment = assignmentKnown &&
      currentTankId == loaded.tankId && currentOwnerUid == loaded.ownerUid &&
      currentAssignmentAtMs == loaded.assignmentAtMs;
  if (!assignmentKnown || sameAssignment) {
    MutexGuard sensorLock(sensorStateMutex);
    winTempSum = loaded.tempSum; winTempN = loaded.tempN;
    winTurbSum = loaded.turbSum; winTurbN = loaded.turbN;
    winDOSum = loaded.doSum; winDON = loaded.doN;
    winPHSum = loaded.phSum; winPHN = loaded.phN;
    winWaterLevelSum = loaded.waterLevelSum; winWaterLevelN = loaded.waterLevelN;
    winFeedLevelSum = loaded.feedLevelSum; winFeedLevelN = loaded.feedLevelN;
    historyWindowRecovered = true;
    Serial.println("[HISTORY] Restored in-progress 10-minute window from NVS");
  } else {
    Serial.println("[HISTORY] Discarded checkpoint from a previous tank assignment");
    resetWindowAggregates();
    saveHistoryWindowCheckpoint();
  }
  return true;
}

bool clearPendingHistoryCheckpoint() {
  PersistedHistoryState previous = persistedHistoryState;
  persistedHistoryState.pendingCapturedAtMs = 0;
  persistedHistoryState.pendingJson[0] = '\0';
  if (saveHistoryWindowCheckpoint()) return true;
  persistedHistoryState = previous;
  return false;
}

bool queuePendingHistoryIfPossible() {
  if (persistedHistoryState.pendingCapturedAtMs <= 0 ||
      persistedHistoryState.pendingJson[0] == '\0') return true;
  if (!bufferAppend(String(persistedHistoryState.pendingJson),
                    persistedHistoryState.pendingCapturedAtMs)) return false;
  if (!clearPendingHistoryCheckpoint()) return false;
  Serial.println("[HISTORY] Recovered pending entry into the offline queue");
  return true;
}

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

struct LiveAverageBucket {
  float sum;
  uint16_t count;
};

struct LiveSensorSnapshot {
  bool ready;
  bool tempValid;
  bool turbidityValid;
  bool doValid;
  bool phValid;
  bool waterValid;
  bool feedValid;
  float temperature;
  float turbidityNTU;
  float dissolvedOxygen;
  float ph;
  float waterLevelCm;
  float feedLevelPercent;
  uint16_t tempSamples;
  uint16_t turbiditySamples;
  uint16_t doSamples;
  uint16_t phSamples;
  uint16_t waterSamples;
  uint16_t feedSamples;
};

LiveAverageBucket liveTempWindow = {};
LiveAverageBucket liveTurbidityWindow = {};
LiveAverageBucket liveDOWindow = {};
LiveAverageBucket livePHWindow = {};
LiveAverageBucket liveWaterWindow = {};
LiveAverageBucket liveFeedWindow = {};
LiveSensorSnapshot liveSensorSnapshot = {};
unsigned long liveAverageWindowStartedMs = 0;

void accumulateLiveReading(LiveAverageBucket& bucket, float value) {
  if (!isfinite(value) || bucket.count == UINT16_MAX) return;
  bucket.sum += value;
  ++bucket.count;
}

void clearLiveAverageBucketsUnlocked() {
  liveTempWindow = {};
  liveTurbidityWindow = {};
  liveDOWindow = {};
  livePHWindow = {};
  liveWaterWindow = {};
  liveFeedWindow = {};
}

void resetLiveAverageWindowUnlocked(bool clearSnapshot) {
  clearLiveAverageBucketsUnlocked();
  liveAverageWindowStartedMs = millis();
  if (clearSnapshot) liveSensorSnapshot = {};
}

bool publishLiveAverageWindowUnlocked(unsigned long now) {
  if (liveAverageWindowStartedMs == 0) {
    liveAverageWindowStartedMs = now;
    return false;
  }
  if (now - liveAverageWindowStartedMs < LIVE_SENSOR_AVERAGE_WINDOW_MS) return false;

  liveSensorSnapshot.tempSamples = liveTempWindow.count;
  liveSensorSnapshot.turbiditySamples = liveTurbidityWindow.count;
  liveSensorSnapshot.doSamples = liveDOWindow.count;
  liveSensorSnapshot.phSamples = livePHWindow.count;
  liveSensorSnapshot.waterSamples = liveWaterWindow.count;
  liveSensorSnapshot.feedSamples = liveFeedWindow.count;
  liveSensorSnapshot.tempValid = liveTempWindow.count > 0;
  liveSensorSnapshot.turbidityValid = liveTurbidityWindow.count > 0;
  liveSensorSnapshot.doValid = liveDOWindow.count > 0;
  liveSensorSnapshot.phValid = livePHWindow.count > 0;
  liveSensorSnapshot.waterValid = liveWaterWindow.count > 0;
  liveSensorSnapshot.feedValid = liveFeedWindow.count > 0;
  liveSensorSnapshot.temperature = liveSensorSnapshot.tempValid
      ? liveTempWindow.sum / liveTempWindow.count : -1.0f;
  liveSensorSnapshot.turbidityNTU = liveSensorSnapshot.turbidityValid
      ? liveTurbidityWindow.sum / liveTurbidityWindow.count : -1.0f;
  liveSensorSnapshot.dissolvedOxygen = liveSensorSnapshot.doValid
      ? liveDOWindow.sum / liveDOWindow.count : -1.0f;
  liveSensorSnapshot.ph = liveSensorSnapshot.phValid
      ? livePHWindow.sum / livePHWindow.count : -1.0f;
  liveSensorSnapshot.waterLevelCm = liveSensorSnapshot.waterValid
      ? liveWaterWindow.sum / liveWaterWindow.count : -1.0f;
  liveSensorSnapshot.feedLevelPercent = liveSensorSnapshot.feedValid
      ? liveFeedWindow.sum / liveFeedWindow.count : -1.0f;
  liveSensorSnapshot.ready = true;

  clearLiveAverageBucketsUnlocked();
  liveAverageWindowStartedMs = now;
  return true;
}

bool publishLiveAverageWindow() {
  MutexGuard sensorLock(sensorStateMutex);
  return publishLiveAverageWindowUnlocked(millis());
}

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
  saved &= prefs.putFloat("phOffset", phReadingOffset) == sizeof(float);
  saved &= prefs.putBool("phOffOn", phReadingOffsetEnabled);
  saved &= prefs.putInt("phFitN", phFitPointCount) == sizeof(int32_t);
  saved &= prefs.putInt("phFitMode", phFitMode) == sizeof(int32_t);
  saved &= prefs.putFloat("doScale", doVoltageScale) == sizeof(float);
  saved &= prefs.putFloat("doOffset", doVoltageOffset) == sizeof(float);
  saved &= prefs.putFloat("tankHeight", waterSensorHeightCm) == sizeof(float);
  saved &= prefs.putFloat("tankDepth", waterLevelCmMax) == sizeof(float);
  saved &= prefs.putFloat("turbClear", turbidityVClear) == sizeof(float);
  saved &= prefs.putFloat("turbDirty", turbidityVDirty) == sizeof(float);
  saved &= prefs.putFloat("feedEmpty", feedLevelEmptyVoltage) == sizeof(float);
  saved &= prefs.putFloat("feedFull", feedLevelFullVoltage) == sizeof(float);
  saved &= prefs.putFloat("hopEmpty", hopperEmptyCm) == sizeof(float);
  saved &= prefs.putFloat("hopFull", hopperFullCm) == sizeof(float);
  saved &= prefs.putInt("feedMode", feedLevelMode) == sizeof(int32_t);
  saved &= prefs.putInt("gateAngle", gateOpenAngle) == sizeof(int32_t);
  if (gateCloseAngleConfigured)
    saved &= prefs.putInt("gateClose", gateCloseAngle) == sizeof(int32_t);
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
  phReadingOffset = prefs.getFloat("phOffset", phReadingOffset);
  phReadingOffsetEnabled = prefs.getBool("phOffOn", false);
  phFitPointCount = prefs.getInt("phFitN", 2);
  if (phFitPointCount != 3) phFitPointCount = 2;
  phFitMode = prefs.getInt("phFitMode", 2);
  if (phFitMode != 3) phFitMode = 2;
  doVoltageScale = prefs.getFloat("doScale", doVoltageScale);
  doVoltageOffset = prefs.getFloat("doOffset", doVoltageOffset);
  waterSensorHeightCm = prefs.getFloat("tankHeight", waterSensorHeightCm);
  waterLevelCmMax = prefs.getFloat("tankDepth", waterLevelCmMax);
  turbidityVClear = prefs.getFloat("turbClear", turbidityVClear);
  turbidityVDirty = prefs.getFloat("turbDirty", turbidityVDirty);
  feedLevelEmptyVoltage = prefs.getFloat("feedEmpty", feedLevelEmptyVoltage);
  feedLevelFullVoltage = prefs.getFloat("feedFull", feedLevelFullVoltage);
  hopperEmptyCm = prefs.getFloat("hopEmpty", hopperEmptyCm);
  hopperFullCm = prefs.getFloat("hopFull", hopperFullCm);
  feedLevelMode = prefs.getInt("feedMode", feedLevelMode);
  if (feedLevelMode != 0) feedLevelMode = 1;
  gateOpenAngle = constrain(prefs.getInt("gateAngle", gateOpenAngle), 10, GATE_MAX_ANGLE);
  gateCloseAngleConfigured = prefs.isKey("gateClose");
  gateCloseAngle = constrain(prefs.getInt("gateClose", gateCloseAngle), 0, GATE_MAX_ANGLE);
  if (abs(gateOpenAngle - gateCloseAngle) < 10) {
    gateCloseAngle = GATE_CLOSE_ANGLE_DFLT;
    gateCloseAngleConfigured = false;
  }
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

// The live pH formula and offline CALSTREAM must pass their voltage samples
// through this exact same median/stability pipeline. The fit is evaluated
// against this filtered voltage, not the one-batch diagnostic voltage.
float updatePHFitVoltage(float batchVoltage) {
  phVoltage = batchVoltage;
  phFilteredVoltage = pushMedianVoltage(phVoltageSamples,
      phVoltageSampleCount, phVoltageSampleNext, batchVoltage);
  phReadingStable = phVoltageSampleCount == SENSOR_FILTER_WINDOW &&
      voltageWindowSpread(phVoltageSamples, phVoltageSampleCount) <=
          LIVE_PH_STABLE_SPREAD_V;
  return phFilteredVoltage;
}

bool turbidityCalibrationValid() {
  return isfinite(turbidityVClear) && isfinite(turbidityVDirty) &&
      turbidityVClear <= 3.25f && turbidityVDirty > 0.0f &&
      turbidityVClear > turbidityVDirty;
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

  if (!turbidityCalibrationValid() || !isfinite(v) || v < 0.0f || v > 3.3f) {
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
  if (!hasCurrentTankAssignment()) {
    if (sensorOutputEnabled) Serial.println("[CONFIG] No tank assigned; retaining firmware defaults.");
    return;
  }
  if (!ensureFirebaseReady()) return;

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
  if (cloudModeForcedOffline() || cloudOutage) return false;
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
  const String recordedAt = firestoreTimestampString(capturedAt);
  if (recordedAt.length() > 0) {
    json.set("fields/recorded_at/timestampValue", recordedAt);
  }

  if (!includeTimestamp) {
    // Real sensors use the most recently completed 5-second average window.
    // The Firestore send timer remains independent at 10 seconds.
    json.set("fields/temperature/doubleValue",
             liveSensorSnapshot.ready && liveSensorSnapshot.tempValid
                 ? liveSensorSnapshot.temperature : -1.0f);

    if (liveSensorSnapshot.ready && liveSensorSnapshot.turbidityValid) {
      json.set("fields/turbidity_air/booleanValue", false);
      json.set("fields/turbidity/doubleValue", liveSensorSnapshot.turbidityNTU);
    } else {
      json.set("fields/turbidity_air/booleanValue", true);
      json.set("fields/turbidity/doubleValue", 0.0);
    }

    if (ENABLE_DO_SENSOR) {
      json.set("fields/dissolved_oxygen/doubleValue",
               liveSensorSnapshot.ready && liveSensorSnapshot.doValid
                   ? liveSensorSnapshot.dissolvedOxygen : -1.0f);
    }

    if (ENABLE_PH_SENSOR) {
      json.set("fields/ph_level/doubleValue",
               (liveSensorSnapshot.ready && liveSensorSnapshot.phValid ? liveSensorSnapshot.ph : -1.0f));
    }

    if (ENABLE_WATER_LEVEL_SENSOR) {
      json.set("fields/water_level/doubleValue",
               liveSensorSnapshot.ready && liveSensorSnapshot.waterValid
                   ? liveSensorSnapshot.waterLevelCm : -1.0f);
    }
    if (ENABLE_FEED_LEVEL_SENSOR && liveSensorSnapshot.ready &&
        liveSensorSnapshot.feedValid) {
      json.set("fields/feed_level/doubleValue", liveSensorSnapshot.feedLevelPercent);
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

  // recorded_at is the canonical capture instant for both live and history
  // records. The assignment time remains a separate millisecond field because
  // it identifies the hardware-to-owner assignment, not this reading.
}


// ─── Write latest sensor reading to Firestore ───────────────────────
// Path: tanks/{tankId}/sensor_readings/latest (fixed live document).
// Firestore Rules compare the payload's assignment identity against the
// current hardware_system/currentOwner document before allowing the write.
bool sendLatestToFirestore() {
  if (!hasCurrentTankAssignment()) return false;
  if (!ensureFirebaseReady()) return false;

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
  // Keep captured_at_ms in the update mask solely to delete it from legacy
  // latest documents. New payloads and rules use recorded_at only.
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
void sendHistoryToFirestore(time_t scheduledSlotEnd) {
  if (persistedHistoryState.pendingCapturedAtMs > 0) {
    Serial.println("[HISTORY] Previous entry still pending; retaining current window");
    return;
  }

  // Persist the completed entry and the cleared next window in one NVS blob
  // before making a network request. A reset during TLS/Firebase work can then
  // recover both the pending entry and new readings collected afterward.
  FirebaseJson content;
  // recorded_at is the end of the fixed 10-minute collection window, even
  // when loop scheduling or a slow network makes this write run a little late.
  const time_t capturedAt = scheduledSlotEnd;
  const long long capturedMs = atoll(epochMillisString(capturedAt).c_str());
  {
    MutexGuard sensorLock(sensorStateMutex);
    buildFirestorePayload(content, true, capturedAt);
    const String payload = content.raw();
    if (payload.length() == 0 || payload.length() >= HISTORY_PENDING_JSON_CAP) {
      Serial.println("[HISTORY] Could not persist entry: payload exceeds local checkpoint capacity");
      return;
    }
    PersistedHistoryState next = persistedHistoryState;
    next.pendingCapturedAtMs = capturedMs;
    strlcpy(next.pendingJson, payload.c_str(), sizeof(next.pendingJson));
    next.nextSlotEndEpoch = nextHistorySlotEndEpoch;
    next.tempSum = next.turbSum = next.doSum = next.phSum = 0.0f;
    next.waterLevelSum = next.feedLevelSum = 0.0f;
    next.tempN = next.turbN = next.doN = next.phN = 0;
    next.waterLevelN = next.feedLevelN = 0;
    if (!writeHistoryState(next)) {
      Serial.println("[HISTORY] NVS checkpoint failed; keeping this window in RAM and skipping upload");
      return;
    }
    persistedHistoryState = next;
    resetWindowAggregatesUnlocked();
  }

  // No valid tank assignment means local/offline mode. Keep history in the
  // on-device buffer; do not stage unassigned readings in Firestore.
  if (!hasCurrentTankAssignment()) {
    if (bufferAppend(content.raw(), capturedMs)) {
      Serial.printf("[BUF] No tank assignment — history retained locally (#%u)\n",
                    (unsigned)countBufferedEntries());
      clearPendingHistoryCheckpoint();
    } else {
      Serial.println("[BUF] No tank assignment; durable NVS history retry remains pending");
    }
    return;
  }

  // WiFi/Firebase down: buffer the reading for later flush. (Previously we
  // returned early here and the reading was LOST — the whole point of the
  // store-and-forward buffer is to survive exactly this case.)
  if (WiFi.status() != WL_CONNECTED || !ensureFirebaseReady()) {
    if (bufferAppend(content.raw(), capturedMs)) {
      Serial.printf("[BUF] Offline — buffered entry #%u\n",
                    (unsigned)countBufferedEntries());
      clearPendingHistoryCheckpoint();
    } else {
      Serial.println("[BUF] Offline queue unavailable; durable NVS history retry remains pending");
    }
    return;
  }

  if (capturedAt < 1577836800 || firestoreTimestampString(capturedAt).length() == 0) {
    if (bufferAppend(content.raw(), capturedMs)) {
      Serial.printf("[BUF] Clock unsynchronized; buffered entry #%u\n",
                    (unsigned)countBufferedEntries());
      clearPendingHistoryCheckpoint();
    }
    return;
  }

  const time_t manilaEpoch = capturedAt + 8 * 60 * 60;
  struct tm manilaTm;
  char dateKey[11] = {0};
  char entryId[32];
  if (gmtime_r(&manilaEpoch, &manilaTm) == nullptr ||
      strftime(dateKey, sizeof(dateKey), "%Y-%m-%d", &manilaTm) == 0) {
    if (bufferAppend(content.raw(), capturedMs)) {
      Serial.printf("[BUF] Could not resolve history date; buffered #%u\n",
                    (unsigned)countBufferedEntries());
      clearPendingHistoryCheckpoint();
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
    if (bufferAppend(content.raw(), capturedMs)) {
      Serial.printf("[BUF] Buffered entry #%u for validated history routing\n",
                    (unsigned)countBufferedEntries());
      clearPendingHistoryCheckpoint();
    }
  }
  if (saved) clearPendingHistoryCheckpoint();
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
    accumulateLiveReading(liveTempWindow, rawTemp);
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
    if (sensorOutputEnabled) Serial.printf("[TURB] Invalid voltage or calibration incomplete (V=%.3f)\n", voltage);
    return;
  }
  turbiditySensorOK = true;
  smoothedTurbidityNTU = tr.ntu;
  accumulateLiveReading(liveTurbidityWindow, smoothedTurbidityNTU);
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
  accumulateLiveReading(liveDOWindow, dissolvedOxygen);
  ACCUM_WINDOW(winDOSum, winDON, dissolvedOxygen);
}

void readPHSensor() {
  if (!ENABLE_PH_SENSOR) {
    phLevel = -1.0;
    return;
  }

  const float rawVoltage = readPHVoltage();
  const float voltage = updatePHFitVoltage(rawVoltage);
  if (voltage < 0.05f || voltage > 3.25f) {
    phLevel = -1.0f;
    phSensorOK = false;
    if (sensorOutputEnabled) Serial.printf("[PH] Invalid/disconnected voltage: %.3fV\n", phVoltage);
    return;
  }
  phLevel = phVoltageSlope * voltage + phVoltageIntercept +
      (phReadingOffsetEnabled ? phReadingOffset : 0.0f);
  if (!isfinite(phLevel) || phLevel < 0.0f || phLevel > 14.0f) {
    phLevel = -1.0f;
    phSensorOK = false;
    return;
  }
  phSensorOK = true;
  accumulateLiveReading(livePHWindow, phLevel);
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
  accumulateLiveReading(liveWaterWindow, waterLevelCm);
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
      accumulateLiveReading(liveFeedWindow, feedLevelPercent);
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
  accumulateLiveReading(liveFeedWindow, feedLevelPercent);
  ACCUM_WINDOW(winFeedLevelSum, winFeedLevelN, feedLevelPercent);
}

void readFeedLevelSensorSafely() {
  MutexGuard sensorLock(sensorStateMutex);
  readFeedLevelSensor();
}

void readNonPHSensors() {
  MutexGuard sensorLock(sensorStateMutex);
  readTemperatureSensor();
  readTurbiditySensor();
  readDissolvedOxygenSensor();
  readWaterLevelSensor();
  readFeedLevelSensor();
}

void readPHSensorSafely() {
  MutexGuard sensorLock(sensorStateMutex);
  readPHSensor();
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

void printSensorReading(bool useLiveAverage = true) {
  MutexGuard sensorLock(sensorStateMutex);
  const bool useSnapshot = useLiveAverage && liveSensorSnapshot.ready;
  const float shownTemp = useSnapshot
      ? (liveSensorSnapshot.tempValid ? liveSensorSnapshot.temperature : -127.0f)
      : smoothedTemp;
  const float shownTurbidity = useSnapshot
      ? (liveSensorSnapshot.turbidityValid ? liveSensorSnapshot.turbidityNTU : -1.0f)
      : smoothedTurbidityNTU;
  const float shownDO = useSnapshot
      ? (liveSensorSnapshot.doValid ? liveSensorSnapshot.dissolvedOxygen : -1.0f)
      : dissolvedOxygen;
  const float shownPH = useSnapshot
      ? (liveSensorSnapshot.phValid ? liveSensorSnapshot.ph : -1.0f)
      : phLevel;
  const float shownWater = useSnapshot
      ? (liveSensorSnapshot.waterValid ? liveSensorSnapshot.waterLevelCm : -1.0f)
      : waterLevelCm;
  const float shownFeed = useSnapshot
      ? (liveSensorSnapshot.feedValid ? liveSensorSnapshot.feedLevelPercent : -1.0f)
      : feedLevelPercent;
  Serial.printf("%s n(T=%u,Turb=%u,DO=%u,pH=%u,W=%u,F=%u) Temp: %.2f C | Turb: %.0f NTU (lastV=%.3f,%s) | DO: %.2f mg/L (lastV=%.3f,%s) | pH: %.2f (lastV=%.3f,%s) | Level: %.1f cm | Feed: %.1f%%\n",
                useSnapshot ? "[SENSOR AVG5s]" : "[SENSOR READ]",
                useSnapshot ? (unsigned)liveSensorSnapshot.tempSamples : 0U,
                useSnapshot ? (unsigned)liveSensorSnapshot.turbiditySamples : 0U,
                useSnapshot ? (unsigned)liveSensorSnapshot.doSamples : 0U,
                useSnapshot ? (unsigned)liveSensorSnapshot.phSamples : 0U,
                useSnapshot ? (unsigned)liveSensorSnapshot.waterSamples : 0U,
                useSnapshot ? (unsigned)liveSensorSnapshot.feedSamples : 0U,
                shownTemp, shownTurbidity, turbidityFilteredVoltage,
                turbidityReadingStable ? "STABLE" : "SETTLING",
                shownDO, doFilteredVoltage,
                doReadingStable ? "STABLE" : "SETTLING",
                shownPH, phFilteredVoltage,
                (phReadingStable ? "STABLE" : "SETTLING"),
                shownWater, shownFeed);
}

// One raw-voltage snapshot for calibration stability checks. Reuses the
// latest smoothed values (no extra ADC traffic); called by `raw` and by
// the 1 s `raw on` stream.
void printRawReading() {
  MutexGuard sensorLock(sensorStateMutex);
  Serial.printf("[RAW] pH=%.3fV FIT V=%.4fV DO=%.3fV Turb=%.3fV HC-SR04=%.1fcm Water=%.1fcm Feed=%.3fV/%.0f%% Hopper=%.1fcm(%s)",
                phVoltage, phFilteredVoltage, dissolvedOxygenVoltage, turbidityVoltage,
                waterDistanceCm, waterLevelCm, feedLevelVoltage,
                feedLevelPercent,
                hopperDistanceCm, feedLevelSource);
  if (rawStreamEnabled) {
    const unsigned long now = millis();
    const unsigned long pHWindowSeconds = rawPHCalibrationSamples > 1
        ? min((now - rawPHCalibrationBlockMs[rawPHCalibrationHead]) / 1000UL,
              60UL)
        : 0UL;
    Serial.printf(" | pHcal=%s avg=%.4fV span=%.1fmV window=%lu/60s blocks=%u",
                  (rawPHCalibrationStable ? "STABLE" : "WAIT"),
                  rawPHCalibrationAverageV,
                  (rawPHCalibrationMaxV - rawPHCalibrationMinV) * 1000.0f,
                  pHWindowSeconds, (unsigned)rawPHCalibrationSamples);
  }
  Serial.println();
}

void resetRawPHCalibrationWindow() {
  rawPHCalibrationStable = false;
  rawPHCalibrationMinV = 0.0f;
  rawPHCalibrationMaxV = 0.0f;
  rawPHCalibrationSumV = 0.0f;
  rawPHCalibrationSamples = 0;
  rawPHCalibrationAverageV = 0.0f;
  rawPHCalibrationHead = 0;
}

void updateRawPHCalibrationWindow() {
  float voltage = 0.0f;
  bool filterReady = false;
  {
    MutexGuard sensorLock(sensorStateMutex);
    voltage = phFilteredVoltage;
    filterReady = phVoltageSampleCount == SENSOR_FILTER_WINDOW;
  }
  if (!rawStreamEnabled || !filterReady ||
      !isfinite(voltage) || voltage <= 0.05f || voltage > 3.25f) {
    resetRawPHCalibrationWindow();
    return;
  }

  const unsigned long now = millis();

  // Keep the latest 60 s of live FIT_V blocks. A voltage excursion outside
  // the permitted span restarts the window at the newest block.
  if (rawPHCalibrationSamples == CAL_PH_RAW_MAX_BLOCKS) {
    rawPHCalibrationHead = (rawPHCalibrationHead + 1) % CAL_PH_RAW_MAX_BLOCKS;
    rawPHCalibrationSamples--;
  }
  const uint8_t tail = (rawPHCalibrationHead + rawPHCalibrationSamples) %
      CAL_PH_RAW_MAX_BLOCKS;
  rawPHCalibrationBlocks[tail] = voltage;
  rawPHCalibrationBlockMs[tail] = now;
  rawPHCalibrationSamples++;

  // Preserve a block at least 60 s old so stability is based on a full window.
  while (rawPHCalibrationSamples > 1) {
    const uint8_t nextHead = (rawPHCalibrationHead + 1) % CAL_PH_RAW_MAX_BLOCKS;
    if (now - rawPHCalibrationBlockMs[nextHead] < CAL_PH_STABLE_MS) break;
    rawPHCalibrationHead = nextHead;
    rawPHCalibrationSamples--;
  }

  rawPHCalibrationMinV = rawPHCalibrationBlocks[rawPHCalibrationHead];
  rawPHCalibrationMaxV = rawPHCalibrationBlocks[rawPHCalibrationHead];
  rawPHCalibrationSumV = 0.0f;
  for (uint16_t i = 0; i < rawPHCalibrationSamples; ++i) {
    const uint8_t index = (rawPHCalibrationHead + i) % CAL_PH_RAW_MAX_BLOCKS;
    const float block = rawPHCalibrationBlocks[index];
    rawPHCalibrationMinV = min(rawPHCalibrationMinV, block);
    rawPHCalibrationMaxV = max(rawPHCalibrationMaxV, block);
    rawPHCalibrationSumV += block;
  }

  if (rawPHCalibrationMaxV - rawPHCalibrationMinV > CAL_PH_STABLE_SPREAD_V) {
    resetRawPHCalibrationWindow();
    rawPHCalibrationBlocks[0] = voltage;
    rawPHCalibrationBlockMs[0] = now;
    rawPHCalibrationSamples = 1;
    rawPHCalibrationMinV = voltage;
    rawPHCalibrationMaxV = voltage;
    rawPHCalibrationSumV = voltage;
    rawPHCalibrationAverageV = voltage;
    return;
  }

  rawPHCalibrationAverageV = rawPHCalibrationSumV / rawPHCalibrationSamples;
  const bool fullWindow = rawPHCalibrationSamples >= CAL_PH_MIN_STABLE_BLOCKS &&
      now - rawPHCalibrationBlockMs[rawPHCalibrationHead] >= CAL_PH_STABLE_MS;
  rawPHCalibrationStable = fullWindow &&
      rawPHCalibrationMaxV - rawPHCalibrationMinV <= CAL_PH_STABLE_SPREAD_V;
}

void printCalibrationHelp() {
  Serial.println("\n=== CALIBRATION COMMANDS ===");
  Serial.println("CALMODE ON/OFF          Pause Wi-Fi/Firebase for calibration");
  Serial.println("CALSTREAM PH|DO|TURB [ms] PH FIT V uses live filter/rate (PH min 1000 ms)");
  Serial.println("raw on                  Optional online pH calibration stream (Firebase stays active)");
  Serial.println("CALSTOP / CALSTATUS     Stop stream / show calibration state");
  Serial.println("CALSHOW                 Show saved calibration values from NVM");
  Serial.println("phcal4 [force]          Save pH 4.01; force skips stability check");
  Serial.println("phcal9 9.18 [force]     Save pH 9.18; force skips stability check");
  Serial.println("phcal686 [force]        Save pH 6.86; force skips stability check");
  Serial.println("phmode 2|3              Select and apply 2-point or 3-point pH fit");
  Serial.println("phpair 9.18|6.86|6.86-9.18  Select a pair (also selects 2-point mode)");
  Serial.println("phfit                   Apply the selected pH fit mode");
  Serial.println("phrefit                 Alias for phfit / refit selected mode");
  Serial.println("phoffset                 Show correction status/magnitude");
  Serial.println("phoffset on|off          Activate/deactivate stored correction (default +1.50)");
  Serial.println("phoffset <value>         Set and activate correction (-3.00..3.00)");
  Serial.println("doread                   Show current DO voltage/value");
  Serial.println("doclear                  Calibrate DO in air-saturated water");
  Serial.println("turbclear [VOLTS]        Save stable clear-water voltage");
  Serial.println("turbdirty [VOLTS]        Save stable dirty-water voltage");
  Serial.println("turbair                  Deprecated; two-point mode does not use air calibration");
  Serial.println("feedempty                Save voltage with an empty hopper");
  Serial.println("feedfull                 Save voltage with a full hopper");
  Serial.println("hopperempty              Teach ultrasonic empty-hopper echo");
  Serial.println("hopperfull               Teach ultrasonic full-hopper echo");
  Serial.println("FEEDMODE <0|1>           0=analog GPIO39, 1=ultrasonic");
  Serial.println("hopperheight <cm>        Manual sensor-face to hopper-bottom distance");
  Serial.println("hopperdepth <cm>         Manual bottom-to-full-feed-surface depth");
  Serial.println("hoppercal                Show hopper geometry, echo, and fill reading");
  Serial.println("BUFSTATUS                Offline buffer backend + counts");
  Serial.println("tankheight <CM>          Manual sensor-face to tank-bottom distance");
  Serial.println("tankdepth <CM>           Bottom-to-target-full-water-surface depth");
  Serial.println("tankcal                  Show geometry, echo, and computed water depth");
  Serial.println("raw [on|off]             Raw snapshot / 1 s stream; FIT V is used by pH formula");
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

bool isPHCalibrationCommand(const String& cmd) {
  String lower = cmd;
  lower.toLowerCase();
  return lower == "phcal4" || lower == "phcal4 force" ||
      lower == "phcal7" || lower == "phcal686" ||
      lower == "phcal686 force" || lower == "phcal9" ||
      lower.startsWith("phcal9 ") || lower == "phfit" ||
      lower == "phrefit" || lower == "phpair" || lower.startsWith("phpair ") ||
      lower == "phmode" || lower.startsWith("phmode ") ||
      lower == "phoffset" || lower.startsWith("phoffset ");
}

bool isSensorCalibrationCommand(const String& cmd) {
  return isPHCalibrationCommand(cmd) || cmd == "doread" || cmd == "doclear" ||
      cmd == "turbclear" || cmd.startsWith("turbclear ") ||
      cmd == "turbdirty" || cmd.startsWith("turbdirty ");
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
  const float savedV686 = prefs.getFloat("phV686", -1.0f);
  const float v686 = savedV686 > 0.05f ? savedV686 :
      (fabsf(ref7 - 6.86f) < 0.01f ? v7 : -1.0f);
  const float v9 = prefs.getFloat("phV9", -1.0f);
  const float ref9 = prefs.getFloat("phV9Ref", 9.18f);
  const int pair = prefs.getInt("phPair", 9);
  prefs.end();
  const char* pairName = pair == 9 ? "4.01+9.18" :
      pair == 686 ? "4.01+6.86" :
      pair == 6869 ? "6.86+9.18" : "legacy/unknown";
  Serial.printf("[CAL NVM] pH4=%.4fV (ref %.2f), pH6.86=%.4fV, pH9.18=%.4fV (ref %.2f), selectedPair=%s, mode=%d-point, activeFit=%d-point, slope=%.5f intercept=%.5f outputOffset=%s%+.2f\n",
                v4, ref4, v686, v9, ref9, pairName, phFitMode, phFitPointCount,
                phVoltageSlope, phVoltageIntercept,
                phReadingOffsetEnabled ? "ON " : "OFF ", phReadingOffset);
  Serial.printf("[CAL NVM] DO scale=%.5f offset=%.5f | Turb clear=%.4f dirty=%.4f V mapping=%s (2-point)\n",
                doVoltageScale, doVoltageOffset, turbidityVClear,
                turbidityVDirty,
                turbidityCalibrationValid() ? "VALID" : "INVALID/INCOMPLETE");
}

bool applySavedPHFit(int requestedFitMode = -1) {
  if (!prefs.begin("sensorcal", true)) {
    Serial.println("[CAL NVM] Cannot read saved pH points.");
    return false;
  }
  const float v4 = prefs.getFloat("phV4", -1.0f);
  const float ref4 = prefs.getFloat("phV4Ref", 4.01f);
  const float v7 = prefs.getFloat("phV7", -1.0f);
  const float ref7 = prefs.getFloat("phV7Ref", 7.0f);
  const float savedV686 = prefs.getFloat("phV686", -1.0f);
  // Read older installations where phcal686 was stored in the legacy phV7 key.
  const float v686 = savedV686 > 0.05f ? savedV686 :
      (fabsf(ref7 - 6.86f) < 0.01f ? v7 : -1.0f);
  const float ref686 = prefs.getFloat("phV686Ref", 6.86f);
  const float v9 = prefs.getFloat("phV9", -1.0f);
  const float ref9 = prefs.getFloat("phV9Ref", 9.18f);
  const int pair = prefs.getInt("phPair", 9);
  const int savedFitMode = prefs.getInt("phFitMode", 2);
  prefs.end();

  const int fitMode = requestedFitMode == 2 || requestedFitMode == 3 ?
      requestedFitMode : (savedFitMode == 3 ? 3 : 2);

  float nextSlope = 0.0f;
  float nextIntercept = 0.0f;
  int nextFitPointCount = fitMode;
  float appliedSpan = 0.0f;
  bool endpointTwoPointFit = false;
  float fitV1 = 0.0f, fitPH1 = 0.0f, fitV2 = 0.0f, fitPH2 = 0.0f;
  const bool haveThreePoints = v4 > 0.05f && v4 <= 3.25f &&
      v686 > 0.05f && v686 <= 3.25f && v9 > 0.05f && v9 <= 3.25f &&
      isfinite(ref4) && isfinite(ref686) && isfinite(ref9) &&
      ref4 < ref686 && ref686 < ref9;
  const float totalSpan = max(v4, max(v686, v9)) - min(v4, min(v686, v9));

  if (fitMode == 3) {
    if (!haveThreePoints) {
      Serial.println("[CAL] 3-point fit needs saved valid pH 4.01, 6.86, and 9.18 values; previous fit retained.");
      return false;
    }
    const bool voltageMonotonic =
        (v4 < v686 && v686 < v9) || (v4 > v686 && v686 > v9);
    if (!voltageMonotonic || totalSpan <= 0.05f) {
      Serial.printf("[CAL] 3-point fit rejected: voltage points must be monotonic and span >50mV (current span %.1fmV). Previous fit retained.\n",
                    totalSpan * 1000.0f);
      return false;
    }
    const float meanV = (v4 + v686 + v9) / 3.0f;
    const float meanPH = (ref4 + ref686 + ref9) / 3.0f;
    const float numerator = (v4 - meanV) * (ref4 - meanPH) +
        (v686 - meanV) * (ref686 - meanPH) +
        (v9 - meanV) * (ref9 - meanPH);
    const float denominator = (v4 - meanV) * (v4 - meanV) +
        (v686 - meanV) * (v686 - meanV) +
        (v9 - meanV) * (v9 - meanV);
    if (denominator <= 0.0f) {
      Serial.println("[CAL] 3-point fit rejected: voltage points have no usable spread.");
      return false;
    }
    nextSlope = numerator / denominator;
    nextIntercept = meanPH - nextSlope * meanV;
    appliedSpan = totalSpan;
  } else if (pair == 9 || pair == 686 || pair == 6869) {
    // Apply exactly the two selected, saved buffer points.
    if (pair == 9) {
      fitV1 = v4; fitPH1 = ref4; fitV2 = v9; fitPH2 = ref9;
    } else if (pair == 686) {
      fitV1 = v4; fitPH1 = ref4; fitV2 = v686; fitPH2 = ref686;
    } else {
      fitV1 = v686; fitPH1 = ref686; fitV2 = v9; fitPH2 = ref9;
    }
    if (fitV1 <= 0.05f || fitV1 > 3.25f ||
        fitV2 <= 0.05f || fitV2 > 3.25f ||
        !isfinite(fitPH1) || !isfinite(fitPH2)) {
      Serial.printf("[CAL] Selected pH pair %s is incomplete; save both buffer points first.\n",
                    pair == 9 ? "4.01+9.18" : pair == 686 ? "4.01+6.86" : "6.86+9.18");
      return false;
    }
    const float voltageDelta = fitV2 - fitV1;
    appliedSpan = fabsf(voltageDelta);
    if (appliedSpan < 0.001f) {
      Serial.printf("[CAL] Selected pH points differ by only %.2fmV; cannot calculate a fit.\n",
                    appliedSpan * 1000.0f);
      return false;
    }
    nextSlope = (fitPH2 - fitPH1) / voltageDelta;
    nextIntercept = fitPH1 - nextSlope * fitV1;
    endpointTwoPointFit = true;
  } else {
    Serial.println("[CAL] No fit applied: selected two-point pair is invalid; previous fit retained.");
    return false;
  }

  const float oldSlope = phVoltageSlope;
  const float oldIntercept = phVoltageIntercept;
  const int oldFitPointCount = phFitPointCount;
  const int oldFitMode = phFitMode;
  phVoltageSlope = nextSlope;
  phVoltageIntercept = nextIntercept;
  phFitPointCount = nextFitPointCount;
  phFitMode = fitMode;
  if (!saveSensorCalibrations()) {
    phVoltageSlope = oldSlope;
    phVoltageIntercept = oldIntercept;
    phFitPointCount = oldFitPointCount;
    phFitMode = oldFitMode;
    Serial.println("[CAL NVM] Could not save the new pH fit; previous active fit retained.");
    return false;
  }
  if (endpointTwoPointFit) {
    const char* pairName = pair == 9 ? "4.01+9.18" :
        pair == 686 ? "4.01+6.86" : "6.86+9.18";
    Serial.printf("[CAL NVM] Applied 2-point pH %s fit: slope=%.5f intercept=%.5f; predictions=%.2f / %.2f; span=%.1fmV.\n",
                  pairName,
                  phVoltageSlope, phVoltageIntercept,
                  phVoltageSlope * fitV1 + phVoltageIntercept,
                  phVoltageSlope * fitV2 + phVoltageIntercept,
                  appliedSpan * 1000.0f);
  } else {
    Serial.printf("[CAL NVM] Applied 3-point pH fit (least-squares): slope=%.5f intercept=%.5f; predicted pH at saved V4/V6.86/V9.18 = %.2f / %.2f / %.2f.\n",
                  phVoltageSlope, phVoltageIntercept,
                  phVoltageSlope * v4 + phVoltageIntercept,
                  phVoltageSlope * v686 + phVoltageIntercept,
                  phVoltageSlope * v9 + phVoltageIntercept);
  }
  if (endpointTwoPointFit && appliedSpan < 0.05f) {
    Serial.printf("[CAL WARNING] Selected pH pair span is only %.1fmV; 10mV noise can shift pH by about %.2f. Fit saved, but verify carefully.\n",
                  appliedSpan * 1000.0f, fabsf(phVoltageSlope) * 0.010f);
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
      resetRawPHCalibrationWindow();
      sensorOutputEnabled = false;
      resetCalibrationStream();
      calibrationMode = true;
      // Wait for any in-progress background scan to finish before starting a
      // selected-pin stream; subsequent polling cycles see calibrationMode.
      {
        MutexGuard sensorLock(sensorStateMutex);
        resetLiveAverageWindowUnlocked(true);
      }
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
      {
        MutexGuard sensorLock(sensorStateMutex);
        resetLiveAverageWindowUnlocked(true);
      }
      calibrationMode = false;
      // Calibration time is excluded from sensor history; resume at the next
      // fixed wall-clock boundary after normal collection restarts.
      nextHistorySlotEndEpoch = 0;
      saveHistoryWindowCheckpoint();
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
        if (sensor == CAL_SENSOR_PH) {
          // Keep the median's time span comparable to live reads: the normal
          // pH polls every PH_SENSOR_POLL_MS after completing its batch.
          const uint16_t minPHBatchMs = max(
              (uint16_t)(SAMPLE_COUNT * SAMPLE_DELAY_MS),
              (uint16_t)PH_SENSOR_POLL_MS);
          if (interval < minPHBatchMs) {
            Serial.printf("[CAL] PH interval raised from %d to %u ms to match the live sensor polling cadence and complete its %u-sample batch.\n",
                          interval, minPHBatchMs, SAMPLE_COUNT);
            interval = minPHBatchMs;
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
        if (sensor == CAL_SENSOR_PH) {
          Serial.println("[CALRAW] ms,PH,rawV,FIT_V,fitWindowAvgV,fitMinV,fitMaxV,filterN,blocks,stable");
        } else {
          Serial.println("[CALRAW] ms,sensor,adc_avg,Vadc,blockMinAvgV,blockMaxAvgV,rawMinV,rawMaxV,n,blocks,stable");
        }
      }
    }
    cmd = "";
    return true;
  }
  return false;
}

bool calibrationCaptureReady(uint8_t sensor, bool force = false) {
  if (force) {
    if (sensor != CAL_SENSOR_PH) {
      Serial.println("[CAL] Force capture is currently supported for pH points only.");
      return false;
    }
    if (!calibrationMode && !rawStreamEnabled) {
      Serial.println("[CAL] Start raw on, or enter CALMODE ON and run CALSTREAM PH first.");
      return false;
    }
    if (calibrationMode && calibrationStreamSensor != CAL_SENSOR_PH) {
      Serial.println("[CAL] Select pH first: CALSTREAM PH");
      return false;
    }

    float capturedVoltage = 0.0f;
    if (!calibrationMode && rawPHCalibrationSamples > 0) {
      capturedVoltage = rawPHCalibrationAverageV;
    } else if (calibrationMode && calibrationBlockCount > 0) {
      capturedVoltage = calibrationStableVoltage;
    } else {
      MutexGuard sensorLock(sensorStateMutex);
      if (phVoltageSampleCount > 0) capturedVoltage = phFilteredVoltage;
    }
    if (!isfinite(capturedVoltage) || capturedVoltage <= 0.05f ||
        capturedVoltage > 3.25f) {
      Serial.println("[CAL] Force capture has no valid recent pH voltage; wait for at least one pH reading/block.");
      return false;
    }
    calibrationStableVoltage = capturedVoltage;
    Serial.printf("[CAL WARNING] FORCE CAPTURE: saving current pH average %.4fV without a stable-window guarantee. The fit may be inaccurate; verify in both buffers.\n",
                  capturedVoltage);
    if (!calibrationMode) {
      Serial.println("[CAL WARNING] CALMODE is OFF; Wi-Fi/Firebase remain active and may upload buffer readings.");
    }
    return true;
  }
  if (sensor == CAL_SENSOR_PH && !calibrationMode && rawStreamEnabled) {
    if (!rawPHCalibrationStable) {
      Serial.println("[CAL] Raw-mode pH window is not stable yet; keep raw on and wait for pHcal=STABLE (a full 60 s window within 10 mV).");
      return false;
    }
    calibrationStableVoltage = rawPHCalibrationAverageV;
    Serial.println("[CAL WARNING] CALMODE is OFF; Wi-Fi/Firebase remain active during this pH calibration.");
    return true;
  }
  if (!calibrationMode) {
    Serial.println("[CAL] For online pH calibration, start raw on and wait for pHcal=STABLE; otherwise use CALMODE ON.");
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
    return readPHVoltage();
  }
  return readAnalogVoltage(calibrationSensorPin(sensor));
}

void runCalibrationStream() {
  const uint8_t sensor = calibrationStreamSensor;
  if (!calibrationMode || sensor == CAL_SENSOR_NONE) return;
  unsigned long now = millis();
  float currentPHFitVoltage = 0.0f;
  bool newPHFitSample = false;

  if (sensor == CAL_SENSOR_PH) {
    // Match the live reader: one 50-sample eFuse-millivolt batch, then the
    // same five-sample median. CALSTREAM's requested cadence is clamped to
    // the time needed for this batch, so each printed block is a real sample.
    if (now - calibrationLastAdcMs >= calibrationStreamIntervalMs) {
      calibrationLastAdcMs = now;
      const float batchVoltage = analogVoltageForCalibration(CAL_SENSOR_PH);
      currentPHFitVoltage = updatePHFitVoltage(batchVoltage);
      now = millis();
      calibrationAdcCount = 1;
      calibrationMilliVoltSum = (uint32_t)lroundf(currentPHFitVoltage * 1000.0f);
      calibrationMilliVoltMin = calibrationMilliVoltMax =
          (uint16_t)lroundf(currentPHFitVoltage * 1000.0f);
      newPHFitSample = true;
    }
  } else if (now - calibrationLastAdcMs >= 2UL) {
    calibrationLastAdcMs = now;
    MutexGuard ioLock(sensorIoMutex);
    const uint16_t raw = analogRead(calibrationSensorPin(sensor));
    calibrationAdcSum += raw;
    calibrationAdcCount++;
    if (raw < calibrationAdcMin) calibrationAdcMin = raw;
    if (raw > calibrationAdcMax) calibrationAdcMax = raw;
  }
  if (sensor == CAL_SENSOR_PH) {
    if (!newPHFitSample) return;
    // The pH block itself is the current FIT V, already filtered by the same
    // five-reading median used by readPHSensor().
    calibrationStableVoltage = currentPHFitVoltage;
  } else if (now - calibrationLastPrintMs < calibrationStreamIntervalMs ||
             calibrationAdcCount == 0) {
    return;
  }

  const float adcAvg = sensor == CAL_SENSOR_PH ? 0.0f :
      (float)calibrationAdcSum / calibrationAdcCount;
  const float avgV = sensor == CAL_SENSOR_PH ? currentPHFitVoltage :
      adcAvg * (3.3f / 4095.0f);
  const float rawMinV = sensor == CAL_SENSOR_PH ? phVoltage :
      calibrationAdcMin * (3.3f / 4095.0f);
  const float rawMaxV = sensor == CAL_SENSOR_PH ? phVoltage :
      calibrationAdcMax * (3.3f / 4095.0f);

  // Judge calibration stability from block averages, never raw ADC extrema.
  // pH requires a full 60 s of filtered FIT_V blocks within 10 mV; DO and
  // turbidity retain their existing time-based windows.
  if (calibrationBlockCount == CAL_STABLE_MAX_BLOCKS) {
    calibrationBlockHead = (calibrationBlockHead + 1) % CAL_STABLE_MAX_BLOCKS;
    calibrationBlockCount--;
  }
  const uint16_t tail = (calibrationBlockHead + calibrationBlockCount) % CAL_STABLE_MAX_BLOCKS;
  const bool phFilterReady = sensor != CAL_SENSOR_PH ||
      phVoltageSampleCount == SENSOR_FILTER_WINDOW;
  if (phFilterReady) {
    calibrationBlockAvgVoltage[tail] = avgV;
    calibrationBlockMs[tail] = now;
    calibrationBlockCount++;
  } else {
    // Ignore the median's warm-up values; they are not full live-equivalent
    // pH blocks and must not count toward a saved calibration point.
    calibrationBlockHead = 0;
    calibrationBlockCount = 0;
  }

  const unsigned long stableWindowMs = calibrationStableWindowMs(sensor);
  if (sensor == CAL_SENSOR_PH && calibrationBlockCount > 1) {
    float candidateMin = avgV;
    float candidateMax = avgV;
    for (uint16_t i = 0; i < calibrationBlockCount; ++i) {
      const uint16_t index = (calibrationBlockHead + i) % CAL_STABLE_MAX_BLOCKS;
      candidateMin = min(candidateMin, calibrationBlockAvgVoltage[index]);
      candidateMax = max(candidateMax, calibrationBlockAvgVoltage[index]);
    }
    if (candidateMax - candidateMin > calibrationStableSpreadV(sensor)) {
      // A block outside the allowed span breaks consecutiveness. Start again
      // from this newest filtered block.
      calibrationBlockHead = tail;
      calibrationBlockCount = 1;
    }
  }
  // Keep at least one sample >= the complete stability window old. Drop it
  // only when the next-oldest sample also preserves that full window.
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
  const bool enoughPHBlocks = sensor != CAL_SENSOR_PH ||
      calibrationBlockCount >= CAL_PH_MIN_STABLE_BLOCKS;
  const bool fullStabilityWindow = enoughPHBlocks && calibrationBlockCount > 1 &&
      now - calibrationBlockMs[calibrationBlockHead] >= stableWindowMs;
  float blockSum = 0.0f;
  calibrationStable = phFilterReady && fullStabilityWindow &&
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
  if (sensor == CAL_SENSOR_PH) {
    Serial.printf("[CALRAW] %lu,PH,rawV=%.4f,FIT_V=%.4f,fitWindowAvgV=%.4f,fitMinV=%.4f,fitMaxV=%.4f,filterN=%u,blocks=%u,stable=%s\n",
                  now, phVoltage, currentPHFitVoltage, calibrationStableVoltage,
                  calibrationStableMinVoltage, calibrationStableMaxVoltage,
                  phVoltageSampleCount, calibrationBlockCount,
                  calibrationStable ? "YES" : "NO");
  } else {
    Serial.printf("[CALRAW] %lu,%s,%.1f,%.4f,%.4f,%.4f,%.4f,%.4f,%u,%u,%s\n",
                  now, calibrationSensorName(sensor), adcAvg, avgV,
                  calibrationStableMinVoltage, calibrationStableMaxVoltage,
                  rawMinV, rawMaxV, calibrationAdcCount, calibrationBlockCount,
                  calibrationStable ? "YES" : "NO");
  }
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
  Serial.println("SENSOR_ON                Print readings every 5 seconds");
  Serial.println("SENSOR_OFF               Stop periodic sensor printing");
  Serial.println("SENSOR_READ              Take and print one fresh reading");
  Serial.println("CAL_HELP                 Show calibration commands");
  Serial.println("CALMODE ON/OFF           Pause Wi-Fi/Firebase during sensor calibration");
  Serial.println("CALSTREAM PH|DO|TURB [ms] Stream selected ADC (20-2000 ms)");
  Serial.println("raw on / raw off         Stream readings; raw mode permits online pH calibration");
  Serial.println("WIFI_HELP                Show Wi-Fi commands");
  Serial.println("SYSTEM_MODE AUTO|ONLINE|OFFLINE  Select cloud/local operating mode (NVS)");
  Serial.println("GATE_PAUSE <0-60>        Closed pause after each swing, seconds (NVS)");
  Serial.println("FIREBASE_STATUS          Show cloud authentication status");
  Serial.println("FEED                     Start a 1 g manual feed");
  Serial.println("GATE_TEST                One gate actuation (GPIO5 SG90)");
  Serial.println("GATECAL                  10 actuations for weighing (~10 g)");
  Serial.println("GATE_ANGLE <10-180>      Gate open angle (NVS)");
  Serial.println("GATE_CLOSE_ANGLE <0-180> Calibrate/save close angle; required before feeding");
  Serial.println("GATE_MS <100-5000>       Gate hold ms (NVS)");
  Serial.println("GPIO13 button            Onsite feed: taps = grams (1-200)");
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
void updateSystemCloudMode();
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
bool reserveFeedNowCommand(const String& commandId, const String& tankId, float grams);
bool storePendingFeedNowLog(const String& tankId, const String& logId, const String& payload);
bool flushPendingFeedNowLog();
bool storePendingLocalFeedLog(const String& tankId, const String& eventKey, const String& envelope);
bool clearPendingLocalFeedLog(const String& eventKey);
bool hasPendingLocalFeedLog(const String& eventKey);
bool hasPendingFeederRecovery(const String& eventKey);
bool flushPendingLocalFeedLog();
bool queuePendingLocalFeedLogOffline();
bool queueFeederLogEnvelope(const String& eventKey, const String& envelope, bool pending);
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
  if (!loadRuntimeSettings()) {
    Serial.println("[SYSTEM] Runtime settings unavailable; using AUTO mode and 1 s gate pause.");
  }
  Serial.printf("[SYSTEM] Requested mode=%s | gate closed pause=%lu s\n",
                systemModeName(), gateCloseDwellMs / 1000UL);

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
  // Rebuild the NVS-selected pH fit at boot so the chosen two/three-point
  // mode and its saved calibration points become active after reset.
  if (prefs.begin("sensorcal", true)) {
    const int savedPHFitMode = prefs.getInt("phFitMode", 2);
    prefs.end();
    if (savedPHFitMode == 2 || savedPHFitMode == 3) {
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
  loadHistoryWindowCheckpoint();
  queuePendingHistoryIfPossible();
  initBlower();
  initBlowerButton();
  // Larger read side for Firestore payloads: fewer -6 payload timeouts.
  fbdo.setResponseSize(8192);
  fbdo.setBSSLBufferSize(4096, 2048);
  if (WiFi.status() == WL_CONNECTED && !cloudModeForcedOffline()) {
    initTime();
    { time_t st; time(&st); if (st > 1700000000) {
        ntpEverSynced = true;
        feederBootEpoch = st;
        lastNtpSyncMs = millis();
      } }
    showLCDBootProgress("Starting cloud", 0);
    connectFirebase();
    lcdCloudBootPending = true;
    lcdCloudBootStartedMs = millis();
  } else if (cloudModeForcedOffline()) {
    showLCDBoot("System offline", "Cloud paused", 1300);
    Serial.println("[CLOUD] Forced OFFLINE mode — Wi-Fi may stay connected, but Firebase/assignment operations are paused.");
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
  // Suppress boot-time transients before accepting physical feed-button taps.
  beginOnsiteButtonLockout(ONSITE_BOOT_LOCKOUT_US);
  portENTER_CRITICAL(&onsiteButtonMux);
  onsiteButtonEnabled = true;
  portEXIT_CRITICAL(&onsiteButtonMux);
  Serial.println("[BUTTON] Onsite feed locked out for 15 s after startup");
  if (!lcdCloudBootPending) {
    showLCDBoot("CrayCare ready", "Local mode", 1200);
  }

  {
    MutexGuard sensorLock(sensorStateMutex);
    resetLiveAverageWindowUnlocked(true);
  }

  if (sensorStateMutex && sensorIoMutex &&
      xTaskCreatePinnedToCore(sensorPollingTask, "sensor_poll", 8192, nullptr,
                              2, nullptr, 1) == pdPASS) {
    sensorTaskRunning = true;
    Serial.println("[SENSOR] Background polling started (non-pH=2 s, pH=1 s; live average window=5 s)");
  } else {
    Serial.println("[SENSOR] Background task unavailable; polling in main loop");
  }

  if (lcdReady && lcdMutex && feederScheduleMutex &&
      xTaskCreatePinnedToCore(lcdDisplayTask, "lcd_display", 6144, nullptr,
                              1, nullptr, 1) == pdPASS) {
    lcdTaskRunning = true;
    Serial.println("[LCD] Background display task started (5 s page rotation; averaged sensor values)");
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
    const unsigned long checkpointNow = millis();
    if (checkpointNow - lastHistoryCheckpointMs >= 60000UL) {
      lastHistoryCheckpointMs = checkpointNow;
      saveHistoryWindowCheckpoint();
    }
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
      } else if (!calibrationMode && isSensorCalibrationCommand(cmd) &&
                 !(rawStreamEnabled && isPHCalibrationCommand(cmd))) {
        Serial.println("[CAL] Enter CALMODE ON first so Firebase/Wi-Fi are paused during calibration.");
        cmd = "";
      }
    }
    if (cmd == "HELP" || cmd == "help" || cmd == "?") {
      printSerialHelp();
    }
    {
      String modeCmd = cmd;
      modeCmd.trim();
      modeCmd.toUpperCase();
      if (modeCmd == "SYSTEM_MODE" || modeCmd == "MODE") {
        Serial.printf("[SYSTEM] Requested mode=%s | cloud active=%s | tank=%s\n",
                      systemModeName(), systemCloudModeActive ? "YES" : "NO",
                      currentTankId.isEmpty() ? "(none)" : currentTankId.c_str());
      } else if (modeCmd.startsWith("SYSTEM_MODE ") || modeCmd.startsWith("MODE ")) {
        const int split = modeCmd.indexOf(' ');
        String requested = modeCmd.substring(split + 1);
        requested.trim();
        SystemModeOverride nextMode;
        if (requested == "AUTO") nextMode = SYSTEM_MODE_AUTO;
        else if (requested == "ONLINE") nextMode = SYSTEM_MODE_FORCE_ONLINE;
        else if (requested == "OFFLINE") nextMode = SYSTEM_MODE_FORCE_OFFLINE;
        else {
          Serial.println("Usage: SYSTEM_MODE AUTO|ONLINE|OFFLINE");
          nextMode = systemModeOverride;
        }
        if (requested == "AUTO" || requested == "ONLINE" || requested == "OFFLINE") {
          const SystemModeOverride previousMode = systemModeOverride;
          systemModeOverride = nextMode;
          if (saveSystemMode(systemModeOverride)) {
            systemCloudModeInitialized = false;
            if (cloudModeForcedOffline()) firebaseReady = false;
            updateSystemCloudMode();
            Serial.printf("[SYSTEM] Mode saved: %s. %s\n", systemModeName(),
                cloudModeForcedOffline()
                    ? "Firebase operations paused; local sensing/feed and buffers continue."
                    : "Cloud operations enabled when Wi-Fi, Firebase, and a valid tank assignment are available.");
          } else {
            systemModeOverride = previousMode;
            Serial.println("[SYSTEM] Could not save mode in NVS; previous mode kept.");
          }
        }
      }
    }
    if (cmd.startsWith("GATE_PAUSE ") || cmd.startsWith("gate_pause ")) {
      const String valueText = cmd.substring(cmd.lastIndexOf(' ') + 1);
      char* end = nullptr;
      const long seconds = strtol(valueText.c_str(), &end, 10);
      if (end == valueText.c_str() || *end != '\0' || seconds < 0 || seconds > 60) {
        Serial.println("Usage: GATE_PAUSE <0-60> (whole seconds; saved in NVS)");
      } else {
        const unsigned long previousDwell = gateCloseDwellMs;
        gateCloseDwellMs = (unsigned long)seconds * 1000UL;
        if (saveRuntimeSetting("gateDwell", gateCloseDwellMs)) {
          Serial.printf("[GATE] Closed pause saved: %lu second(s); used after every swing, including GATECAL.\n",
                        seconds);
        } else {
          gateCloseDwellMs = previousDwell;
          Serial.println("[GATE] Could not save pause in NVS; previous value kept.");
        }
      }
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
      printSensorReading(false);
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
        if (feederBootEpoch == 0) feederBootEpoch = nt2;
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
      } else if (!gateCloseAngleConfigured) {
        Serial.println("[GATE] Set the real closed position first: GATE_CLOSE_ANGLE <degrees>");
      } else {
        Serial.printf("[GATE] Test: one actuation %d -> %d -> %d\n", gateCloseAngle,
                      gateOpenAngle, gateCloseAngle);
        setGateAngle(gateOpenAngle);
        delay(gateHoldMs);
        setGateAngle(gateCloseAngle);
        delay(gateCloseDwellMs);
        Serial.printf("[GATE] Test complete (closed pause: %lu s)\n", gateCloseDwellMs / 1000UL);
      }
    }
    if (cmd == "GATECAL" || cmd == "gatecal") {
      if (feederRunState != FEEDER_IDLE) {
        Serial.println("[GATE] Feeder busy — try after the feed finishes");
      } else if (!gateCloseAngleConfigured) {
        Serial.println("[GATE] Set the real closed position first: GATE_CLOSE_ANGLE <degrees>");
      } else {
        Serial.printf("[GATE] Calibration: 10 actuations; gate stays closed for %lu ms after each swing. Catch and weigh the output.\n",
                      gateCloseDwellMs);
        Serial.println("[GATE] Target ~10 g total (1 g each). If off, adjust with");
        Serial.println("[GATE] GATE_ANGLE / GATE_MS and repeat until 10 actuations = ~10 g.");
        for (int i = 0; i < 10; i++) {
          setGateAngle(gateOpenAngle);
          delay(gateHoldMs);
          setGateAngle(gateCloseAngle);
          delay(gateCloseDwellMs);
          esp_task_wdt_reset();  // 10 cycles x (hold + dwell) exceeds short timeouts
          Serial.printf("[GATE] Actuation %d/10\n", i + 1);
        }
        Serial.println("[GATE] Done — weigh total (expect ~10 g for the 1 g-only model)");
      }
    }
    if (cmd.startsWith("GATE_ANGLE ") || cmd.startsWith("gate_angle ")) {
      int v = cmd.substring(cmd.lastIndexOf(' ') + 1).toInt();
      if (v < 10 || v > GATE_MAX_ANGLE || abs(v - gateCloseAngle) < 10) {
        Serial.println("Usage: GATE_ANGLE <10-180>");
        if (abs(v - gateCloseAngle) < 10)
          Serial.println("[GATE] Open and close angles must differ by at least 10 degrees.");
      } else {
        gateOpenAngle = v;
        saveSensorCalibrations();
        Serial.printf("[GATE] Open angle %d saved\n", gateOpenAngle);
      }
    }
    if (cmd.startsWith("GATE_CLOSE_ANGLE ") || cmd.startsWith("gate_close_angle ")) {
      int v = cmd.substring(cmd.lastIndexOf(' ') + 1).toInt();
      if (v < 0 || v > GATE_MAX_ANGLE || abs(v - gateOpenAngle) < 10) {
        Serial.println("Usage: GATE_CLOSE_ANGLE <0-180>; must differ from open angle by at least 10 degrees.");
      } else if (feederRunState != FEEDER_IDLE) {
        Serial.println("[GATE] Feeder busy — set close angle after feed finishes.");
      } else {
        const int previousAngle = gateCloseAngle;
        const bool wasConfigured = gateCloseAngleConfigured;
        gateCloseAngle = v;
        gateCloseAngleConfigured = true;
        if (saveSensorCalibrations()) {
          setGateAngle(gateCloseAngle);
          Serial.printf("[GATE] Close angle %d saved and commanded.\n", gateCloseAngle);
        } else {
          gateCloseAngle = previousAngle;
          gateCloseAngleConfigured = wasConfigured;
          Serial.println("[GATE] Save failed; close angle may not persist after reboot.");
        }
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
        Serial.printf("[CAL] Tank sensor-face to bottom = %.1f cm saved to NVS.\n", v);
      } else {
        Serial.println("Usage: tankheight <5-400> cm (sensor face to tank bottom)");
      }
    }
    if (cmd.startsWith("tankdepth ")) {
      const float v = cmd.substring(10).toFloat();
      if (v > 1.0f && v < waterSensorHeightCm) {
        waterLevelCmMax = v;
        saveSensorCalibrations();
        Serial.printf("[CAL] Tank bottom to target full-water surface = %.1f cm saved to NVS.\n", v);
      } else {
        Serial.printf("Usage: tankdepth <1-%.1f> cm (tank bottom to target water surface)\n",
                      waterSensorHeightCm);
      }
    }
    if (cmd == "tankcal") {
      const float computedDepth = waterDistanceCm >= 0.0f
          ? waterSensorHeightCm - waterDistanceCm : -1.0f;
      Serial.printf("[CAL] Tank sensor->bottom=%.2fcm; bottom->target surface=%.2fcm; latest sensor->surface echo=%.2fcm; computed water depth=%.2fcm\n",
                    waterSensorHeightCm, waterLevelCmMax, waterDistanceCm,
                    computedDepth);
    }
    if (cmd == "hoppercal") {
      Serial.printf("[CAL] Hopper sensor->bottom/empty echo=%.2fcm; bottom->target full-feed surface=%.2fcm; derived full echo=%.2fcm; latest echo=%.2fcm; fill=%.1f%% (%s)\n",
                    hopperEmptyCm,
                    hopperEmptyCm >= 0.0f && hopperFullCm >= 0.0f
                        ? hopperEmptyCm - hopperFullCm : -1.0f,
                    hopperFullCm, hopperDistanceCm, feedLevelPercent,
                    feedLevelSource);
    }
    String phCalibrationCommand = cmd;
    phCalibrationCommand.toLowerCase();
    if (phCalibrationCommand == "phcal7" || phCalibrationCommand == "phcal686" ||
        phCalibrationCommand == "phcal686 force" || phCalibrationCommand == "phcal4" ||
        phCalibrationCommand == "phcal4 force" || phCalibrationCommand == "phcal9" ||
        phCalibrationCommand.startsWith("phcal9 ")) {
      bool forceCapture = false;
      if (phCalibrationCommand.endsWith(" force")) {
        forceCapture = true;
        phCalibrationCommand.remove(phCalibrationCommand.length() - 6);
        phCalibrationCommand.trim();
      }
      const bool isNeutral = phCalibrationCommand == "phcal7" ||
          phCalibrationCommand == "phcal686";
      const float neutralReference = phCalibrationCommand == "phcal686" ? 6.86f : 7.00f;
      const bool isPH686 = phCalibrationCommand == "phcal686";
      const bool isNine = phCalibrationCommand == "phcal9" ||
          phCalibrationCommand.startsWith("phcal9 ");
      float nineReference = 9.18f;
      if (phCalibrationCommand.startsWith("phcal9 ")) {
        String valueText = phCalibrationCommand.substring(7);
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
      if (!calibrationCaptureReady(CAL_SENSOR_PH, forceCapture)) return;
      const float v = calibrationStableVoltage;
      if (v <= 0.05f || v > 3.25f) {
        Serial.printf("[CAL] pH point rejected: stable-window voltage %.4fV is outside ADC range.\n", v);
        return;
      }
      if (!prefs.begin("sensorcal", false)) {
        Serial.println("[CAL NVM] Could not open sensor calibration storage; pH point not saved.");
        return;
      }
      const char* pointKey = isPH686 ? "phV686" :
          isNeutral ? "phV7" : isNine ? "phV9" : "phV4";
      bool pointSaved = prefs.putFloat(pointKey, v) == sizeof(float);
      if (phCalibrationCommand == "phcal4") prefs.putFloat("phV4Ref", 4.01f);
      if (isNeutral && !isPH686) prefs.putFloat("phV7Ref", neutralReference);
      if (isPH686) prefs.putFloat("phV686Ref", 6.86f);
      if (isNine) {
        prefs.putFloat("phV9Ref", nineReference);
        if (prefs.getInt("phPair", 9) != 6869) prefs.putInt("phPair", 9);
      } else if (isPH686) {
        if (prefs.getInt("phPair", 9) != 6869) prefs.putInt("phPair", 686);
      }
      pointSaved &= prefs.getFloat(pointKey, -1.0f) == v;
      prefs.end();
      if (!pointSaved) {
        Serial.println("[CAL NVM] pH calibration point write failed; check NVS and retry.");
        return;
      }
      Serial.printf("[CAL NVM] Saved %s pH average %.4fV for %s; attempting fit from saved buffer points.\n",
                    forceCapture ? "FORCED" : "stable", v,
                    phCalibrationCommand.c_str());
      applySavedPHFit();
    }
    if (cmd == "phmode" || cmd.startsWith("phmode ")) {
      if (!calibrationMode && !rawStreamEnabled) {
        Serial.println("[CAL] Start raw on first, or enter CALMODE ON.");
      } else {
        String requestedMode = cmd == "phmode" ? "" : cmd.substring(7);
        requestedMode.trim();
        if (requestedMode.length() == 0) {
          Serial.printf("[CAL] Selected pH fit mode: %d-point; active fit: %d-point. Use phmode 2 or phmode 3.\n",
                        phFitMode, phFitPointCount);
        } else if (requestedMode == "2" || requestedMode == "3") {
          const int mode = requestedMode.toInt();
          Serial.printf("[CAL] Activating %d-point pH fit from saved calibration points.\n", mode);
          if (applySavedPHFit(mode)) {
            Serial.printf("[CAL] pH %d-point mode is active and saved in NVS.\n", mode);
          } else {
            Serial.printf("[CAL] pH %d-point mode was not activated; previous fit remains active.\n", mode);
          }
        } else {
          Serial.println("Usage: phmode 2 | phmode 3");
        }
      }
    }
    if (cmd == "phpair" || cmd.startsWith("phpair ")) {
      if (!calibrationMode && !rawStreamEnabled) {
        Serial.println("[CAL] Start raw on first, or enter CALMODE ON.");
      } else {
        String requestedPair = cmd == "phpair" ? "" : cmd.substring(7);
        requestedPair.trim();
        int pair = 0;
        if (requestedPair == "9.18" || requestedPair == "9") pair = 9;
        else if (requestedPair == "6.86") pair = 686;
        else if (requestedPair == "6.86-9.18" || requestedPair == "6.86 9.18" ||
                 requestedPair == "686-918") pair = 6869;
        if (pair == 0) {
          Serial.println("Usage: phpair 9.18 | phpair 6.86 | phpair 6.86-9.18");
        } else if (!prefs.begin("sensorcal", false)) {
          Serial.println("[CAL NVM] Could not save selected pH calibration pair.");
        } else {
          const bool saved = prefs.putInt("phPair", pair) == sizeof(int32_t);
          prefs.end();
          if (!saved) {
            Serial.println("[CAL NVM] Selected pH pair was not saved.");
          } else {
            const char* pairName = pair == 9 ? "4.01 + 9.18" :
                pair == 686 ? "4.01 + 6.86" : "6.86 + 9.18";
            Serial.printf("[CAL NVM] Selected 2-point pair: pH %s. Running fit from saved points.\n",
                          pairName);
            applySavedPHFit(2);
          }
        }
      }
    }
    if (cmd == "phrefit" || cmd == "phfit") {
      if (!calibrationMode && !rawStreamEnabled) {
        Serial.println("[CAL] Start raw on first, or enter CALMODE ON.");
      } else {
        applySavedPHFit();
      }
    }
    if (cmd == "phoffset" || cmd.startsWith("phoffset ")) {
      String offsetText = cmd == "phoffset" ? "" : cmd.substring(9);
      offsetText.trim();
      if (offsetText.length() == 0) {
        Serial.printf("[PH] Output correction %s (%+.2f pH). Use phoffset on|off or phoffset <value>.\n",
                      phReadingOffsetEnabled ? "ON" : "OFF", phReadingOffset);
      } else if (offsetText == "on" || offsetText == "off") {
        const bool enableOffset = offsetText == "on";
        if (!prefs.begin("sensorcal", false)) {
          Serial.println("[PH] Could not open NVS; correction activation was not changed.");
        } else {
          const bool saved = prefs.putBool("phOffOn", enableOffset);
          prefs.end();
          if (saved) {
            phReadingOffsetEnabled = enableOffset;
            Serial.printf("[PH] Output correction %s; stored magnitude is %+.2f pH.\n",
                          phReadingOffsetEnabled ? "ON" : "OFF", phReadingOffset);
          } else {
            Serial.println("[PH] NVS write failed; previous activation state retained.");
          }
        }
      } else {
        char* end = nullptr;
        const float requestedOffset = strtof(offsetText.c_str(), &end);
        if (end == offsetText.c_str() || *end != '\0' ||
            !isfinite(requestedOffset) || requestedOffset < -3.0f ||
            requestedOffset > 3.0f) {
          Serial.println("[PH] Invalid correction. Use a value from -3.00 to 3.00 pH.");
        } else if (!prefs.begin("sensorcal", false)) {
          Serial.println("[PH] Could not open NVS; correction was not changed.");
        } else {
          bool saved = prefs.putFloat("phOffset", requestedOffset) == sizeof(float);
          saved &= prefs.putBool("phOffOn", requestedOffset != 0.0f);
          prefs.end();
          if (saved) {
            phReadingOffset = requestedOffset;
            phReadingOffsetEnabled = requestedOffset != 0.0f;
            Serial.printf("[PH] Saved correction %+.2f pH; activation %s. The 2-point fit is unchanged.\n",
                          phReadingOffset,
                          phReadingOffsetEnabled ? "ON" : "OFF");
          } else {
            Serial.println("[PH] NVS write failed; previous correction retained.");
          }
        }
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
      Serial.printf("[CAL NVM] Clear-water point saved: %.4fV. Two-point mapping %s.\n", v,
                    turbidityCalibrationValid() ? "VALID" : "incomplete; save a distinct dirty-water point");
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
      Serial.printf("[CAL NVM] Dirty-water point saved: %.4fV. Two-point mapping %s.\n", v,
                    turbidityCalibrationValid() ? "VALID" : "incomplete; save a distinct clear-water point");
    }
    if (cmd == "turbair" || cmd.startsWith("turbair ")) {
      Serial.println("[CAL] turbair is not used in two-point mode. Save turbclear and turbdirty only.");
      Serial.println("[CAL] Two-point mapping cannot independently identify a dry probe if its voltage overlaps the water range.");
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
        Serial.printf("[CAL] Hopper sensor-face to floor = %.1f cm (empty echo) saved to NVS.\n", v);
      } else {
        Serial.println("Usage: hopperheight <5-200> cm (sensor face to hopper floor)");
      }
    }
    if (cmd.startsWith("hopperdepth ")) {
      const float v = cmd.substring(12).toFloat();
      if (v > 1.0f && v < hopperEmptyCm) {
        hopperFullCm = hopperEmptyCm - v;
        saveSensorCalibrations();
        Serial.printf("[CAL] Hopper floor to target full-feed surface = %.1f cm (derived full echo %.1f cm), saved to NVS.\n",
                      v, hopperFullCm);
      } else {
        Serial.printf("Usage: hopperdepth <1-%.1f> cm (floor to target full-feed surface)\n",
                      hopperEmptyCm);
      }
    }
    if (cmd == "raw") {
      printRawReading();
    }
    if (cmd == "raw on" || cmd == "raw stream") {
      rawStreamEnabled = true;
      resetRawPHCalibrationWindow();
      lastRawStreamMs = 0;  // stream prints on the next loop pass
      Serial.println("[RAW] Stream ON (1 s, 'raw off' to stop); pH calibration needs a full 60 s FIT_V window within 10 mV. Wi-Fi/Firebase remain active.");
      printRawReading();
    }
    if (cmd == "raw off" || cmd == "raw stop") {
      rawStreamEnabled = false;
      resetRawPHCalibrationWindow();
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
  const bool wifiConnected = WiFi.status() == WL_CONNECTED;
  const bool networkAvailable = wifiConnected && !cloudModeForcedOffline();
  if (!wifiConnected && now - lastWifiReconnectTime >= 10000UL) {
    lastWifiReconnectTime = now;
    if (sensorOutputEnabled) {
      Serial.println("[WIFI] Offline — local sensing/automation continues; reconnecting...");
    }
    WiFi.reconnect();
  }

  // If a local feed was interrupted before its terminal event could be
  // recorded, move its NVS recovery marker to the offline queue while the
  // feeder is idle. Never touch an in-progress feed's marker.
  if (feederRunState == FEEDER_IDLE && (!networkAvailable || !firebaseReady || cloudOutage)) {
    queuePendingLocalFeedLogOffline();
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
    if (nt > 1700000000) {
      ntpEverSynced = true;
      if (feederBootEpoch == 0) feederBootEpoch = nt;
    }
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
    if (hasCurrentTankAssignment()) {
      syncConfigFromFirebase();
      syncFeederSchedules();
    }
    cloudBootstrapComplete = true;
    updateSystemCloudMode();
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
    const bool haveAssignment = hasCurrentTankAssignment();
    const unsigned long assignInterval =
        haveAssignment ? ASSIGNMENT_RECHECK_MS : ASSIGNMENT_SEARCH_MS;
    if (networkAvailable && now - lastAssignmentCheckMs >= assignInterval) {
      String prevTank = currentTankId;
      String prevOwner = currentOwnerUid;
      const long long prevAssignedAt = currentAssignmentAtMs;
      fetchTankId();
      lastAssignmentCheckMs = millis();
      now = lastAssignmentCheckMs;
      // Any assignment identity transition invalidates cached tank settings
      // and schedules; re-sync them immediately when a valid assignment returns.
      if (currentTankId != prevTank || currentOwnerUid != prevOwner ||
          currentAssignmentAtMs != prevAssignedAt) {
        lastConfigSyncTime = now - CONFIG_SYNC_INTERVAL_MS;
        lastFeederScheduleSyncMs = now - FEEDER_SCHEDULE_SYNC_MS;
      }
    }
  }
  updateSystemCloudMode();

  // ─── Sensors + live Latest (first: the realtime path never queues) ───

  if (!sensorTaskRunning && !calibrationMode) {
    if (now - lastNonPhPollTime >= NON_PH_SENSOR_POLL_MS) {
      const unsigned long scanStartedMs = now;
      lastNonPhPollTime = scanStartedMs;
      readNonPHSensors();
      now = millis();
      if (now - scanStartedMs >= NON_PH_SENSOR_POLL_MS) {
        lastNonPhPollTime = now;  // Long scan: wait a full interval, no catch-up.
      }
    }
    if (now - lastPhPollTime >= PH_SENSOR_POLL_MS) {
      const unsigned long scanStartedMs = now;
      lastPhPollTime = scanStartedMs;
      readPHSensorSafely();
      now = millis();
      if (now - scanStartedMs >= PH_SENSOR_POLL_MS) {
        lastPhPollTime = now;
      }
    }
    if (publishLiveAverageWindow() && sensorOutputEnabled) printSensorReading();
  }

  // Continuous raw-voltage stream for calibration stability checks
  // (`raw on` / `raw off`). Reuses cached values; zero extra ADC load.
  if (rawStreamEnabled && now - lastRawStreamMs >= 1000UL) {
    lastRawStreamMs = now;
    updateRawPHCalibrationWindow();
    printRawReading();
  }

  if (networkAvailable && hasCurrentTankAssignment() &&
      now - lastFirebaseSendTime >= FIREBASE_SEND_INTERVAL_MS) {
    // Firestore is synchronous, so maintain at least a 10-second interval
    // between attempts. A slow request coalesces missed intervals; never
    // queue catch-up writes. Sensor and LCD tasks continue during the request.
    // ESP supplies the capture-time recorded_at Timestamp; Functions normalize
    // legacy staged events before routing them into canonical sensor records.
    // Whether this succeeds or fails, wait for the next normal slot. Immediate
    // retries amplify weak-link TLS failures and can exhaust the SSL layer.
    sendLatestToFirestore();
    lastFirebaseSendTime = millis();
    now = lastFirebaseSendTime;
  }

  // Outage probe: the ONLY network call allowed in outage mode. A single
  // attempt (no retry); success clears the outage via reportCloudResult and
  // normal ops resume. Everything else stays fail-fast until then.
  if (networkAvailable && cloudOutage && now - lastOutageProbeMs >= OUTAGE_PROBE_MS) {
    lastOutageProbeMs = now;
    bool probeOk = Firebase.Firestore.getDocument(&fbdo, FIREBASE_PROJECT_ID, "",
                                                  "hardware_system/currentOwner");
    reportCloudResult(probeOk);
    now = millis();
  }

  // ─── Feeder ───
  // Observe assignment changes before consuming commands or running a plan.
  if (networkAvailable && hasCurrentTankAssignment() &&
      now - lastConfigSyncTime >= CONFIG_SYNC_INTERVAL_MS) {
    syncConfigFromFirebase();
    lastConfigSyncTime = millis();
    now = lastConfigSyncTime;
  }
  // Cloud commands/status/schedule refresh need network. Already-synced
  // schedules continue to execute locally below while offline.
  if (networkAvailable && hasCurrentTankAssignment() &&
      now - lastFeederCmdCheckMs >= FEEDER_CMD_INTERVAL_MS) {
    processFeederCommands();
    lastFeederCmdCheckMs = millis();
    now = lastFeederCmdCheckMs;
    if (feederRunState != FEEDER_IDLE) return;
  }

  if (networkAvailable && hasCurrentTankAssignment() &&
      now - lastFeederStatusMs >= FEEDER_STATUS_INTERVAL_MS) {
    sendFeederStatus();
    lastFeederStatusMs = millis();
    now = lastFeederStatusMs;
  }

  if (networkAvailable && hasCurrentTankAssignment() &&
      now - lastFeederScheduleSyncMs >= FEEDER_SCHEDULE_SYNC_MS) {
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

  // History windows follow fixed wall-clock boundaries (00, 10, 20, ...).
  // Epoch boundaries align with Manila time because UTC+8 is a whole number
  // of 10-minute intervals. If processing is a few minutes late, keep the
  // original slot end in recorded_at. If a whole slot was missed, coalesce
  // the accumulated readings into the latest completed slot instead of
  // fabricating catch-up entries for windows with no separate samples.
  time_t historyNow = 0;
  time(&historyNow);
  if (historyNow > 1700000000) {
    if (nextHistorySlotEndEpoch == 0) {
      nextHistorySlotEndEpoch =
          (historyNow / HISTORY_SLOT_SECONDS + 1) * HISTORY_SLOT_SECONDS;
    } else if (historyNow >= nextHistorySlotEndEpoch) {
      time_t slotEnd = nextHistorySlotEndEpoch;
      if (historyNow - slotEnd >= HISTORY_SLOT_SECONDS) {
        slotEnd = (historyNow / HISTORY_SLOT_SECONDS) * HISTORY_SLOT_SECONDS;
      }
      nextHistorySlotEndEpoch =
          (historyNow / HISTORY_SLOT_SECONDS + 1) * HISTORY_SLOT_SECONDS;
      sendHistoryToFirestore(slotEnd);

      // A synchronous Firebase request may itself cross one or more slot
      // boundaries. Start the next collection window at the next future slot;
      // don't emit empty catch-up records after the request returns.
      time(&historyNow);
      if (historyNow > 1700000000) {
        nextHistorySlotEndEpoch =
            (historyNow / HISTORY_SLOT_SECONDS + 1) * HISTORY_SLOT_SECONDS;
      } else {
        nextHistorySlotEndEpoch = slotEnd + HISTORY_SLOT_SECONDS;
      }
      saveHistoryWindowCheckpoint();
      now = millis();
    }
  }

  // ─── Offline buffer flush (store-and-forward) ───
  // Runs whenever Firebase is reachable; 1 entry/sec max so the live
  // 5-sec + 10-min writes are never starved. Oldest entry goes first.
  if (now - lastFlushTime >= FLUSH_INTERVAL_MS) {
    queuePendingHistoryIfPossible();
    if (networkAvailable && hasCurrentTankAssignment() && ensureFirebaseReady()) {
      flushPendingLocalFeedLog();
      if (sdMounted || littlefsMounted) flushOneFeederLog();
    }
    if (networkAvailable && hasCurrentTankAssignment() && littlefsMounted &&
        countBufferedEntries() > 0) {
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

  if (now - lastHistoryCheckpointMs >= 60000UL) {
    lastHistoryCheckpointMs = now;
    if (!saveHistoryWindowCheckpoint()) {
      Serial.println("[HISTORY] Could not checkpoint in-progress window to NVS");
    }
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
  // Do not attach PWM or command the servo at boot: a stored/misidentified
  // close angle can physically open the gate and dispense feed on reset.
  // setGateAngle() attaches PWM lazily on an explicit command/feed instead.
  Serial.printf("[GATE] Boot-safe: no servo movement/PWM at startup on GPIO %d; close angle %sconfigured.\n",
                GATE_SERVO_PIN, gateCloseAngleConfigured ? "" : "NOT ");
  feederIsRunning = false;
  feederRunState = FEEDER_IDLE;
  feederCurrentCycle = 0;
  feederInitialized = true;
  recoverFeederLogs();

  // Do not park or self-test at boot; the first servo pulse is issued only
  // by an explicit close-angle command, test, or permitted feed cycle.
}

// ─── Process Commands from Firestore ───
// Lists tanks/{tankId}/feeder_commands, safely acknowledges one command, then
// starts its non-blocking feed cycle.
// Reads all docs into local arrays first to avoid fbdo buffer conflicts.
void processFeederCommands() {
  if (!gateCloseAngleConfigured) return;
  if (!hasCurrentTankAssignment()) return;
  if (!ensureFirebaseReady()) return;
  // Leave queued commands untouched while a feed is already running. This
  // prevents a second Feed Now request from being deleted without execution.
  if (feederRunState != FEEDER_IDLE) return;

  // Recover/upload any Feed Now result before looking at another command. If
  // a previous boot stopped after acknowledging a command, this writes one
  // failed/unconfirmed log and clears the stale command without dispensing it.
  if (!flushPendingFeedNowLog() || !flushPendingLocalFeedLog()) return;

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
  // Do not start an authentication/network attempt from a local-only feed.
  if (!hasCurrentTankAssignment() || WiFi.status() != WL_CONNECTED ||
      !firebaseReady || cloudOutage) return;
  if (!ensureFirebaseReady()) return;

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

// Preferences::getString logs NOT_FOUND even when a fallback is supplied.
// Feed Now's NVS keys are absent during normal idle operation and after a
// successful flush, so check for each key before reading it.
String readOptionalFeederStateString(const char* key, const String& fallback = "") {
  return prefs.isKey(key) ? prefs.getString(key, fallback) : fallback;
}

void loadFeederState() {
  prefs.begin("feederstate", true);
  feederEventSequence = prefs.getULong("eventSeq", 0);
  feederLastScheduledMinute = prefs.getULong("lastSchedMin", 0);
  if (!currentTankId.isEmpty() && readOptionalFeederStateString("tank") == currentTankId) {
    feederDispenseCount = prefs.getInt("dispenseCount", 0);
    feederLastCompletedEpoch = prefs.getULong("lastComplete", 0);
  }
  prefs.end();
  if (feederDispenseCount > 0) {
    Serial.printf("[FEEDER] Restored dispense count: %d\n", feederDispenseCount);
  }
}

// Feed Now execution and its retryable result live in NVS, not LittleFS.
// LittleFS is still used for scheduled/onsite log buffering, but a failed
// filesystem operation must not reboot the device before a cloud command is
// executed. The command marker enforces at-most-once execution across reboots;
// the deterministic Firestore log ID makes result retries idempotent.
bool reserveFeedNowCommand(const String& commandId, const String& tankId, float grams) {
  if (commandId.isEmpty() || tankId.isEmpty() || !isfinite(grams)) return false;
  if (!prefs.begin("feederstate", false)) return false;
  const String existingId = readOptionalFeederStateString("cmd_id");
  if (!existingId.isEmpty()) {
    prefs.end();
    return false;
  }
  const bool ok = prefs.putString("cmd_tank", tankId) > 0 &&
      prefs.putString("cmd_grams", String(grams, 1)) > 0 &&
      prefs.putString("cmd_id", commandId) > 0;
  prefs.end();
  return ok;
}

bool storePendingFeedNowLog(const String& tankId, const String& logId, const String& payload) {
  if (tankId.isEmpty() || logId.isEmpty() || payload.isEmpty()) return false;
  if (!prefs.begin("feederstate", false)) return false;
  const String existingId = readOptionalFeederStateString("log_id");
  if (!existingId.isEmpty() && existingId != logId) {
    prefs.end();
    return false;
  }
  // Write the payload last: its presence marks the complete NVS outbox item.
  const bool ok = prefs.putString("log_tank", tankId) > 0 &&
      prefs.putString("log_id", logId) > 0 &&
      prefs.putString("log_json", payload) > 0;
  prefs.end();
  return ok;
}

bool storePendingLocalFeedLog(const String& tankId, const String& eventKey,
                              const String& envelope) {
  // Unassigned onsite feeds remain local until the first later tank assignment
  // is known; the outbox then binds the record before attempting upload.
  if (eventKey.isEmpty() || envelope.isEmpty()) return false;
  if (!prefs.begin("feederstate", false)) return false;
  const String existingEvent = readOptionalFeederStateString("local_event");
  if (!existingEvent.isEmpty() && existingEvent != eventKey) {
    prefs.end();
    return false;
  }
  // Store the envelope last so its presence marks a complete recovery record.
  const bool ok = prefs.putString("local_tank", tankId) == tankId.length() &&
      prefs.putString("local_event", eventKey) > 0 &&
      prefs.putString("local_json", envelope) > 0;
  prefs.end();
  return ok;
}

bool hasPendingLocalFeedLog(const String& eventKey) {
  if (!prefs.begin("feederstate", true)) return false;
  const bool found = readOptionalFeederStateString("local_event") == eventKey &&
      !readOptionalFeederStateString("local_json").isEmpty();
  prefs.end();
  return found;
}

bool clearPendingLocalFeedLog(const String& eventKey) {
  if (!prefs.begin("feederstate", false)) return false;
  const String existingEvent = readOptionalFeederStateString("local_event");
  if (existingEvent != eventKey) {
    prefs.end();
    return existingEvent.isEmpty();
  }
  if (prefs.isKey("local_json")) prefs.remove("local_json");
  if (prefs.isKey("local_event")) prefs.remove("local_event");
  if (prefs.isKey("local_tank")) prefs.remove("local_tank");
  prefs.end();
  return true;
}

bool queueFeederLogEnvelope(const String& eventKey, const String& envelope,
                            bool pending) {
  if (eventKey.isEmpty() || envelope.isEmpty() ||
      (!sdMounted && !littlefsMounted) || !ensureFeederLogDirectory()) return false;
  fs::FS& logFs = feederLogFS();
  const String base = feederLogPath(eventKey);
  const String temp = base + ".tmp";
  const String target = base + (pending ? ".pending" : ".json");
  File file = logFs.open(temp, "w");
  if (!file) return false;
  const size_t written = file.print(envelope);
  file.flush();
  file.close();
  // The NVS record remains the recovery copy until this replacement succeeds,
  // so an older same-event target can be removed safely before atomic rename.
  if (written != envelope.length() ||
      (logFs.exists(target) && !logFs.remove(target)) ||
      !logFs.rename(temp, target)) {
    Serial.println("[FEEDER LOG] Offline queue write/rename failed; NVS recovery record retained");
    return false;
  }
  if (!pending) removeFeederLogIfPresent(logFs, base + ".pending");
  return true;
}

bool hasPendingFeederRecovery(const String& eventKey) {
  if (hasPendingLocalFeedLog(eventKey)) return true;
  if (eventKey.isEmpty() || (!sdMounted && !littlefsMounted)) return false;
  if (!ensureFeederLogDirectory()) return false;
  File marker = feederLogFS().open(feederLogPath(eventKey) + ".pending", "r");
  if (!marker) return false;
  marker.close();
  return true;
}

// Bind only onsite events deliberately marked unassigned at capture time.
// They are routed to the first valid tank assignment seen when syncing later.
bool bindUnassignedOnsiteFeedEnvelope(FirebaseJson& envelope,
                                      const String& assignedTankId) {
  if (assignedTankId.isEmpty()) return false;
  FirebaseJsonData field;
  if (!envelope.get(field, "tank") || !field.stringValue.isEmpty()) return false;
  const bool markedPending = envelope.get(field, "assignment_pending") &&
      field.stringValue == "true";
  if (!envelope.get(field, "payload")) return false;

  FirebaseJson payload;
  if (!payload.setJsonData(field.stringValue)) return false;
  if (!payload.get(field, "fields/trigger_source/stringValue") ||
      field.stringValue != "physical_button") return false;
  const bool legacyPending = payload.get(field, "fields/assignment_status/stringValue") &&
      field.stringValue == "unassigned_local_only";
  if (!markedPending && !legacyPending) return false;

  // The destination is represented by the Firestore collection path. Remove
  // local-only routing metadata so the uploaded document keeps the app schema.
  payload.remove("fields/assignment_status");
  payload.remove("fields/assignment_tank_id");
  if (!payload.get(field, "fields/logged_at/timestampValue")) {
    time_t uploadTime;
    time(&uploadTime);
    const String linkedAt = firestoreTimestampString(uploadTime);
    if (linkedAt.isEmpty()) return false;  // wait for NTP before creating a cloud log
    payload.set("fields/logged_at/timestampValue", linkedAt);
    payload.remove("fields/device_uptime_ms");
    payload.remove("fields/time_source");
  }
  envelope.set("tank", assignedTankId);
  envelope.set("payload", payload.raw());
  envelope.remove("assignment_pending");
  return true;
}

bool queuePendingLocalFeedLogOffline() {
  if (!prefs.begin("feederstate", true)) return false;
  const String eventKey = readOptionalFeederStateString("local_event");
  const String envelope = readOptionalFeederStateString("local_json");
  prefs.end();
  if (envelope.isEmpty()) return true;
  if (feederRunState != FEEDER_IDLE) return false;
  if (!queueFeederLogEnvelope(eventKey, envelope, false)) return false;
  const bool cleared = clearPendingLocalFeedLog(eventKey);
  if (cleared) {
    Serial.printf("[FEEDER LOG] Offline event %s queued locally for Firebase retry\n",
                  eventKey.c_str());
  }
  return cleared;
}

bool flushPendingLocalFeedLog() {
  if (!prefs.begin("feederstate", true)) return false;
  String tankId = readOptionalFeederStateString("local_tank");
  const String eventKey = readOptionalFeederStateString("local_event");
  String serialized = readOptionalFeederStateString("local_json");
  prefs.end();
  if (serialized.isEmpty()) return true;
  // The NVS envelope is a recovery marker until the active feed reaches a
  // terminal result; do not publish its provisional "unconfirmed" payload.
  if (feederRunState != FEEDER_IDLE) return true;
  if (eventKey.isEmpty()) return false;
  if (tankId.isEmpty()) {
    if (!hasCurrentTankAssignment()) {
      // Keep the event local until a tank exists; never guess a destination.
      if (!queueFeederLogEnvelope(eventKey, serialized, false)) return false;
      const bool cleared = clearPendingLocalFeedLog(eventKey);
      if (cleared) {
        Serial.printf("[FEEDER LOG] Unassigned onsite event %s retained locally; waiting for tank assignment\n",
                      eventKey.c_str());
      }
      return cleared;
    }

    FirebaseJson unassignedEnvelope;
    unassignedEnvelope.setJsonData(serialized);
    if (!bindUnassignedOnsiteFeedEnvelope(unassignedEnvelope, currentTankId)) {
      Serial.printf("[FEEDER LOG] Refusing to route unassigned event %s: not an onsite feed record\n",
                    eventKey.c_str());
      return false;
    }
    tankId = currentTankId;
    serialized = unassignedEnvelope.raw();
    // Persist the selected destination before a network attempt, so retries
    // cannot silently move the same event to a different tank.
    if (!storePendingLocalFeedLog(tankId, eventKey, serialized)) return false;
    Serial.printf("[FEEDER LOG] Linking previously unassigned onsite event %s to tank %s\n",
                  eventKey.c_str(), tankId.c_str());
  }
  if (!ensureFirebaseReady()) return false;

  FirebaseJson envelope;
  envelope.setJsonData(serialized);
  FirebaseJsonData field;
  if (!envelope.get(field, "tank") || field.stringValue != tankId) return false;
  if (!envelope.get(field, "id")) return false;
  const String logId = field.stringValue;
  if (!envelope.get(field, "payload")) return false;
  const String payload = field.stringValue;
  const String collection = "tanks/" + tankId + "/feeder_logs";
  const bool uploaded = Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "",
      collection.c_str(), logId.c_str(), payload.c_str(), "");
  const bool duplicate = !uploaded && fbdo.httpCode() == 409;
  if (!uploaded && !duplicate) {
    Serial.printf("[FEEDER LOG] Direct Firestore save failed; queueing for retry: %s\n",
                  fbdo.errorReason().c_str());
    if (!queueFeederLogEnvelope(eventKey, serialized, false)) return false;
    return clearPendingLocalFeedLog(eventKey);
  }

  if (!clearPendingLocalFeedLog(eventKey)) return false;
  if (sdMounted || littlefsMounted) {
    fs::FS& logFs = feederLogFS();
    const String base = feederLogPath(eventKey);
    removeFeederLogIfPresent(logFs, base + ".pending");
    removeFeederLogIfPresent(logFs, base + ".json");
    removeFeederLogIfPresent(logFs, base + ".tmp");
  }
  Serial.printf("[FEEDER LOG] Direct Firestore save confirmed (%s)\n", logId.c_str());
  return true;
}

bool flushPendingFeedNowLog() {
  if (!prefs.begin("feederstate", false)) return false;
  if (!prefs.isKey("cmd_id") && !prefs.isKey("log_json")) {
    prefs.end();
    return true;
  }
  String commandId = readOptionalFeederStateString("cmd_id");
  String commandTank = readOptionalFeederStateString("cmd_tank");
  String commandGrams = readOptionalFeederStateString("cmd_grams", "1.0");
  String tankId = readOptionalFeederStateString("log_tank");
  String logId = readOptionalFeederStateString("log_id");
  String payload = readOptionalFeederStateString("log_json");
  prefs.end();

  if (payload.isEmpty()) {
    if (commandId.isEmpty()) return true;
    // A reset after acknowledging the command but before a terminal result
    // means the physical outcome cannot be confirmed. Record that explicitly;
    // never replay the same command after reboot.
    if (commandTank.isEmpty()) return false;
    time_t now;
    time(&now);
    const String loggedAt = firestoreTimestampString(now);
    if (loggedAt.isEmpty()) return false;
    FirebaseJson interrupted;
    interrupted.set("fields/action/stringValue", "Feed interrupted - execution could not be confirmed");
    interrupted.set("fields/type/stringValue", "manual");
    interrupted.set("fields/status/stringValue", "failed");
    interrupted.set("fields/command_id/stringValue", commandId);
    interrupted.set("fields/trigger_source/stringValue", "manual_request");
    interrupted.set("fields/logged_at/timestampValue", loggedAt);
    interrupted.set("fields/requested_grams/doubleValue", commandGrams);
    tankId = commandTank;
    logId = hardwareId + "_cmd_" + commandId;
    payload = interrupted.raw();
    if (!storePendingFeedNowLog(tankId, logId, payload)) return false;
  }

  if (tankId.isEmpty() || logId.isEmpty()) return false;
  const String collection = "tanks/" + tankId + "/feeder_logs";
  const bool uploaded = Firebase.Firestore.createDocument(&fbdo, FIREBASE_PROJECT_ID, "",
      collection.c_str(), logId.c_str(), payload.c_str(), "");
  const bool duplicate = !uploaded && fbdo.httpCode() == 409;
  if (!uploaded && !duplicate) {
    Serial.printf("[FEEDER LOG] Feed Now result upload failed: %s\n", fbdo.errorReason().c_str());
    return false;
  }

  // A crash/ambiguous Firestore acknowledgement may leave the command queued.
  // Delete it only after its outcome is safely present in the log collection.
  if (!commandId.isEmpty()) {
    const String commandPath = "tanks/" + tankId + "/feeder_commands/" + commandId;
    const bool deleted = Firebase.Firestore.deleteDocument(&fbdo, FIREBASE_PROJECT_ID, "", commandPath.c_str());
    if (!deleted && fbdo.httpCode() != 404) {
      Serial.printf("[FEEDER CMD] Could not clear recovered command: %s\n", fbdo.errorReason().c_str());
      return false;
    }
  }

  if (!prefs.begin("feederstate", false)) return false;
  if (prefs.isKey("log_json")) prefs.remove("log_json");
  if (prefs.isKey("log_id")) prefs.remove("log_id");
  if (prefs.isKey("log_tank")) prefs.remove("log_tank");
  if (prefs.isKey("cmd_id")) prefs.remove("cmd_id");
  if (prefs.isKey("cmd_tank")) prefs.remove("cmd_tank");
  if (prefs.isKey("cmd_grams")) prefs.remove("cmd_grams");
  prefs.end();
  Serial.printf("[FEEDER LOG] Feed Now outcome saved to Firestore (%s)\n", logId.c_str());
  return true;
}

// ─── Sync Schedules from Firestore ───
// Fetch every page, then replace the cache. No silent 20-item cutoff.
void syncFeederSchedules() {
  if (!hasCurrentTankAssignment()) return;
  if (!ensureFirebaseReady()) return;

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

// The double-tap confirmation is reserved for the schedule-collision warning.
// Sensor faults and critical feed level are never bypassable.
bool feedBlockBypassable(const String& reason) {
  return reason.startsWith("automatic feeding is due at");
}

String waterQualityWarningText() {
  String warning;
  auto appendWarning = [&warning](const String& item) {
    if (warning.length() > 0) warning += "; ";
    warning += item;
  };
  if (!tempSensorOK) {
    appendWarning("Temperature sensor unavailable");
  } else if (!isfinite(smoothedTemp) || smoothedTemp < 0.0f || smoothedTemp > 50.0f) {
    appendWarning("Temperature reading invalid");
  } else {
    if (smoothedTemp < tempCriticalLow) {
      appendWarning("Temperature low: " + String(smoothedTemp, 1) + " C (min " + String(tempCriticalLow, 1) + " C)");
    } else if (smoothedTemp > tempCriticalHigh) {
      appendWarning("Temperature high: " + String(smoothedTemp, 1) + " C (max " + String(tempCriticalHigh, 1) + " C)");
    }
  }
  if (!doSensorOK) {
    appendWarning("Dissolved oxygen sensor unavailable");
  } else if (!isfinite(dissolvedOxygen) || dissolvedOxygen < 0.0f || dissolvedOxygen > 30.0f) {
    appendWarning("Dissolved oxygen reading invalid");
  } else {
    if (dissolvedOxygen < doCriticalLow) {
      appendWarning("Dissolved oxygen low: " + String(dissolvedOxygen, 1) + " mg/L (min " + String(doCriticalLow, 1) + " mg/L)");
    } else if (dissolvedOxygen > doCriticalHigh) {
      appendWarning("Dissolved oxygen high: " + String(dissolvedOxygen, 1) + " mg/L (max " + String(doCriticalHigh, 1) + " mg/L)");
    }
  }
  if (!phSensorOK) {
    appendWarning("pH sensor unavailable");
  } else if (!isfinite(phLevel) || phLevel < 0.0f || phLevel > 14.0f) {
    appendWarning("pH reading invalid");
  } else {
    if (phLevel < phCriticalLow) {
      appendWarning("pH low: " + String(phLevel, 2) + " (min " + String(phCriticalLow, 2) + ")");
    } else if (phLevel > phCriticalHigh) {
      appendWarning("pH high: " + String(phLevel, 2) + " (max " + String(phCriticalHigh, 2) + ")");
    }
  }
  if (!turbiditySensorOK) {
    appendWarning("Turbidity sensor unavailable");
  } else if (!isfinite(smoothedTurbidityNTU) || smoothedTurbidityNTU < 0.0f ||
             smoothedTurbidityNTU > 1000.0f) {
    appendWarning("Turbidity reading invalid");
  } else {
    if (smoothedTurbidityNTU < turbNtuMin) {
      appendWarning("Turbidity low: " + String(smoothedTurbidityNTU, 0) + " NTU (min " + String(turbNtuMin, 0) + " NTU)");
    } else if (smoothedTurbidityNTU > turbNtuMax) {
      appendWarning("Turbidity high: " + String(smoothedTurbidityNTU, 0) + " NTU (max " + String(turbNtuMax, 0) + " NTU)");
    }
  }
  return warning;
}

String waterQualityLcdWarning() {
  const bool useWindow = liveSensorSnapshot.ready;
  const bool tempValid = useWindow ? liveSensorSnapshot.tempValid : tempSensorOK;
  const float tempValue = useWindow ? liveSensorSnapshot.temperature : smoothedTemp;
  const bool doValid = useWindow ? liveSensorSnapshot.doValid : doSensorOK;
  const float doValue = useWindow ? liveSensorSnapshot.dissolvedOxygen : dissolvedOxygen;
  const bool phValid = useWindow ? liveSensorSnapshot.phValid : phSensorOK;
  const float phValue = useWindow ? liveSensorSnapshot.ph : phLevel;
  const bool turbidityValid = useWindow ? liveSensorSnapshot.turbidityValid : turbiditySensorOK;
  const float turbidityValue = useWindow
      ? liveSensorSnapshot.turbidityNTU : smoothedTurbidityNTU;

  if (!tempValid || !isfinite(tempValue) || tempValue < 0.0f || tempValue > 50.0f) return "Temp SENSOR?";
  if (tempValue < tempCriticalLow) return "Temp LOW";
  if (tempValue > tempCriticalHigh) return "Temp HIGH";

  if (!doValid || !isfinite(doValue) || doValue < 0.0f || doValue > 30.0f) return "DO SENSOR?";
  if (doValue < doCriticalLow) return "DO LOW";
  if (doValue > doCriticalHigh) return "DO HIGH";

  if (!phValid || !isfinite(phValue) || phValue < 0.0f || phValue > 14.0f) return "pH SENSOR?";
  if (phValue < phCriticalLow) return "pH LOW";
  if (phValue > phCriticalHigh) return "pH HIGH";

  if (!turbidityValid || !isfinite(turbidityValue) || turbidityValue < 0.0f ||
      turbidityValue > 1000.0f) return "Turb SENSOR?";
  if (turbidityValue < turbNtuMin) return "Turbidity LOW";
  if (turbidityValue > turbNtuMax) return "Turbidity HIGH";
  return "";
}

bool canFeedSafely(String &reason, bool allowLocalConfigFallback = false) {
  if (!feederConfigReady && !allowLocalConfigFallback) {
    reason = "tank sensor settings have not finished syncing";
    return false;
  }
  // Water-quality values (temperature, DO, pH, turbidity) are advisory only.
  // Missing, invalid, or out-of-range readings are reported as warnings but
  // do not inhibit feeding. Hopper/feed-level validity and critical-low
  // protection remain the sensor-based dispense interlock.
  const float criticalThreshold = feederConfigReady
      ? feedLevelCriticalThreshold : FEED_LEVEL_CRITICAL_DEFAULT;
  if (!feedLevelSensorOK) reason = "feed-level sensor unavailable";
  else if (!isfinite(feedLevelPercent) || feedLevelPercent < 0.0f || feedLevelPercent > 100.0f) {
    reason = "feed-level sensor unavailable";
  }
  else if (feedLevelPercent <= criticalThreshold) reason = "critical feed level";
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
  if (!gateCloseAngleConfigured || currentTankId.isEmpty() || !feederAutoMode ||
      feederScheduleCount == 0 || feederRunState != FEEDER_IDLE) return;

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
      const unsigned long scheduledMinuteEpoch = nowEpoch - nowEpoch % 60;
      // Do not catch up a scheduled occurrence whose minute had already
      // started before this boot. The next future schedule remains enabled.
      const bool occurrenceStartedThisBoot = feederBootEpoch > 0 &&
          scheduledMinuteEpoch > (unsigned long)feederBootEpoch;
      if (occurrenceStartedThisBoot && nowEpoch / 60 > feederLastScheduledMinute &&
          s.effectiveEpoch <= scheduledMinuteEpoch) {
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
  const bool localOnsite = source == "onsite";
  // Defense in depth: never start or log an onsite feed during a boot/pump
  // transition lockout, even if another caller reaches this function.
  if (source == "onsite" && isOnsiteButtonLockedOut()) {
    feederStatus = "blocked";
    feederStatusReason = "Onsite feed startup/pump cooldown";
    return;
  }
  feederWaterQualityWarning = "";
  if (!forceOverride) { feederForced = false; feederForceReason = ""; }
  if (feederRunState != FEEDER_IDLE) {
    feederStatusReason = "Feeder busy";
    Serial.println("[FEEDER] Already running, skipping");
    return;
  }
  if (!gateCloseAngleConfigured) {
    feederStatus = "blocked";
    feederStatusReason = "Gate close angle not calibrated";
    Serial.println("[FEEDER] BLOCKED: configure GATE_CLOSE_ANGLE before feeding");
    return;
  }
  feederStatusReason = "";
  if (currentTankId.isEmpty() && !localOnsite) {
    feederStatusReason = "Tank not assigned";
    Serial.println("[FEEDER] BLOCKED: tank assignment is not available");
    return;
  }
  time_t startedAt;
  time(&startedAt);
  if (startedAt < 1700000000 && !localOnsite) {
    feederStatusReason = "Clock not synced";
    Serial.printf("[FEEDER] BLOCKED: %s\n", feederStatusReason.c_str());
    return;
  }
  feederCommandId = commandId;
  feederStatusReason = "";
  feederRequestedGrams = grams;
  {
    MutexGuard lcdLock(lcdMutex);
    feederFeedSource = source;
  }
  feederEventTank = localOnsite && !hasCurrentTankAssignment()
      ? String("") : currentTankId;
  feederOccurrenceEpoch = source == "scheduled"
      ? startedAt - startedAt % 60
      : startedAt >= 1700000000 ? startedAt : 0;
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
  if (!commandId.isEmpty()) {
    // NVS provides the durable at-most-once marker for cloud Feed Now. This
    // avoids LittleFS open/rename operations in the command path that were
    // panicking before the servo could start.
    if (!reserveFeedNowCommand(commandId, currentTankId, grams)) {
      feederStatus = "blocked";
      feederStatusReason = "Another Feed Now result is still pending";
      Serial.println("[FEEDER] Cannot reserve Feed Now in NVS; refusing to dispense");
      sendFeederStatus();
      return;
    }
  } else {
    // Local intent recovery remains for scheduled and physical-button feeding.
    feederWritingIntent = true;
    pushFeederLog("Feed interrupted - execution could not be confirmed", source == "scheduled" ? "auto" : "manual",
                  "failed", grams, -1, -1);
    feederWritingIntent = false;
    if (!hasPendingFeederRecovery(feederEventKey)) {
      feederStatus = "blocked";
      feederStatusReason = "Cannot persist feed recovery marker";
      Serial.println("[FEEDER] BLOCKED: recovery marker could not be saved to NVS, SD, or LittleFS");
      sendFeederStatus();
      return;
    }
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
  if (!commandId.isEmpty() && feederBootEpoch > 0 &&
      issuedAtMs > 0 && issuedAtMs <= (long long)feederBootEpoch * 1000) {
    blockedReason = "Feed Now request predates ESP boot; submit a new request";
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
    if (!canFeedSafely(sensorRangeReason, localOnsite)) {
      blockedReason = sensorRangeReason;
    } else {
      if (localOnsite && !feederConfigReady) {
        Serial.printf("[FEEDER] No synced tank config; onsite feed uses firmware feed-level critical threshold %.0f%%\n",
                      FEED_LEVEL_CRITICAL_DEFAULT);
      }
      MutexGuard sensorLock(sensorStateMutex);
      feederWaterQualityWarning = waterQualityWarningText();
      if (feederWaterQualityWarning.length() > 0) {
        Serial.printf("[FEEDER] Water-quality warning (feeding remains allowed): %s\n",
                      feederWaterQualityWarning.c_str());
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
  Serial.printf("[FEEDER] Gate setup: GPIO%d, open=%d, hold=%dms, closed dwell=%ums; blower lead=%us\n",
                GATE_SERVO_PIN, gateOpenAngle, gateHoldMs,
                gateCloseDwellMs,
                (unsigned)BLOWER_PRE_SEC);
}

// ─── Non-blocking feeder tick — call every loop() ───
void processFeederTick() {
  if (feederRunState == FEEDER_IDLE) return;

  unsigned long now = millis();

  switch (feederRunState) {

    case FEEDER_PRE_BLOW:
      // Blower was switched auto-ON at startFeed; wait out the warm-up lead.
      if (now - feederStepMs >= (unsigned long)BLOWER_PRE_SEC * 1000UL) {
        Serial.printf("[FEEDER] Blower lead complete; opening gate at %d degrees\n",
                      gateOpenAngle);
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
        setGateAngle(gateCloseAngle);
        feederStepMs = now;
        feederCurrentCycle++;
        feederRunState = FEEDER_CLOSE_DWELL;
      }
      break;

    case FEEDER_CLOSE_DWELL:
      // Without this dwell the next FORWARD fires before the servo is fully
      // shut. Normal feeding and GATECAL both wait one full second closed.
      if (now - feederStepMs >= gateCloseDwellMs) {
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

      setGateAngle(gateCloseAngle);
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
      // Keep the warning available for the LCD completion message only.
      String completionAction = feederFeedSource == "scheduled"
          ? String("Dispensed feed (Scheduled)")
          : feederFeedSource == "onsite"
              ? (feederForced ? "Dispensed feed (Onsite Button, override: " + feederForceReason + ")"
                              : "Dispensed feed (Onsite Button)")
              : String("Dispensed feed (Manual)");
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
// Feed Now uses an NVS outbox; other feed outcomes are Firestore-first online
// and use SD/LittleFS store-and-forward only when Firebase is unavailable.
void pushFeederLog(String action, String type, String status,
                   float requestedGrams, float levelBefore, float levelAfter) {
  const bool unassignedOnsite = feederEventTank.isEmpty() && feederFeedSource == "onsite";
  if (feederEventTank.isEmpty() && !unassignedOnsite) return;
  const bool feedNowCommand = !feederCommandId.isEmpty();

  time_t now;
  time(&now);
  const String loggedAt = firestoreTimestampString(now);
  if (loggedAt.isEmpty() && !unassignedOnsite && feederFeedSource != "onsite") {
    Serial.println("[FEEDER LOG] Skipped Firestore write: system clock is not synchronized");
    return;
  }

  FirebaseJson json;
  json.set("fields/action/stringValue",    action);
  json.set("fields/type/stringValue",      type);
  if (!feederCommandId.isEmpty()) json.set("fields/command_id/stringValue", feederCommandId);
  if (!loggedAt.isEmpty()) {
    json.set("fields/logged_at/timestampValue", loggedAt);
  } else {
    json.set("fields/device_uptime_ms/integerValue", String(millis()));
    json.set("fields/time_source/stringValue", "device_uptime_no_network_time");
  }
  if (unassignedOnsite) {
    json.set("fields/assignment_status/stringValue", "unassigned_local_only");
  }
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

  if (feedNowCommand) {
    // Keep the exact outcome in NVS before attempting Firestore. The fixed
    // event ID lets retries safely treat HTTP 409 as already recorded.
    const String logId = hardwareId + "_" + feederEventKey;
    if (!storePendingFeedNowLog(feederEventTank, logId, json.raw())) {
      Serial.println("[FEEDER LOG] Could not persist Feed Now result in NVS; command marker retained");
      return;
    }
    flushPendingFeedNowLog();
    return;
  }

  FirebaseJson envelope;
  envelope.set("tank", feederEventTank);
  envelope.set("id", hardwareId + "_" + feederEventKey);
  envelope.set("command_id", feederCommandId);
  envelope.set("scheduled_minute", type == "auto" ? feederOccurrenceEpoch / 60 : 0);
  envelope.set("payload", String(json.raw()));
  if (unassignedOnsite) envelope.set("assignment_pending", "true");
  const String serialized = envelope.raw();

  // Keep a compact recovery marker while an online/local feed is in progress.
  // Prefer NVS; if its single-slot outbox is unavailable/full, use the mounted
  // SD/LittleFS queue instead. Never start a physical cycle without a durable
  // recovery record, but do not require NVS when filesystem storage is ready.
  if (feederWritingIntent) {
    if (!storePendingLocalFeedLog(feederEventTank, feederEventKey, serialized)) {
      if (!queueFeederLogEnvelope(feederEventKey, serialized, true)) {
        Serial.println("[FEEDER LOG] Could not save recovery marker to NVS, SD, or LittleFS");
        return;
      }
      Serial.printf("[FEEDER LOG] NVS marker unavailable; recovery intent saved to %s\n",
                    sdMounted ? "SD" : "LittleFS");
      return;
    }
    const bool firebaseOnline = WiFi.status() == WL_CONNECTED &&
        firebaseReady && !cloudOutage;
    if (!firebaseOnline && (sdMounted || littlefsMounted)) {
      if (queueFeederLogEnvelope(feederEventKey, serialized, true)) {
        Serial.printf("[FEEDER LOG] Offline intent %s also journaled locally\n",
                      feederEventKey.c_str());
      }
    }
    return;
  }

  // An onsite action without an assignment cannot yet be routed into a
  // tank-scoped Firestore collection. Keep it locally for later assignment.
  if (unassignedOnsite) {
    if (queueFeederLogEnvelope(feederEventKey, serialized, false)) {
      clearPendingLocalFeedLog(feederEventKey);
      Serial.printf("[FEEDER LOG] Unassigned onsite event %s saved locally; waiting for a tank assignment\n",
                    feederEventKey.c_str());
    } else if (storePendingLocalFeedLog(feederEventTank, feederEventKey, serialized)) {
      Serial.println("[FEEDER LOG] Unassigned onsite event retained in NVS; local filesystem unavailable");
    } else {
      Serial.println("[FEEDER LOG] CRITICAL: unable to persist unassigned onsite event");
    }
    return;
  }

  // Online is Firestore-first. A deterministic document ID makes an
  // ambiguous retry safe: HTTP 409 means this exact event is already saved.
  if (WiFi.status() == WL_CONNECTED && ensureFirebaseReady()) {
    const String collection = "tanks/" + feederEventTank + "/feeder_logs";
    const String logId = hardwareId + "_" + feederEventKey;
    const bool uploaded = Firebase.Firestore.createDocument(&fbdo,
        FIREBASE_PROJECT_ID, "", collection.c_str(), logId.c_str(),
        json.raw(), "");
    const bool duplicate = !uploaded && fbdo.httpCode() == 409;
    if (uploaded || duplicate) {
      clearPendingLocalFeedLog(feederEventKey);
      if (sdMounted || littlefsMounted) {
        fs::FS& logFs = feederLogFS();
        const String base = feederLogPath(feederEventKey);
        removeFeederLogIfPresent(logFs, base + ".pending");
        removeFeederLogIfPresent(logFs, base + ".json");
        removeFeederLogIfPresent(logFs, base + ".tmp");
      }
      Serial.printf("[FEEDER LOG] Saved directly to Firebase (%s)\n", logId.c_str());
      return;
    }
    Serial.printf("[FEEDER LOG] Firebase write failed; queuing for retry: %s\n",
                  fbdo.errorReason().c_str());
  }

  // Offline (or Firebase write failure): durable store-and-forward queue.
  if (queueFeederLogEnvelope(feederEventKey, serialized, false)) {
    clearPendingLocalFeedLog(feederEventKey);
    Serial.printf("[FEEDER LOG] Offline event %s queued on %s\n",
                  feederEventKey.c_str(), sdMounted ? "SD" : "LittleFS");
    return;
  }

  // If storage is unavailable, keep the exact final event in NVS until it can
  // be sent or queued; never discard the only copy.
  if (storePendingLocalFeedLog(feederEventTank, feederEventKey, serialized)) {
    Serial.println("[FEEDER LOG] Queue unavailable; final event retained in NVS");
  } else {
    Serial.println("[FEEDER LOG] CRITICAL: unable to persist final event in NVS or offline queue");
  }
}

void recoverFeederLogs() {
  if (!sdMounted && !littlefsMounted) return;
  if (!ensureFeederLogDirectory()) return;
  fs::FS& logFs = feederLogFS();
  File dir = logFs.open(feederLogRoot());
  std::vector<String> pending;
  for (File file = dir.openNextFile(); file; file = dir.openNextFile()) {
    String path = file.path();
    if (path.endsWith(".pending")) pending.push_back(path);
    file.close();
  }
  dir.close();
  for (const String& path : pending) {
    File intent = logFs.open(path, "r");
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
    if (logFs.exists(target)) removeFeederLogIfPresent(logFs, path);
    else logFs.rename(path, target);
  }
}

bool flushOneFeederLog() {
  if ((!sdMounted && !littlefsMounted) || !hasCurrentTankAssignment() ||
      !ensureFeederLogDirectory()) return false;
  recoverFeederLogs(); // Idle only: finalize any intent whose completion write failed.
  fs::FS& logFs = feederLogFS();
  File dir = logFs.open(feederLogRoot());
  if (!dir || !dir.isDirectory()) {
    if (dir) dir.close();
    Serial.println("[FEEDER LOG] Log directory unavailable; retrying later.");
    return false;
  }
  for (File file = dir.openNextFile(); file; file = dir.openNextFile()) {
    const String path = file.path();
    if (!path.endsWith(".json")) { file.close(); continue; }
    FirebaseJson envelope;
    envelope.setJsonData(file.readString());
    file.close();
    FirebaseJsonData field;
    if (!envelope.get(field, "tank")) continue;
    if (field.stringValue.isEmpty()) {
      String eventKey = path.substring(path.lastIndexOf('/') + 1);
      if (eventKey.endsWith(".json")) {
        eventKey = eventKey.substring(0, eventKey.length() - 5);
      }
      if (!bindUnassignedOnsiteFeedEnvelope(envelope, currentTankId)) continue;
      // Move the event into the durable NVS outbox with its first assigned
      // tank before attempting upload; retries keep this same destination.
      const bool reserved = storePendingLocalFeedLog(
          currentTankId, eventKey, envelope.raw());
      dir.close();
      if (!reserved) return false;
      return flushPendingLocalFeedLog();
    }
    if (field.stringValue != currentTankId) continue;
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
    if (uploaded || duplicate) {
      const bool removed = removeFeederLogIfPresent(logFs, path);
      if (removed) {
        Serial.printf("[FEEDER LOG] Offline event uploaded to Firebase (%s)\n", id.c_str());
      }
      return removed;
    }
    return false;
  }
  dir.close();
  return true;
}

void applyTankAssignment(const String& tankId, const String& ownerUid, long long assignedAtMs) {
  if (tankId == currentTankId && ownerUid == currentOwnerUid && assignedAtMs == currentAssignmentAtMs) return;
  const bool preserveRecoveredWindow = historyWindowRecovered &&
      tankId == persistedHistoryState.tankId &&
      ownerUid == persistedHistoryState.ownerUid &&
      assignedAtMs == persistedHistoryState.assignmentAtMs;
  const bool hadAssignment = currentTankId.length() > 0 && currentOwnerUid.length() > 0;
  const bool hasAssignment = tankId.length() > 0 && ownerUid.length() > 0;
  if (hadAssignment || hasAssignment) {
    if (!hasAssignment) {
      Serial.println("[ASSIGNMENT] Hardware is now unassigned; cloud writes are paused and local buffers are retained until assignment returns.");
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
  if (!preserveRecoveredWindow) {
    resetWindowAggregates(); // A 10-minute window must never span two assignments.
  }
  historyWindowRecovered = false;
  saveHistoryWindowCheckpoint();
  feederConfigReady = false;
  if (!feederInitialized) return;
  // Loop defers cloud work until the servo is parked. Revoke the cached plan;
  // never carry a previous owner's schedules/counters into the next account.
  {
    MutexGuard scheduleLock(feederScheduleMutex);
    feederSchedules.clear();
    feederScheduleCount = 0;
  }
  feederWaterQualityWarning = "";
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
  if (idx == 0) {
    // Clear pending button taps and ignore input around pump relay switching.
    // Arm this before toggling the relay, which is when interference occurs.
    beginOnsiteButtonLockout(ONSITE_PUMP_LOCKOUT_US);
  }
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
#define LCD_ROTATE_MS 5000
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

void updateSystemCloudMode() {
  const bool cloudActive = !cloudModeForcedOffline() && hasCurrentTankAssignment() &&
      WiFi.status() == WL_CONNECTED && firebaseReady && !cloudOutage;
  if (systemCloudModeInitialized && cloudActive == systemCloudModeActive) return;

  systemCloudModeInitialized = true;
  systemCloudModeActive = cloudActive;
  if (cloudActive) {
    Serial.printf("[SYSTEM] Cloud mode active for assigned tank %s.\n",
                  currentTankId.c_str());
    showLCDTransient("Cloud online", "Tank assigned", 2500);
  } else if (cloudModeForcedOffline()) {
    Serial.println("[SYSTEM] Forced OFFLINE mode — cloud operations paused; local sensing/feed and buffers continue.");
    showLCDTransient("Forced offline", "Cloud paused", 2500);
  } else if (!hasCurrentTankAssignment()) {
    Serial.println("[SYSTEM] Local/offline mode — no valid tank assignment; only assignment discovery remains enabled.");
    showLCDTransient("No tank assigned", "Local mode", 2500);
  } else if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[SYSTEM] Local/offline mode — Wi-Fi unavailable; local sensing/feed continue.");
    showLCDTransient("Wi-Fi offline", "Local mode", 2500);
  } else {
    Serial.println("[SYSTEM] Local/offline mode — Firebase unavailable; local sensing/feed continue.");
    showLCDTransient("Cloud offline", "Local mode", 2500);
  }
}

void IRAM_ATTR onsiteButtonISR() {
  if (!onsiteButtonEnabled) return;
  const uint32_t nowUs = micros();
  portENTER_CRITICAL_ISR(&onsiteButtonMux);
  if (onsiteButtonLockoutActive &&
      (uint32_t)(nowUs - onsiteButtonLockoutStartedUs) <
          onsiteButtonLockoutDurationUs) {
    portEXIT_CRITICAL_ISR(&onsiteButtonMux);
    return;
  }
  onsiteButtonLockoutActive = false;
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
  Serial.printf("[FEEDER] BLOCKED (schedule collision): %s — tap 2x within 10 s to confirm\n",
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
  // Discard any stale count in the lockout window; it must not reach the
  // dispense or feed-log path after the cooldown expires.
  if (isOnsiteButtonLockedOut()) {
    portENTER_CRITICAL(&onsiteButtonMux);
    onsiteButtonTapCount = 0;
    portEXIT_CRITICAL(&onsiteButtonMux);
    return;
  }
  // Confirmation taps inside the schedule-collision warning window are
  // counted immediately and never converted to grams.
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
  const String liveWaterQualityWarning = waterQualityLcdWarning();
  const float lcdTemp = liveSensorSnapshot.ready
      ? (liveSensorSnapshot.tempValid ? liveSensorSnapshot.temperature : -127.0f)
      : smoothedTemp;
  const float lcdPH = liveSensorSnapshot.ready
      ? (liveSensorSnapshot.phValid ? liveSensorSnapshot.ph : -1.0f) : phLevel;
  const float lcdDO = liveSensorSnapshot.ready
      ? (liveSensorSnapshot.doValid ? liveSensorSnapshot.dissolvedOxygen : -1.0f)
      : dissolvedOxygen;
  const float lcdTurbidity = liveSensorSnapshot.ready
      ? (liveSensorSnapshot.turbidityValid ? liveSensorSnapshot.turbidityNTU : -1.0f)
      : smoothedTurbidityNTU;
  const float lcdWater = liveSensorSnapshot.ready
      ? (liveSensorSnapshot.waterValid ? liveSensorSnapshot.waterLevelCm : -1.0f)
      : waterLevelCm;
  const float lcdFeed = liveSensorSnapshot.ready
      ? (liveSensorSnapshot.feedValid ? liveSensorSnapshot.feedLevelPercent : -1.0f)
      : feedLevelPercent;
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
    l1 = feederWaterQualityWarning.length() > 0
        ? "Water quality warn"
        : "Gate cycles done";
  } else if (overrideWarnReason.length() > 0) {
    l0 = overrideWarnReason.substring(0, 16);
    l1 = "Tap 2x to confirm";
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
      lcdScreen = (lcdScreen + 1) % (liveWaterQualityWarning.length() > 0 ? 5 : 4);
    } else if (lastLcdMs != 0) {
      return;
    }
    if (lcdScreen == 0) {
      l0 = String("Temp: ") + (lcdTemp > -100 ? String(lcdTemp, 2) + " C" : "--");
      l1 = String("pH: ") + (lcdPH >= 0 ? String(lcdPH, 2) : "--");
    } else if (lcdScreen == 1) {
      l0 = String("DO:") + (lcdDO >= 0 ? String(lcdDO, 2) : "--") + "mg/L";
      l1 = String("Turb:") + (lcdTurbidity >= 0 ? String(lcdTurbidity, 0) : "--") + " NTU";
    } else if (lcdScreen == 2) {
      l0 = String("Water:") + (lcdWater >= 0 ? String(lcdWater, 0) + "cm" : "--");
      l1 = String("Hopper:") + (lcdFeed >= 0 ? String(lcdFeed, 0) + "%" : "--");
    } else if (lcdScreen == 3) {
      getNextScheduleLines(l0, l1);
    } else {
      l0 = "Water quality!";
      l1 = liveWaterQualityWarning;
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
      unsigned long now = millis();
      if (now - lastNonPhPollTime >= NON_PH_SENSOR_POLL_MS) {
        const unsigned long scanStartedMs = now;
        lastNonPhPollTime = scanStartedMs;
        readNonPHSensors();
        now = millis();
        if (now - scanStartedMs >= NON_PH_SENSOR_POLL_MS) {
          lastNonPhPollTime = now;  // Long scan: wait a full interval, no catch-up.
        }
      }
      now = millis();
      if (now - lastPhPollTime >= PH_SENSOR_POLL_MS) {
        const unsigned long scanStartedMs = now;
        lastPhPollTime = scanStartedMs;
        readPHSensorSafely();
        now = millis();
        if (now - scanStartedMs >= PH_SENSOR_POLL_MS) {
          lastPhPollTime = now;
        }
      }
      if (publishLiveAverageWindow() && sensorOutputEnabled) printSensorReading();
    }
    // Check frequently, but schedule each group from its own last completion
    // time so a slow scan never causes catch-up bursts.
    vTaskDelay(pdMS_TO_TICKS(10));
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
  if (!hasCurrentTankAssignment()) return false;
  if (!ensureFirebaseReady()) return false;

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
  if (!hasCurrentTankAssignment()) return;
  if (!ensureFirebaseReady()) return;

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
  if (!hasCurrentTankAssignment()) return;
  if (!ensureFirebaseReady()) return;

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
  if (!hasCurrentTankAssignment() || WiFi.status() != WL_CONNECTED ||
      cloudOutage || !ensureFirebaseReady()) {
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
