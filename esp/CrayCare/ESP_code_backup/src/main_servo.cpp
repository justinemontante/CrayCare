/*
 * ============================================================
 *  CrayCare — ESP32 Feeder-Only (Fast Compile)
 *  Board   : ESP32 DevKit
 *  Flow    : Flutter App writes commands/schedules -> ESP32
 *            ESP32 writes feeder status + logs -> Flutter reads
 * ============================================================
 *
 *  WiFi credentials: stored in NVS via Preferences.
 *    First boot: enter via Serial Monitor.
 *    Reset: send "RESET_WIFI" over Serial.
 *
 *  Firebase paths:
 *    /feeder/commands   -> Flutter pushes, ESP32 polls & deletes
 *    /feeder/status     -> ESP32 writes every 5s
 *    /feeder/schedules  -> Flutter writes, ESP32 reads
 *    /feeder/logs       -> ESP32 pushes
 *
 *  Servo: GPIO13, direct LEDC PWM (no ESP32Servo library)
 */

#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <Preferences.h>
#include <time.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// ============================================================
//  WIFI SETTINGS — NVS via Preferences
// ============================================================
Preferences prefs;
String ssid;
String pass;

// ============================================================
//  FIREBASE SETTINGS
// ============================================================
#define FIREBASE_API_KEY "AIzaSyCjDOkzE4iubiLx_xA2YufMUMo6jgIKcaw"
#define FIREBASE_DATABASE_URL "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app"

#define FIREBASE_FEEDER_COMMANDS_PATH  "/feeder/commands"
#define FIREBASE_FEEDER_STATUS_PATH    "/feeder/status"
#define FIREBASE_FEEDER_SCHEDULES_PATH "/feeder/schedules"
#define FIREBASE_FEEDER_LOGS_PATH      "/feeder/logs"

// Feeder timing
#define FEEDER_CMD_INTERVAL_MS 300
#define FEEDER_STATUS_INTERVAL_MS 5000
#define FEEDER_SCHEDULE_SYNC_MS 30000
#define FEEDER_SCHEDULE_CHECK_MS 1000
#define FEEDER_MAX_SCHEDULES 20

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

bool firebaseReady = false;

// ============================================================
//  LEDC SERVO CONTROL (no library needed)
// ============================================================
#define FEEDER_SERVO_PIN 13
#define SERVO_LEDC_CHANNEL 0
#define SERVO_LEDC_FREQ 50
#define SERVO_LEDC_RESOLUTION 16
#define SERVO_PULSE_MIN 500
#define SERVO_PULSE_MAX 2500

int _servoAngleToDuty(int angle) {
  angle = constrain(angle, 0, 180);
  int pulseWidth = map(angle, 0, 180, SERVO_PULSE_MIN, SERVO_PULSE_MAX);
  return (int)((float)pulseWidth / 20000.0f * 65535.0f);
}

void _setServoAngle(int angle) {
  ledcWrite(SERVO_LEDC_CHANNEL, _servoAngleToDuty(angle));
}

void reinitServoPWM() {
  ledcDetachPin(FEEDER_SERVO_PIN);
  ledcSetup(SERVO_LEDC_CHANNEL, SERVO_LEDC_FREQ, SERVO_LEDC_RESOLUTION);
  ledcAttachPin(FEEDER_SERVO_PIN, SERVO_LEDC_CHANNEL);
  _setServoAngle(0);
}

// ============================================================
//  FEEDER STATE
// ============================================================
bool feederAutoMode = true;
int feederHopperLevel = 100;
unsigned long feederLastFeedEpoch = 0;
bool feederIsRunning = false;
String feederFeedSource = "";
int feederFeedCount = 0;
String feederError = "";

unsigned long lastServoRefreshMs = 0;

enum FeederRunState {
  FEEDER_IDLE,
  FEEDER_FORWARD,
  FEEDER_BACKWARD,
  FEEDER_DONE
};
FeederRunState feederRunState = FEEDER_IDLE;
int feederCurrentCycle = 0;
int feederMaxCycles = 1;
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
//  WIFI
// ============================================================
void connectWiFi() {
  prefs.begin("wifi", true);
  ssid = prefs.getString("ssid", "");
  pass = prefs.getString("pass", "");
  prefs.end();

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

// ============================================================
//  TIME (NTP)
// ============================================================
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

// ============================================================
//  FIREBASE
// ============================================================
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

unsigned long getEpochMillis() {
  time_t now;
  time(&now);
  if (now < 1700000000) return 0;
  return (unsigned long)now * 1000UL;
}

// ============================================================
//  Forward declarations
// ============================================================
void startFeed(String source);
void pushFeederLog(String action, String type);

// ============================================================
//  FEEDER — Commands
// ============================================================
void processFeederCommands() {
  if (!ensureFirebaseReady()) return;

  FirebaseJson json;
  if (!Firebase.RTDB.getJSON(&fbdo, FIREBASE_FEEDER_COMMANDS_PATH, &json)) return;

  size_t count = json.iteratorBegin();
  if (count == 0) { json.iteratorEnd(); return; }

  struct CmdEntry { String key, action, mode; };
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

  for (int i = 0; i < entryCount; i++) {
    CmdEntry& e = entries[i];
    Serial.printf("[FEEDER CMD] %s (mode=%s) key=%s\n",
      e.action.c_str(), e.mode.c_str(), e.key.c_str());

    if (e.action == "feed_now") {
      startFeed("manual");
    } else if (e.action == "set_mode" && e.mode != "") {
      feederAutoMode = (e.mode == "auto");
      Serial.printf("[FEEDER] Mode -> %s\n", feederAutoMode ? "AUTO" : "MANUAL");
    }

    String cmdPath = String(FIREBASE_FEEDER_COMMANDS_PATH) + "/" + e.key;
    if (!Firebase.RTDB.deleteNode(&fbdo, cmdPath.c_str())) {
      Serial.printf("[FEEDER] Delete cmd failed: %s\n", fbdo.errorReason().c_str());
    }
  }
}

// ============================================================
//  FEEDER — Status
// ============================================================
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
  json.set("feedCount", feederFeedCount);
  json.set("lastSeen", (int)epochMs);
  json.set("feederError", feederError);

  if (!Firebase.RTDB.updateNode(&fbdo, FIREBASE_FEEDER_STATUS_PATH, &json)) {
    if (fbdo.httpConnected()) {
      Serial.printf("[FEEDER STATUS ERROR] %s\n", fbdo.errorReason().c_str());
    }
  }
}

// ============================================================
//  FEEDER — Schedule Sync
// ============================================================
void syncFeederSchedules() {
  if (!ensureFirebaseReady()) return;

  FirebaseJson json;
  if (!Firebase.RTDB.getJSON(&fbdo, FIREBASE_FEEDER_SCHEDULES_PATH, &json)) {
    feederScheduleCount = 0;
    return;
  }
  if (!fbdo.httpConnected()) { feederScheduleCount = 0; return; }

  size_t count = json.iteratorBegin();
  if (count == 0) { feederScheduleCount = 0; json.iteratorEnd(); return; }

  feederScheduleCount = 0;
  for (size_t i = 0; i < count && feederScheduleCount < FEEDER_MAX_SCHEDULES; i++) {
    int iterType;
    String iterKey, iterValue;
    json.iteratorGet(i, iterType, iterKey, iterValue);

    FeedSchedule& s = feederSchedules[feederScheduleCount];
    s.key = iterKey;

    FirebaseJson item;
    item.setJsonData(iterValue);
    FirebaseJsonData d;

    String timeStr = "6:00", ampm = "AM";
    if (item.get(d, "time")) timeStr = d.stringValue;
    if (item.get(d, "ampm")) ampm = d.stringValue;

    int colon = timeStr.indexOf(':');
    if (colon < 0) continue;
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

// ============================================================
//  FEEDER — Scheduled Feed Check
// ============================================================
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
    if (schedMin == currentMin) {
      unsigned long nowEpoch = (unsigned long)now;
      if (nowEpoch - feederLastFeedEpoch >= 60) {
        Serial.printf("[FEEDER] Scheduled feed at %02d:%02d\n", s.hour24, s.minute);
        startFeed("scheduled");
      }
    }
  }
}

// ============================================================
//  FEEDER — Non-blocking State Machine
// ============================================================
void startFeed(String source) {
  if (feederRunState != FEEDER_IDLE) {
    feederError = "stuck";
    Serial.println("[FEEDER] ERROR: Already running, setting stuck error");
    return;
  }

  feederError = "";
  time_t now;
  time(&now);
  feederLastFeedEpoch = (unsigned long)now;
  feederFeedSource = source;
  feederIsRunning = true;
  feederCurrentCycle = 0;
  feederRunState = FEEDER_FORWARD;
  feederStartMs = millis();
  feederStepMs = feederStartMs;

  sendFeederStatus();
  Serial.printf("[FEEDER] Start feed (source=%s)\n", source.c_str());
}

void processFeederTick() {
  if (feederRunState == FEEDER_IDLE) return;

  unsigned long now = millis();

  // ─── Timeout: if stuck >5s in any non-IDLE state ───
  if (now - feederStepMs >= 5000) {
    feederError = "timeout";
    feederIsRunning = false;
    feederRunState = FEEDER_IDLE;
    reinitServoPWM();
    sendFeederStatus();
    Serial.printf("[FEEDER] ERROR: Timeout, reset to IDLE (error=%s)\n", feederError.c_str());
    return;
  }

  switch (feederRunState) {

    case FEEDER_FORWARD:
      _setServoAngle(180);
      feederStepMs = now;
      feederRunState = FEEDER_BACKWARD;
      Serial.printf("[FEEDER] Forward %d/%d\n",
        feederCurrentCycle + 1, feederMaxCycles);
      break;

    case FEEDER_BACKWARD:
      if (now - feederStepMs >= 200) {
        _setServoAngle(0);
        feederStepMs = now;
        feederRunState = FEEDER_DONE;
        Serial.printf("[FEEDER] Backward %d/%d\n",
          feederCurrentCycle + 1, feederMaxCycles);
      }
      break;

    case FEEDER_DONE:
      if (now - feederStepMs >= 300) {
        reinitServoPWM();
        feederCurrentCycle++;
        feederHopperLevel -= 9;
        if (feederHopperLevel < 0) feederHopperLevel = 0;
        feederFeedCount++;
        feederIsRunning = false;
        feederRunState = FEEDER_IDLE;
        sendFeederStatus();
        pushFeederLog(
          feederFeedSource == "scheduled" ? "Dispensed feed (Scheduled)" : "Dispensed feed (Manual)",
          feederAutoMode ? "auto" : "manual"
        );
        feederFeedSource = "";
        Serial.println("[FEEDER] Feed complete");
      }
      break;

    default:
      feederRunState = FEEDER_IDLE;
      break;
  }
}

// ============================================================
//  FEEDER — Logs
// ============================================================
void pushFeederLog(String action, String type) {
  if (!ensureFirebaseReady()) return;

  time_t now;
  time(&now);
  struct tm* timeinfo = localtime(&now);

  int h12 = timeinfo->tm_hour % 12;
  if (h12 == 0) h12 = 12;
  String ampm = timeinfo->tm_hour >= 12 ? "PM" : "AM";
  char timeBuf[10];
  sprintf(timeBuf, "%d:%02d %s", h12, timeinfo->tm_min, ampm.c_str());

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

// ============================================================
//  FEEDER — Init
// ============================================================
void initFeeder() {
  ledcSetup(SERVO_LEDC_CHANNEL, SERVO_LEDC_FREQ, SERVO_LEDC_RESOLUTION);
  ledcAttachPin(FEEDER_SERVO_PIN, SERVO_LEDC_CHANNEL);
  _setServoAngle(0);
  feederIsRunning = false;
  feederRunState = FEEDER_IDLE;
  feederCurrentCycle = 0;

  Serial.println("[FEEDER] Testing servo...");
  _setServoAngle(90);
  delay(800);
  _setServoAngle(0);
  delay(500);
  Serial.println("[FEEDER] Servo initialized OK");
}

// ============================================================
//  SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  connectWiFi();
  initTime();
  connectFirebase();
  initFeeder();
  syncFeederSchedules();

  Serial.println("============================================");
  Serial.println("  CrayCare — Feeder Only");
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
    if (cmd == "CLEAR_ERROR") {
      feederError = "";
      Serial.println("[FEEDER] Error cleared");
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

  // ─── Servo refresh: keep PWM active when idle ───
  if (feederRunState == FEEDER_IDLE && now - lastServoRefreshMs >= 100) {
    lastServoRefreshMs = now;
    _setServoAngle(0);
  }
}
