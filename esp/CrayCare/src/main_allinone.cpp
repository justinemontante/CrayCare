#include "common.h"
#include "servo_ctrl.h"
#include "turbidity.h"
#include "ph_ctrl.h"
#include "do_ctrl.h"
#include <LiquidCrystal_I2C.h>
#include <Wire.h>

// =============================================================================
// CONFIGURATION
// =============================================================================

// --- Relay pins ---
#define PIN_A1 26
#define PIN_A2 27
#define PIN_P  14

// --- Sensor pins ---
#define TRIG_PIN        32
#define ECHO_PIN        33
// DS18B20: GPIO 4, Turbidity: GPIO 34 (via turbidity.h)
// pH: GPIO 35 (via ph_ctrl.h), DO: GPIO 36 SVP (via do_ctrl.h)
// LCD I2C: SDA=21, SCL=22

// --- Timing (ms) ---
#define SENSOR_INTERVAL     1000
#define PUBLISH_INTERVAL    5000
#define HISTORY_INTERVAL    600000
#define LCD_INTERVAL        3000
#define MODES_POLL_INTERVAL 3000
#define CMD_POLL_INTERVAL   5000
#define STATUS_INTERVAL     30000

// --- HC-SR04 ---
#define SOUND_SPEED_CM_US   0.034
#define MAX_DIST_CM         400
#define ECHO_TIMEOUT_US     30000
#define TANK_DEPTH_CM       100.0f  // SET THIS: distance from sensor to tank bottom (cm)

// --- LCD ---
#define LCD_ADDR    0x27
#define LCD_COLS    16
#define LCD_ROWS    2

// =============================================================================
// RELAY / SERVO GLOBALS
// =============================================================================

#define DEV_A1 "aerator1"
#define DEV_A2 "aerator2"
#define DEV_P  "pump"

enum RMode { RM_OFF, RM_ON, RM_AUTO };

struct RelayCtx {
    int pin;
    RMode mode;
    bool active;
    const char* devId;
    const char* label;
};

static RelayCtx relays[3] = {
    {PIN_A1, RM_OFF, false, DEV_A1, "Aerator 1"},
    {PIN_A2, RM_OFF, false, DEV_A2, "Aerator 2"},
    {PIN_P,  RM_OFF, false, DEV_P,  "Water Pump"},
};

static FirebaseData fbW;
static bool feedBusy = false;
static int  feedCount = 0;
static unsigned long lastModesPoll = 0;
static unsigned long lastCmdPoll = 0;
static unsigned long lastStatusWrite = 0;

// =============================================================================
// SENSOR / LCD GLOBALS
// =============================================================================

static FirebaseData fbS;
static LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS);

static unsigned long lastSensorRead = 0;
static unsigned long lastPublish = 0;
static unsigned long lastHistoryPublish = 0;
static unsigned long lastLcdUpdate = 0;
static int lcdPage = 0;
static uint8_t lcdAddress = 0;

static float currentTemp = 0;
static float currentTurbV = 0;
static float currentTurbNTU = 0;
static bool currentTurbAir = false;
static float currentPH = 7.0;
static float currentDO = 5.0;
static float currentWaterCm = -1;
static bool debugMode = false;

static bool initialConnectDone = false;
static unsigned long lastWifiRetry = 0;

// --- Feeder schedule ---
static int feedHour1 = 9, feedMin1 = 0;
static int feedHour2 = 18, feedMin2 = 0;
static bool fedAM = false, fedPM = false;
static int lastFeedCheckMin = -1;

// --- Schedule sync from Firebase ---
static unsigned long lastSchedPoll = 0;
static unsigned long lastSchedSync = 0;
static int numFbSchedules = 0;
#define SCHED_POLL_INTERVAL 30000  // poll Firebase every 30s

static void loadFeederSchedule();
static void saveFeederSchedule();

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

static void applyMode(int idx, const String& modeStr);
static void doFeed(const String& cmdPath);
static void scanI2C();
static bool detectLCD();
static float readWaterLevelCm();
static void publishSensors();
static void publishHistory();
static void updateLCD();
static void printHelp();
static void processSerialCommands();
static void loadFeederSchedule();
static void saveFeederSchedule();
static void checkFeederSchedule();
static void pollFirebaseSchedules();
static void markScheduleDispatched();

// =============================================================================
// I2C HELPERS
// =============================================================================

static void scanI2C() {
    Serial.println("[I2C] Scanning 0x08-0x77...");
    Wire.begin(21, 22);
    for (uint8_t addr = 8; addr < 0x78; addr++) {
        Wire.beginTransmission(addr);
        if (Wire.endTransmission() == 0) {
            Serial.printf("[I2C] Found 0x%02X\n", addr);
        }
    }
    Serial.println("[I2C] Done");
}

static bool detectLCD() {
    Wire.begin(21, 22);
    static const uint8_t addrs[] = {0x27, 0x3F};
    for (size_t i = 0; i < 2; i++) {
        uint8_t addr = addrs[i];
        Wire.beginTransmission(addr);
        if (Wire.endTransmission() == 0) {
            lcdAddress = addr;
            Serial.printf("[LCD] Found at 0x%02X\n", addr);
            return true;
        }
    }
    Serial.println("[LCD] Not detected (check wiring: 5V, SDA=21, SCL=22)");
    return false;
}

// =============================================================================
// HC-SR04
// =============================================================================

static float readWaterLevelCm() {
    digitalWrite(TRIG_PIN, LOW);
    delayMicroseconds(2);
    digitalWrite(TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(TRIG_PIN, LOW);
    long duration = pulseIn(ECHO_PIN, HIGH, ECHO_TIMEOUT_US);
    if (duration == 0) return -1;
    float distToWater = duration * SOUND_SPEED_CM_US / 2.0;
    if (distToWater < 2 || distToWater > MAX_DIST_CM) return -1;
    float waterDepth = TANK_DEPTH_CM - distToWater;
    if (waterDepth < 0) waterDepth = 0;
    if (waterDepth > TANK_DEPTH_CM) waterDepth = TANK_DEPTH_CM;
    return waterDepth;
}

// =============================================================================
// RELAY / FEEDER FUNCTIONS
// =============================================================================

static String fmtTime() {
    struct tm t;
    if (!getLocalTime(&t)) return "--:-- --";
    int h12 = t.tm_hour % 12;
    if (h12 == 0) h12 = 12;
    char b[10];
    snprintf(b, sizeof(b), "%d:%02d %s", h12, t.tm_min, t.tm_hour >= 12 ? "PM" : "AM");
    return String(b);
}

static String fmtDate() {
    struct tm t;
    if (!getLocalTime(&t)) return "--- --, ----";
    const char* ms[] = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
    char b[20];
    snprintf(b, sizeof(b), "%s %d, %d", ms[t.tm_mon], t.tm_mday, 1900 + t.tm_year);
    return String(b);
}

static void logDeviceAction(const char* devId, const char* action, const char* type) {
    if (!Firebase.ready()) return;
    FirebaseJson j;
    j.add("action", action); j.add("type", type);
    j.add("time", fmtTime()); j.add("date", fmtDate());
    j.add("userName", "ESP32");
    j.add("timestamp", (double)(getEpochMillis() / 1000));
    Firebase.RTDB.push(&fbW, String("/devices/logs/") + devId, &j);
}

static void logFeedAction(const char* action, const char* type) {
    if (!Firebase.ready()) return;
    FirebaseJson j;
    j.add("action", action); j.add("type", type);
    j.add("time", fmtTime()); j.add("date", fmtDate());
    j.add("userName", "ESP32");
    j.add("timestamp", (double)(getEpochMillis() / 1000));
    Firebase.RTDB.push(&fbW, "/feeder/logs", &j);
}

static void applyMode(int idx, const String& modeStr) {
    RelayCtx* r = &relays[idx];
    String m = modeStr; m.toLowerCase();
    RMode newMode; bool newActive;
    if (m == "on") { newMode = RM_ON; newActive = true; }
    else if (m == "off") { newMode = RM_OFF; newActive = false; }
    else { newMode = RM_AUTO; newActive = false; }
    if (r->mode == newMode && r->active == newActive) return;
    bool wasActive = r->active;
    r->mode = newMode; r->active = newActive;
    digitalWrite(r->pin, newActive ? LOW : HIGH);
    Serial.printf("[RELAY] %s (GPIO%d) = %s\n", r->label, r->pin, newActive ? "ON" : "OFF");
    if (wasActive != newActive && newMode == RM_AUTO) {
        logDeviceAction(r->devId, newActive ? "Switched ON (AUTO)" : "Switched OFF (AUTO)", "auto");
    }
}

static void pollModes() {
    if (!Firebase.ready()) return;
    unsigned long now = millis();
    if (now - lastModesPoll < MODES_POLL_INTERVAL) return;
    lastModesPoll = now;
    FirebaseJson j;
    if (!Firebase.RTDB.getJSON(&fbW, "/devices/modes", &j)) return;
    FirebaseJsonData d;
    if (j.get(d, DEV_A1)) { Serial.printf("[MODES] %s=%s\n", DEV_A1, d.stringValue.c_str()); applyMode(0, d.stringValue); }
    if (j.get(d, DEV_A2)) { Serial.printf("[MODES] %s=%s\n", DEV_A2, d.stringValue.c_str()); applyMode(1, d.stringValue); }
    if (j.get(d, DEV_P))  { Serial.printf("[MODES] %s=%s\n", DEV_P, d.stringValue.c_str()); applyMode(2, d.stringValue); }
}

static void doFeed(const String& cmdPath) {
    if (feedBusy) return;
    feedBusy = true;
    if (Firebase.ready()) {
        Firebase.RTDB.setBool(&fbW, "/feeder/status/isRunning", true);
        Firebase.RTDB.deleteNode(&fbW, cmdPath);
    }
    executeServoCycle();
    feedCount++;
    markScheduleDispatched();
    if (Firebase.ready()) {
        FirebaseJson j;
        j.add("isRunning", false); j.add("feedCount", feedCount);
        j.add("lastSeen", (double)getEpochMillis());
        j.add("hopperLevel", 100.0); j.add("feedSource", "esp32");
        j.add("feederError", "");
        Firebase.RTDB.setJSON(&fbW, "/feeder/status", &j);
        logFeedAction("Feed dispensed", "auto");
    }
    feedBusy = false;
}

static void pollCommands() {
    if (!Firebase.ready()) return;
    unsigned long now = millis();
    if (now - lastCmdPoll < CMD_POLL_INTERVAL) return;
    lastCmdPoll = now;
    FirebaseJson j;
    if (!Firebase.RTDB.getJSON(&fbW, "/feeder/commands", &j)) return;
    FirebaseJsonData d;
    size_t n = j.iteratorBegin();
    if (n > 0) Serial.printf("[CMD-POLL] %u command(s)\n", n);
    for (size_t i = 0; i < n; i++) {
        int itType; String key, value;
        j.iteratorGet(i, itType, key, value);
        if (itType == FirebaseJson::JSON_OBJECT) {
            FirebaseJson sub; sub.setJsonData(value);
            sub.get(d, "action");
            if (d.stringValue == "feed_now") {
                sub.get(d, "timestamp");
                int64_t ts = (int64_t)d.doubleValue;
                int64_t nowMs = (int64_t)getEpochMillis();
                String path = String("/feeder/commands/") + key;
                if (nowMs > 0 && nowMs - ts < 30000) {
                    Serial.printf("[CMD-POLL] Feed: %s\n", key.c_str());
                    doFeed(path);
                } else if (nowMs > 0) {
                    Serial.printf("[CMD-POLL] Stale: %s\n", key.c_str());
                    Firebase.RTDB.deleteNode(&fbW, path);
                }
            }
        }
    }
    j.iteratorEnd();
}

static void writeStatus() {
    if (!Firebase.ready()) return;
    FirebaseJson j;
    j.add("isRunning", feedBusy); j.add("feedCount", feedCount);
    j.add("lastSeen", (double)getEpochMillis());
    j.add("hopperLevel", 100.0); j.add("feedSource", "esp32");
    j.add("feederError", "");
    Firebase.RTDB.setJSON(&fbW, "/feeder/status", &j);
}

// =============================================================================
// FIREBASE PUBLISH (SENSOR DATA)
// =============================================================================

static void publishSensors() {
    if (!Firebase.ready()) return;
    FirebaseJson j;
    j.add("temperature", currentTemp);
    j.add("phLevel", currentPH);
    j.add("dissolvedOxygen", currentDO);
    j.add("turbidity", currentTurbNTU);
    j.add("waterLevel", currentWaterCm >= 0 ? currentWaterCm : 0);
    j.add("timestamp", (double)(getEpochMillis() / 1000));
    if (Firebase.RTDB.setJSON(&fbS, "/sensor_readings/latest", &j)) {
        Serial.println("[FB] Sensor data published");
    } else {
        Serial.printf("[FB] Sensor publish failed: %s\n", fbS.errorReason());
    }
}

static String fmtDatePath() {
    struct tm t;
    if (!getLocalTime(&t)) return "unknown";
    char b[12];
    snprintf(b, sizeof(b), "%04d-%02d-%02d", 1900 + t.tm_year, t.tm_mon + 1, t.tm_mday);
    return String(b);
}

static void publishHistory() {
    if (!Firebase.ready()) return;
    FirebaseJson j;
    j.add("temperature", currentTemp);
    j.add("phLevel", currentPH);
    j.add("dissolvedOxygen", currentDO);
    j.add("turbidity", currentTurbNTU);
    j.add("waterLevel", currentWaterCm >= 0 ? currentWaterCm : 0);
    j.add("timestamp", (double)(getEpochMillis() / 1000));
    String path = String("/sensor_readings/history/") + fmtDatePath();
    if (Firebase.RTDB.pushJSON(&fbS, path, &j)) {
        Serial.println("[FB] History record pushed");
    } else {
        Serial.printf("[FB] History push failed: %s\n", fbS.errorReason());
    }
}

// =============================================================================
// FEEDER SCHEDULE
// =============================================================================

static void loadFeederSchedule() {
    prefs.begin("feedtime", false);
    feedHour1 = prefs.getInt("hr1", 9);
    feedMin1 = prefs.getInt("min1", 0);
    feedHour2 = prefs.getInt("hr2", 18);
    feedMin2 = prefs.getInt("min2", 0);
    prefs.end();
    lastSchedSync = 0;
    Serial.printf("[FEEDER] Schedule loaded: %02d:%02d, %02d:%02d\n", feedHour1, feedMin1, feedHour2, feedMin2);
}

static void saveFeederSchedule() {
    prefs.begin("feedtime", false);
    prefs.putInt("hr1", feedHour1);
    prefs.putInt("min1", feedMin1);
    prefs.putInt("hr2", feedHour2);
    prefs.putInt("min2", feedMin2);
    prefs.end();
    Serial.println("[FEEDER] Schedule saved to NVS");
}

static String fmtTime12(int hour, int min) {
    int h12 = hour % 12;
    if (h12 == 0) h12 = 12;
    char b[10];
    snprintf(b, sizeof(b), "%d:%02d%s", h12, min, hour >= 12 ? "PM" : "AM");
    return String(b);
}

static void checkFeederSchedule() {
    struct tm t;
    if (!getLocalTime(&t)) return;
    int curH = t.tm_hour;
    int curM = t.tm_min;
    if (curM != lastFeedCheckMin) {
        lastFeedCheckMin = curM;
        fedAM = false;
        fedPM = false;
    }
    if (!feedBusy) {
        if (!fedAM && curH == feedHour1 && curM == feedMin1) {
            Serial.printf("[FEEDER] Auto-feed AM (%s)\n", fmtTime12(feedHour1, feedMin1).c_str());
            doFeed("-");
            fedAM = true;
        }
        if (!fedPM && curH == feedHour2 && curM == feedMin2) {
            Serial.printf("[FEEDER] Auto-feed PM (%s)\n", fmtTime12(feedHour2, feedMin2).c_str());
            doFeed("-");
            fedPM = true;
        }
    }
}

static void pollFirebaseSchedules() {
    if (!Firebase.ready()) return;
    unsigned long now = millis();
    if (now - lastSchedPoll < SCHED_POLL_INTERVAL) return;
    lastSchedPoll = now;

    FirebaseJson j;
    if (!Firebase.RTDB.getJSON(&fbW, "/feeder/schedules", &j)) {
        Serial.println("[SCHED] Fetch failed");
        return;
    }

    struct FbSched { int hour24; int min; };
    FbSched scheds[8];
    int count = 0;

    size_t n = j.iteratorBegin();
    for (size_t i = 0; i < n && count < 8; i++) {
        int itType; String key, value;
        j.iteratorGet(i, itType, key, value);
        if (itType != FirebaseJson::JSON_OBJECT) continue;

        FirebaseJson sub; sub.setJsonData(value);
        FirebaseJsonData d;
        bool enabled = false;
        String timeStr = "", ampmStr = "";
        if (sub.get(d, "enabled")) {
            String ev = d.stringValue;
            enabled = (ev == "true" || ev == "1");
        }
        if (sub.get(d, "time")) timeStr = d.stringValue;
        if (sub.get(d, "ampm")) ampmStr = d.stringValue;
        if (!enabled || timeStr.length() == 0) continue;

        int colon = timeStr.indexOf(':');
        if (colon < 0) continue;
        int h = timeStr.substring(0, colon).toInt();
        int m = timeStr.substring(colon + 1).toInt();
        if (ampmStr == "PM" && h != 12) h += 12;
        if (ampmStr == "AM" && h == 12) h = 0;

        scheds[count].hour24 = h;
        scheds[count].min = m;
        count++;
    }
    j.iteratorEnd();

    numFbSchedules = count;

    // Sort by time-of-day
    for (int i = 0; i < count - 1; i++) {
        for (int j2 = i + 1; j2 < count; j2++) {
            int ti = scheds[i].hour24 * 60 + scheds[i].min;
            int tj = scheds[j2].hour24 * 60 + scheds[j2].min;
            if (ti > tj) { FbSched tmp = scheds[i]; scheds[i] = scheds[j2]; scheds[j2] = tmp; }
        }
    }

    int h1 = 9, m1 = 0, h2 = 18, m2 = 0;
    if (count >= 1) { h1 = scheds[0].hour24; m1 = scheds[0].min; }
    if (count >= 2) { h2 = scheds[1].hour24; m2 = scheds[1].min; }

    if (h1 != feedHour1 || m1 != feedMin1 || h2 != feedHour2 || m2 != feedMin2) {
        feedHour1 = h1; feedMin1 = m1; feedHour2 = h2; feedMin2 = m2;
        saveFeederSchedule();
        Serial.printf("[SCHED] Synced: %02d:%02d, %02d:%02d (%d schedule(s))\n",
            feedHour1, feedMin1, feedHour2, feedMin2, count);
    }
    lastSchedSync = now;
}

static void markScheduleDispatched() {
    struct tm t;
    if (!getLocalTime(&t)) return;
    char dateKey[20];
    snprintf(dateKey, sizeof(dateKey), "%04d/%02d/%02d",
        1900 + t.tm_year, t.tm_mon + 1, t.tm_mday);
    Firebase.RTDB.setBool(&fbW, String("/feeder/dispatched/") + dateKey + "/esp_local", true);
}

// =============================================================================
// LCD
// =============================================================================

static void updateLCD() {
    if (lcdAddress == 0) return;
    lcdPage = (lcdPage + 1) % 3;
    lcd.clear();

    if (lcdPage == 0) {
        lcd.setCursor(0, 0);
        lcd.printf("pH:%.1f DO:%.1f", currentPH, currentDO);
        lcd.setCursor(0, 1);
        lcd.printf("T:%.1fC W:%.0fcm", currentTemp, currentWaterCm >= 0 ? currentWaterCm : 0);
    } else if (lcdPage == 1) {
        lcd.setCursor(0, 0);
        lcd.printf("Turb:%.0fNTU", currentTurbNTU);
        lcd.setCursor(0, 1);
        String t1 = fmtTime12(feedHour1, feedMin1);
        String t2 = fmtTime12(feedHour2, feedMin2);
        lcd.printf("FD:%s %s", t1.c_str(), t2.c_str());
    } else {
        bool a1 = relays[0].active, a2 = relays[1].active, p = relays[2].active;
        bool schedOk = (millis() - lastSchedSync < 120000);
        lcd.setCursor(0, 0);
        lcd.printf("A1:%s A2:%s", a1 ? "ON" : "OFF", a2 ? "ON" : "OFF");
        lcd.setCursor(0, 1);
        lcd.printf("P:%s Sched:%s", p ? "ON" : "OFF", schedOk ? "OK" : "--");
    }
}

// =============================================================================
// SERIAL COMMANDS
// =============================================================================

static void printHelp() {
    Serial.println();
    Serial.println("========== CrayCare All-in-One Commands ==========");
    Serial.println("--- Relays ---");
    Serial.println("  n1on / n1off         Aerator 1 ON/OFF");
    Serial.println("  n2on / n2off         Aerator 2 ON/OFF");
    Serial.println("  n3on / n3off         Pump ON/OFF");
    Serial.println("  relay status         Show relay states");
    Serial.println("");
    Serial.println("--- Servo / Feeder ---");
    Serial.println("  servopause <ms>      Set servo open pause");
    Serial.println("  servocycle           Run one feed cycle");
    Serial.println("  feedtime1 <H> <M>    Set AM feed time (24h format)");
    Serial.println("  feedtime2 <H> <M>    Set PM feed time (24h format)");
    Serial.println("  feedtime             Show current feed schedule");
    Serial.println("  schedulesync         Force Firebase schedule sync");
    Serial.println("");
    Serial.println("--- WiFi ---");
    Serial.println("  wifissid <SSID>      Save WiFi SSID");
    Serial.println("  wifipass <PASS>      Save WiFi password");
    Serial.println("  wifireset            Reset WiFi credentials");
    Serial.println("  wifistatus           Show stored credentials");
    Serial.println("");
    Serial.println("--- Turbidity Calibration ---");
    Serial.println("  turbclear <V>        Voltage for 0 NTU");
    Serial.println("  turbdirty <V>        Voltage for ~500 NTU");
    Serial.println("  turbair <V>          Air threshold voltage");
    Serial.println("");
    Serial.println("--- pH Calibration ---");
    Serial.println("  phcal7               Calibrate at pH 7.0 buffer");
    Serial.println("  phcal4               Calibrate at pH 4.0 buffer");
    Serial.println("");
    Serial.println("--- DO Calibration ---");
    Serial.println("  doclear              Calibrate in air (100% sat)");
    Serial.println("");
    Serial.println("--- Debug ---");
    Serial.println("  debugmode [0/1]      Show raw voltage on LCD/serial");
    Serial.println("  debugstatus          Show system status");
    Serial.println("");
    Serial.println("--- System ---");
    Serial.println("  restart              Reboot ESP32");
    Serial.println("  i2cscan              Scan I2C bus");
    Serial.println("  help / ?             This list");
    Serial.println("=================================================");
    Serial.println();
}

static void processSerialCommands() {
    if (!Serial.available()) return;
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.length() == 0) return;
    int sp = line.indexOf(' ');
    String cmd = (sp == -1) ? line : line.substring(0, sp);
    String arg = (sp == -1) ? "" : line.substring(sp + 1);
    cmd.toLowerCase();

    if (cmd == "help" || cmd == "?") { printHelp(); return; }

    // --- Relays ---
    if (cmd == "n1on")  { digitalWrite(PIN_A1, LOW);  Serial.println("[CMD] Aerator 1 ON"); return; }
    if (cmd == "n1off") { digitalWrite(PIN_A1, HIGH); Serial.println("[CMD] Aerator 1 OFF"); return; }
    if (cmd == "n2on")  { digitalWrite(PIN_A2, LOW);  Serial.println("[CMD] Aerator 2 ON"); return; }
    if (cmd == "n2off") { digitalWrite(PIN_A2, HIGH); Serial.println("[CMD] Aerator 2 OFF"); return; }
    if (cmd == "n3on")  { digitalWrite(PIN_P, LOW);   Serial.println("[CMD] Pump ON"); return; }
    if (cmd == "n3off") { digitalWrite(PIN_P, HIGH);  Serial.println("[CMD] Pump OFF"); return; }
    if (cmd == "relay" && arg == "status") {
        for (int i = 0; i < 3; i++) {
            Serial.printf("  %s (GPIO%d): %s [mode: %s]\n",
                relays[i].label, relays[i].pin,
                relays[i].active ? "ON" : "OFF",
                relays[i].mode == RM_ON ? "on" : relays[i].mode == RM_OFF ? "off" : "auto");
        }
        return;
    }

    // --- Servo ---
    if (cmd == "servopause") {
        uint32_t v = (uint32_t)arg.toInt();
        if (v > 0) { servoPauseMs = v; Serial.printf("[CMD] Servo pause = %u ms\n", v); }
        return;
    }
    if (cmd == "servocycle") {
        Serial.println("[CMD] Manual feed cycle");
        executeServoCycle();
        return;
    }
    if (cmd == "feedtime1") {
        int sp2 = arg.indexOf(' ');
        if (sp2 > 0) {
            int h = arg.substring(0, sp2).toInt();
            int m = arg.substring(sp2 + 1).toInt();
            if (h >= 0 && h < 24 && m >= 0 && m < 60) {
                feedHour1 = h; feedMin1 = m;
                saveFeederSchedule();
                Serial.printf("[CMD] AM feed set to %s\n", fmtTime12(feedHour1, feedMin1).c_str());
            }
        }
        return;
    }
    if (cmd == "feedtime2") {
        int sp2 = arg.indexOf(' ');
        if (sp2 > 0) {
            int h = arg.substring(0, sp2).toInt();
            int m = arg.substring(sp2 + 1).toInt();
            if (h >= 0 && h < 24 && m >= 0 && m < 60) {
                feedHour2 = h; feedMin2 = m;
                saveFeederSchedule();
                Serial.printf("[CMD] PM feed set to %s\n", fmtTime12(feedHour2, feedMin2).c_str());
            }
        }
        return;
    }
    if (cmd == "feedtime") {
        Serial.printf("  AM: %s\n", fmtTime12(feedHour1, feedMin1).c_str());
        Serial.printf("  PM: %s\n", fmtTime12(feedHour2, feedMin2).c_str());
        return;
    }
    if (cmd == "schedulesync") {
        lastSchedPoll = 0;
        Serial.println("[CMD] Schedule sync triggered");
        return;
    }

    // --- WiFi ---
    if (cmd == "wifissid") {
        arg.trim();
        if (arg.length() > 0 && arg.length() <= 32) {
            saveWifiSSIDToNVS(arg.c_str());
            Serial.printf("[CMD] SSID saved: %s\n", arg.c_str());
            Serial.println("[CMD] Type 'restart' to reconnect");
        }
        return;
    }
    if (cmd == "wifipass") {
        arg.trim();
        if (arg.length() > 0 && arg.length() <= 64) {
            saveWifiPasswordToNVS(arg.c_str());
            Serial.println("[CMD] Password saved");
            Serial.println("[CMD] Type 'restart' to reconnect");
        }
        return;
    }
    if (cmd == "wifireset") { resetWifiToDefault(); Serial.println("[CMD] Type 'restart'"); return; }
    if (cmd == "wifistatus") {
        Serial.printf("  SSID: %s\n", getStoredWifiSSID().c_str());
        Serial.printf("  Password: %s (%u chars)\n",
            getStoredWifiPassword().length() > 0 ? "***" : "(empty)",
            getStoredWifiPassword().length());
        Serial.printf("  Connected: %s\n", WiFi.status() == WL_CONNECTED ? "YES" : "NO");
        if (WiFi.status() == WL_CONNECTED) Serial.printf("  IP: %s\n", WiFi.localIP().toString().c_str());
        return;
    }

    // --- Turbidity calibration ---
    if (cmd == "turbclear" || cmd == "turblclear") {
        float v = arg.toFloat();
        if (v > 0) { updateTurbidityCalibration(v, turbidityVDirty, turbidityVAir); Serial.printf("[CMD] turbidityVClear = %.3f V\n", v); }
        return;
    }
    if (cmd == "turbdirty") {
        float v = arg.toFloat();
        if (v > 0) { updateTurbidityCalibration(turbidityVClear, v, turbidityVAir); Serial.printf("[CMD] turbidityVDirty = %.3f V\n", v); }
        return;
    }
    if (cmd == "turbair") {
        float v = arg.toFloat();
        if (v > 0) { updateTurbidityCalibration(turbidityVClear, turbidityVDirty, v); Serial.printf("[CMD] turbidityVAir = %.3f V\n", v); }
        return;
    }

    // --- pH calibration ---
    if (cmd == "phcal7") { calibratePH7(); return; }
    if (cmd == "phcal4") { calibratePH4(); return; }

    // --- DO calibration ---
    if (cmd == "doclear") { calibrateDOInAir(); return; }

    // --- Debug ---
    if (cmd == "debugmode") {
        if (arg.length() > 0) debugMode = (arg.toInt() != 0);
        else debugMode = !debugMode;
        Serial.printf("[CMD] Debug mode: %s\n", debugMode ? "ON" : "OFF");
        return;
    }
    if (cmd == "debugstatus") {
        Serial.printf("  Debug: %s\n", debugMode ? "ON" : "OFF");
        Serial.printf("  LCD: %s\n", lcdAddress != 0 ? "Connected" : "Not detected");
        Serial.printf("  WiFi: %s\n", WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected");
        if (WiFi.status() == WL_CONNECTED) Serial.printf("  IP: %s\n", WiFi.localIP().toString().c_str());
        Serial.printf("  Firebase: %s\n", Firebase.ready() ? "Ready" : "Not ready");
        for (int i = 0; i < 3; i++) Serial.printf("  %s: %s\n", relays[i].label, relays[i].active ? "ON" : "OFF");
        Serial.printf("  Temp: %.1fC pH: %.2f DO: %.1fmg/L Turb: %.1fNTU Water: %.0fcm\n",
            currentTemp, currentPH, currentDO, currentTurbNTU, currentWaterCm);
        return;
    }

    // --- System ---
    if (cmd == "restart") { Serial.println("[CMD] Rebooting..."); delay(500); ESP.restart(); }
    if (cmd == "i2cscan") { scanI2C(); return; }

    Serial.println("[CMD] Unknown — type 'help'");
}

// =============================================================================
// SETUP
// =============================================================================

void setup() {
    Serial.begin(115200);
    Serial.println("=== CrayCare All-in-One Firmware ===");

    // ADC config for stable analog readings
    analogSetAttenuation(ADC_11db);
    analogSetWidth(12);
    analogSetPinAttenuation(TURBIDITY_PIN, ADC_11db);

    // Relay pins
    pinMode(PIN_A1, OUTPUT); digitalWrite(PIN_A1, HIGH);
    pinMode(PIN_A2, OUTPUT); digitalWrite(PIN_A2, HIGH);
    pinMode(PIN_P,  OUTPUT); digitalWrite(PIN_P,  HIGH);

    // Servo
    initServo();

    // Sensors
    pinMode(TRIG_PIN, OUTPUT);
    pinMode(ECHO_PIN, INPUT);
    digitalWrite(TRIG_PIN, LOW);
    loadTurbidityFromNVS();
    initTemperatureSensor();
    initPHSensor();
    initDOSensor();
    analogSetPinAttenuation(PH_PIN, ADC_11db);
    analogSetPinAttenuation(DO_PIN, ADC_11db);

    // LCD detection
    if (detectLCD()) {
        lcd.init();
        lcd.backlight();
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print("CrayCare AIO");
        lcd.setCursor(0, 1);
        lcd.print("Starting...");
    }

    // WiFi
    loadWifiFromNVS();
    connectWiFi();

    Serial.println("[MAIN] Setup complete");
    if (lcdAddress != 0) {
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print("Wait WiFi...");
    }
}

// =============================================================================
// LOOP
// =============================================================================

void loop() {
    processSerialCommands();
    unsigned long now = millis();

    // --- WiFi + Firebase init (retry) ---
    if (!initialConnectDone) {
        if (WiFi.status() == WL_CONNECTED) {
            Serial.println("[MAIN] WiFi OK — init Firebase...");
            if (lcdAddress != 0) {
                lcd.clear();
                lcd.setCursor(0, 0);
                lcd.print("WiFi OK!");
                lcd.setCursor(0, 1);
                lcd.print("Connecting FB...");
            }
            initTime();
            connectFirebase();
            initialConnectDone = true;
            Serial.println("[MAIN] Ready");
            if (lcdAddress != 0) {
                lcd.clear();
                lcd.setCursor(0, 0);
                lcd.print("System Ready!");
                delay(1000);
            }
        } else if (now - lastWifiRetry >= 10000) {
            lastWifiRetry = now;
            Serial.println("[WIFI] Retrying...");
            if (lcdAddress != 0) {
                lcd.clear();
                lcd.setCursor(0, 0);
                lcd.print("Retrying WiFi...");
            }
            connectWiFi();
        }
        return;
    }

    // --- Sensor reads ---
    if (now - lastSensorRead >= SENSOR_INTERVAL) {
        lastSensorRead = now;
        currentTemp = readTemperatureC();
        currentTurbV = readTurbidityVoltage();
        currentTurbAir = (currentTurbV < turbidityVAir);
        currentTurbNTU = ntuFromVoltage(currentTurbV);
        currentPH = readPH();
        currentDO = readDO(currentTemp);
        currentWaterCm = readWaterLevelCm();

        if (debugMode) {
            Serial.printf("[DEBUG] T=%.1fC pH=%.2f DO=%.1f Turb V=%.3fV NTU=%.0f%s Water=%.0fcm\n",
                currentTemp, currentPH, currentDO, currentTurbV, currentTurbNTU,
                currentTurbAir ? " AIR" : "", currentWaterCm >= 0 ? currentWaterCm : 0);
        } else {
            Serial.printf("[SENSORS] T=%.1fC pH=%.2f DO=%.1f Turb=%.0fNTU%s Water=%.0fcm\n",
                currentTemp, currentPH, currentDO, currentTurbNTU,
                currentTurbAir ? " AIR" : "", currentWaterCm >= 0 ? currentWaterCm : 0);
        }
    }

    // --- Firebase operations ---
    if (Firebase.ready()) {
        pollModes();
        pollCommands();
        pollFirebaseSchedules();
        checkFeederSchedule();
        writeStatus();

        if (now - lastPublish >= PUBLISH_INTERVAL) {
            lastPublish = now;
            publishSensors();
        }

        if (now - lastHistoryPublish >= HISTORY_INTERVAL) {
            lastHistoryPublish = now;
            publishHistory();
        }
    }

    // --- LCD ---
    if (now - lastLcdUpdate >= LCD_INTERVAL) {
        lastLcdUpdate = now;
        updateLCD();
    }
}
