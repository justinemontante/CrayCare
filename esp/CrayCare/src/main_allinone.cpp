#include "common.h"
#include "servo_ctrl.h"
#include "turbidity.h"
#include "ph_ctrl.h"
#include "do_ctrl.h"
#include <LiquidCrystal_I2C.h>
#include <Wire.h>
#include "esp_task_wdt.h"

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
#define SENSOR_HEIGHT_DEFAULT  67.0f   // HC-SR04 mounted height above tank bottom (cm)
#define MAX_WATER_DEPTH_DEFAULT 23.0f  // Tank maximum water depth (cm)

// --- LCD ---
#define LCD_ADDR    0x27
#define LCD_COLS    16
#define LCD_ROWS    2

// =============================================================================
// RELAY / SERVO GLOBALS
// =============================================================================

#define DEV_A1 "pump"      // App "Pump" → GPIO 26 → Water Pump
#define DEV_A2 "aerator1"  // App "Aerator 1" → GPIO 27 → Primary Aerator
#define DEV_P  "aerator2"  // App "Aerator 2" → GPIO 14 → Secondary Aerator

enum RMode { RM_OFF, RM_ON, RM_AUTO };

struct RelayCtx {
    int pin;
    RMode mode;
    bool active;
    const char* devId;
    const char* label;
};

static RelayCtx relays[3] = {
    {PIN_A1, RM_OFF, false, DEV_A1, "Water Pump"},
    {PIN_A2, RM_OFF, false, DEV_A2, "Primary Aer"},
    {PIN_P,  RM_OFF, false, DEV_P,  "Sec Aerator"},
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
static unsigned long lastRawOutput = 0;
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
static bool plotterMode = false;
static bool rawMode = false;

// --- Sensor enable/disable (NVS-persisted) ---
static const char* sensorNames[5] = {"temp", "ph", "do", "turb", "water"};
static bool sensorEnabled[5] = {true, true, true, true, true};

static void loadSensorEnabled() {
    prefs.begin("sensors", false);
    for (int i = 0; i < 5; i++) {
        sensorEnabled[i] = prefs.getBool(sensorNames[i], true);
    }
    prefs.end();
    Serial.printf("[SENSORS] Enabled flags: temp=%d ph=%d do=%d turb=%d water=%d\n",
        sensorEnabled[0], sensorEnabled[1], sensorEnabled[2], sensorEnabled[3], sensorEnabled[4]);
}

static void saveSensorEnabled() {
    prefs.begin("sensors", false);
    for (int i = 0; i < 5; i++) {
        prefs.putBool(sensorNames[i], sensorEnabled[i]);
    }
    prefs.end();
    Serial.println("[SENSORS] Enabled flags saved to NVS");
}

// --- HC-SR04 moving average filter (smooth ripples) ---
#define HC_BUF_SIZE 10
static float hcBuffer[HC_BUF_SIZE];
static int hcBufIdx = 0;
static int hcBufCount = 0;

// --- Tank calibration (configurable via serial, NVS-persisted) ---
static float sensorHeight = SENSOR_HEIGHT_DEFAULT;
static float maxWaterDepth = MAX_WATER_DEPTH_DEFAULT;

// --- Auto-control hysteresis (moved to globals for NVS persistence) ---
static float DO_HYSTERESIS = 0.5f;
static float WATER_HYSTERESIS = 2.0f;
static float PH_HYSTERESIS = 0.2f;
static float TEMP_HYSTERESIS = 1.0f;
static float TURB_HYSTERESIS = 5.0f;  // NTU — ON immediately when > max, OFF when <= max - hysteresis
static unsigned long PUMP_COOLDOWN_MS = 60000;
static unsigned long lastPumpOffTime = 0;

// --- Auto-control thresholds (cached from Firebase /sensor_readings/config/ranges/) ---
static float threshTempMin = 26.0f, threshTempMax = 30.0f;
static float threshPHMin = 7.5f, threshPHMax = 8.0f;
static float threshDOMin = 5.0f, threshDOMax = 999.0f;
static float threshTurbMin = 0.0f, threshTurbMax = 25.0f;
static float threshWaterMin = 120.0f, threshWaterMax = 160.0f;
static unsigned long lastConfigPoll = 0;
#define CONFIG_POLL_INTERVAL 30000

// --- Offline ring buffer (RAM, lost on reboot) ---
#define BUFFER_MAX 720
struct SensorReading {
    unsigned long timestamp;
    float temperature, phLevel, dissolvedOxygen, turbidity, waterLevel;
};
static SensorReading readingBuffer[BUFFER_MAX];
static int bufferWritePos = 0;
static int bufferCount = 0;

static bool initialConnectDone = false;
static unsigned long lastWifiRetry = 0;
static unsigned long lastFirebaseOK = 0;
static unsigned long lastLoopTime = 0;

// --- Feeder schedule ---
static String fbSchedKey1 = "";  // Firebase key of slot 1
static String fbSchedKey2 = "";  // Firebase key of slot 2
static String pendingSchedKey = "";  // Key pending isDone sync when offline
static double feedGrams1 = 0, feedGrams2 = 0;
static int feedHour1 = 9, feedMin1 = 0;
static int feedHour2 = 18, feedMin2 = 0;
static bool fedSlot1 = false, fedSlot2 = false;
static bool missedLogged1 = false, missedLogged2 = false;
static int lastFeedCheckMin = -1;
static bool schedSyncPending = false;

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
static void doFeed(const String& schedKey, double grams = 0);
static void scanI2C();
static bool detectLCD();
static float readWaterLevelCm();
static float readWaterLevelFiltered();
static void addToBuffer(float temp, float ph, float do_, float turb, float water);
static void flushBufferTick();
static String fmtDatePath();
static void publishSensors();
static void publishHistory();
static void updateLCD();
static void printHelp();
static void processSerialCommands();
static void loadFeederSchedule();
static void saveFeederSchedule();
static void checkFeederSchedule();
static void pollFirebaseSchedules();
static void markScheduleDispatched(const String& schedKey);
static void loadWaterLevelCalibration();
static void saveWaterLevelCalibration();
static void autoControlLoop();
static void pollConfig();
static void saveAutoConfig();
static void loadAutoConfig();
static bool canFeed();

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
    if (duration == 0) {
        if (debugMode) Serial.println("[HC-SR04] TIMEOUT - no echo (sensor unplugged or target out of range)");
        return -1;
    }
    float distToWater = duration * SOUND_SPEED_CM_US / 2.0;
    if (distToWater < 2 || distToWater > MAX_DIST_CM) {
        if (debugMode) Serial.printf("[HC-SR04] OUT OF RANGE: duration=%ldus dist=%.1fcm\n", duration, distToWater);
        return -1;
    }
    float waterDepth = sensorHeight - distToWater;
    float rawDepth = waterDepth;
    if (waterDepth < 0) waterDepth = 0;
    if (waterDepth > maxWaterDepth) waterDepth = maxWaterDepth;
    if (debugMode) {
        Serial.printf("[HC-SR04] duration=%ldus dist=%.1fcm rawDepth=%.1fcm depth=%.1fcm (sensorH=%.1f maxD=%.1f)\n",
            duration, distToWater, rawDepth, waterDepth, sensorHeight, maxWaterDepth);
    }
    return waterDepth;
}

static float readWaterLevelFiltered() {
    float result = readWaterLevelCm();
    if (result >= 0) {
        hcBuffer[hcBufIdx++] = result;
        if (hcBufIdx >= HC_BUF_SIZE) hcBufIdx = 0;
        if (hcBufCount < HC_BUF_SIZE) hcBufCount++;
        float sum = 0;
        for (int i = 0; i < hcBufCount; i++) sum += hcBuffer[i];
        return sum / hcBufCount;
    }
    return currentWaterCm;
}

static void addToBuffer(float temp, float ph, float do_, float turb, float water) {
    struct SensorReading* r = &readingBuffer[bufferWritePos];
    r->timestamp = getEpochMillis() / 1000;
    r->temperature = temp;
    r->phLevel = ph;
    r->dissolvedOxygen = do_;
    r->turbidity = turb;
    r->waterLevel = water;
    bufferWritePos = (bufferWritePos + 1) % BUFFER_MAX;
    if (bufferCount < BUFFER_MAX) bufferCount++;
}

static void flushBufferTick() {
    if (bufferCount == 0 || !Firebase.ready()) return;

    int start = (bufferWritePos - bufferCount + BUFFER_MAX) % BUFFER_MAX;
    struct SensorReading* r = &readingBuffer[start];

    FirebaseJson j;
    j.add("temperature", r->temperature);
    j.add("phLevel", r->phLevel);
    j.add("dissolvedOxygen", r->dissolvedOxygen);
    j.add("turbidity", r->turbidity);
    j.add("waterLevel", r->waterLevel >= 0 ? r->waterLevel : 0);
    j.add("timestamp", (double)r->timestamp);

    String path = String("/sensor_readings/history/") + fmtDatePath();
    if (Firebase.RTDB.pushJSON(&fbS, path, &j)) {
        bufferCount--;
        Serial.printf("[FB] Flushed buffered reading (%d remaining)\n", bufferCount);
    }
}

static void loadWaterLevelCalibration() {
    prefs.begin("watercal", false);
    sensorHeight  = prefs.getFloat("sh", SENSOR_HEIGHT_DEFAULT);
    maxWaterDepth = prefs.getFloat("mwd", MAX_WATER_DEPTH_DEFAULT);
    prefs.end();
    Serial.printf("[NVS] Water cal loaded: sensorHeight=%.1fcm, maxDepth=%.1fcm\n",
        sensorHeight, maxWaterDepth);
}

static void saveWaterLevelCalibration() {
    prefs.begin("watercal", false);
    prefs.putFloat("sh", sensorHeight);
    prefs.putFloat("mwd", maxWaterDepth);
    prefs.end();
    Serial.printf("[NVS] Water cal saved: sensorHeight=%.1fcm, maxDepth=%.1fcm\n",
        sensorHeight, maxWaterDepth);
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
    RMode newMode;
    if (m == "on") newMode = RM_ON;
    else if (m == "off") newMode = RM_OFF;
    else newMode = RM_AUTO;
    if (r->mode == newMode) return;
    RMode oldMode = r->mode;
    r->mode = newMode;
    if (newMode == RM_ON) {
        r->active = true;
        digitalWrite(r->pin, LOW);
        Serial.printf("[RELAY] %s = ON (manual)\n", r->label);
        logDeviceAction(r->devId, "Switched ON (manual)", "on");
    } else if (newMode == RM_OFF) {
        r->active = false;
        digitalWrite(r->pin, HIGH);
        Serial.printf("[RELAY] %s = OFF (manual)\n", r->label);
        logDeviceAction(r->devId, "Switched OFF (manual)", "off");
    } else {
        if (oldMode == RM_ON) {
            r->active = false;
            digitalWrite(r->pin, HIGH);
        }
        Serial.printf("[RELAY] %s = AUTO\n", r->label);
        logDeviceAction(r->devId, "Switched to AUTO mode", "auto");
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

// =============================================================================
// AUTO-CONTROL LOGIC
// =============================================================================

static void autoControlLoop() {
    for (int i = 0; i < 3; i++) {
        if (relays[i].mode != RM_AUTO) continue;
        bool wantOn = relays[i].active;
        String reason = "";

        if (i == 1 || i == 2) {
            // Aerators: controlled by DO with hysteresis
            if (currentDO < threshDOMin) {
                wantOn = true;
                reason = "DO dropped to " + String(currentDO, 1) + " mg/L (below " + String(threshDOMin, 1) + " mg/L)";
            } else if (currentDO >= threshDOMin + DO_HYSTERESIS) {
                wantOn = false;
                reason = "DO normalized to " + String(currentDO, 1) + " mg/L (above " + String(threshDOMin, 1) + " mg/L)";
            }
        } else if (i == 0) {
            // Pump: ON if pH out of range OR temp out of range OR turbidity high
            // OFF only when ALL three are normal (with hysteresis)
            unsigned long nowMs = millis();
            bool pHLow = currentPH < threshPHMin;
            bool pHHigh = currentPH > threshPHMax;
            bool pHNormal = currentPH >= threshPHMin + PH_HYSTERESIS && currentPH <= threshPHMax - PH_HYSTERESIS;
            bool tempLow = currentTemp < threshTempMin;
            bool tempHigh = currentTemp > threshTempMax;
            bool tempNormal = currentTemp >= threshTempMin + TEMP_HYSTERESIS && currentTemp <= threshTempMax - TEMP_HYSTERESIS;
            bool turbHigh = currentTurbAir || currentTurbNTU > threshTurbMax;
            bool turbNormal = !currentTurbAir && currentTurbNTU <= threshTurbMax - TURB_HYSTERESIS;

            // Pump cooldown: prevent rapid cycling after turning off
            if (!wantOn && nowMs - lastPumpOffTime < PUMP_COOLDOWN_MS) continue;

            if (pHLow || pHHigh || tempLow || tempHigh || turbHigh) {
                wantOn = true;
                if (pHLow) reason = "pH low (" + String(currentPH, 2) + ")";
                else if (pHHigh) reason = "pH high (" + String(currentPH, 2) + ")";
                else if (tempLow) reason = "temp low (" + String(currentTemp, 1) + " C)";
                else if (tempHigh) reason = "temp high (" + String(currentTemp, 1) + " C)";
                else if (turbHigh) reason = "turbidity high (" + String(currentTurbNTU, 0) + " NTU)";
            } else if (pHNormal && tempNormal && turbNormal) {
                wantOn = false;
                reason = "all parameters normalized";
                if (!relays[i].active) lastPumpOffTime = nowMs;
            }
        }

        if (wantOn != relays[i].active) {
            relays[i].active = wantOn;
            digitalWrite(relays[i].pin, wantOn ? LOW : HIGH);
            const char* label = relays[i].label;
            if (wantOn) {
                Serial.printf("[AUTO] %s ON (%s)\n", label, reason.c_str());
                logDeviceAction(relays[i].devId,
                    (String("Switched ON (AUTO) - ") + reason).c_str(), "auto");
            } else {
                Serial.printf("[AUTO] %s OFF (%s)\n", label, reason.c_str());
                logDeviceAction(relays[i].devId,
                    (String("Switched OFF (AUTO) - ") + reason).c_str(), "auto");
            }
        }
    }
}

// =============================================================================
// CONFIG POLL — read thresholds from Firebase
// =============================================================================

static void saveAutoConfig() {
    prefs.begin("autocfg", false);
    prefs.putFloat("tMin", threshTempMin); prefs.putFloat("tMax", threshTempMax);
    prefs.putFloat("pMin", threshPHMin);   prefs.putFloat("pMax", threshPHMax);
    prefs.putFloat("dMin", threshDOMin);   prefs.putFloat("dMax", threshDOMax);
    prefs.putFloat("trMin", threshTurbMin); prefs.putFloat("trMax", threshTurbMax);
    prefs.putFloat("wMin", threshWaterMin); prefs.putFloat("wMax", threshWaterMax);
    prefs.end();
    Serial.println("[CONFIG] Thresholds saved to NVS");
}

static void loadAutoConfig() {
    prefs.begin("autocfg", false);
    threshTempMin = prefs.getFloat("tMin", threshTempMin);
    threshTempMax = prefs.getFloat("tMax", threshTempMax);
    threshPHMin   = prefs.getFloat("pMin", threshPHMin);
    threshPHMax   = prefs.getFloat("pMax", threshPHMax);
    threshDOMin   = prefs.getFloat("dMin", threshDOMin);
    threshDOMax   = prefs.getFloat("dMax", threshDOMax);
    threshTurbMin = prefs.getFloat("trMin", threshTurbMin);
    threshTurbMax = prefs.getFloat("trMax", threshTurbMax);
    threshWaterMin = prefs.getFloat("wMin", threshWaterMin);
    threshWaterMax = prefs.getFloat("wMax", threshWaterMax);
    prefs.end();
    Serial.printf("[CONFIG] Loaded from NVS: temp %.1f-%.1f ph %.1f-%.1f do %.1f-%.1f turb %.1f-%.1f water %.1f-%.1f\n",
        threshTempMin, threshTempMax, threshPHMin, threshPHMax,
        threshDOMin, threshDOMax, threshTurbMin, threshTurbMax,
        threshWaterMin, threshWaterMax);
}

static void pollConfig() {
    if (!Firebase.ready()) return;
    unsigned long now = millis();
    if (now - lastConfigPoll < CONFIG_POLL_INTERVAL) return;
    lastConfigPoll = now;

    FirebaseJson j;
    if (!Firebase.RTDB.getJSON(&fbW, "/sensor_readings/config/ranges", &j)) {
        return;
    }

    FirebaseJsonData d;
    #define READ_SUB_SENSOR(key, varMin, varMax) do { \
        if (j.get(d, key)) { \
            FirebaseJson sub; sub.setJsonData(d.stringValue); \
            if (sub.get(d, "min")) { float v = d.floatValue; if (v >= 0) varMin = v; } \
            if (sub.get(d, "max")) { float v = d.floatValue; if (v >= 0) varMax = v; } \
        } \
    } while(0)

    READ_SUB_SENSOR("temp",       threshTempMin, threshTempMax);
    READ_SUB_SENSOR("ph",         threshPHMin, threshPHMax);
    READ_SUB_SENSOR("do",         threshDOMin, threshDOMax);
    READ_SUB_SENSOR("turb",       threshTurbMin, threshTurbMax);
    READ_SUB_SENSOR("waterlevel", threshWaterMin, threshWaterMax);

    saveAutoConfig();
    Serial.printf("[CONFIG] Polled: temp %.1f-%.1f ph %.1f-%.1f do %.1f-%.1f turb %.1f-%.1f water %.1f-%.1f\n",
        threshTempMin, threshTempMax, threshPHMin, threshPHMax,
        threshDOMin, threshDOMax, threshTurbMin, threshTurbMax,
        threshWaterMin, threshWaterMax);
}

// =============================================================================
// FEED SAFETY CHECK
// =============================================================================

static bool canFeed() {
    if (currentTurbAir) {
        Serial.println("[FEED-SAFE] BLOCKED: turbidity sensor in air, no water");
        return false;
    }
    if (currentTurbNTU > threshTurbMax) {
        Serial.printf("[FEED-SAFE] BLOCKED: turbidity too high (%.0f > %.0f NTU)\n",
            currentTurbNTU, threshTurbMax);
        return false;
    }
    return true;
}

static void doFeed(const String& schedKey, double grams) {
    if (feedBusy) return;
    if (!canFeed()) {
        logFeedAction("Feed blocked by safety check", "error");
        return;
    }
    feedBusy = true;
    if (Firebase.ready()) {
        Firebase.RTDB.setBool(&fbW, "/feeder/status/isRunning", true);
    }
    if (grams > 0) {
        executeServoCycleFromTable(grams);
    } else {
        executeServoCycle();
    }
    feedCount++;
    markScheduleDispatched(schedKey);
    if (Firebase.ready()) {
        FirebaseJson j;
        j.add("isRunning", false); j.add("feedCount", feedCount);
        j.add("lastSeen", (double)getEpochMillis());
        j.add("hopperLevel", 100.0); j.add("feedSource", "esp32");
        j.add("feederError", "");
        Firebase.RTDB.setJSON(&fbW, "/feeder/status", &j);
        if (grams > 0) {
            char buf[48];
            snprintf(buf, sizeof(buf), "Feed dispensed (%.1fg)", grams);
            logFeedAction(buf, "auto");
        } else {
            logFeedAction("Feed dispensed", "auto");
        }
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
                double gramsCmd = 0;
                if (sub.get(d, "grams")) gramsCmd = d.doubleValue;
                String path = String("/feeder/commands/") + key;
                if (nowMs > 0 && nowMs - ts < 30000) {
                    Serial.printf("[CMD-POLL] Feed: %s (%.1fg)\n", key.c_str(), gramsCmd);
                    Firebase.RTDB.deleteNode(&fbW, path);
                    doFeed("", gramsCmd);
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
    unsigned long now = millis();
    if (now - lastStatusWrite < STATUS_INTERVAL) return;
    lastStatusWrite = now;
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
    unsigned long now = getEpochMillis() / 1000;

    if (Firebase.ready()) {
        FirebaseJson j;
        j.add("temperature", currentTemp);
        j.add("phLevel", currentPH);
        j.add("dissolvedOxygen", currentDO);
        j.add("turbidity", currentTurbNTU);
        j.add("turbidityAir", currentTurbAir ? true : false);
        j.add("waterLevel", currentWaterCm >= 0 ? currentWaterCm : -1);
        j.add("phDisabled", !sensorEnabled[1]);
        j.add("doDisabled", !sensorEnabled[2]);
        j.add("tempDisabled", !sensorEnabled[0]);
        j.add("turbDisabled", !sensorEnabled[3]);
        j.add("waterDisabled", !sensorEnabled[4]);
        j.add("timestamp", (double)now);
        if (Firebase.RTDB.setJSON(&fbS, "/sensor_readings/latest", &j)) {
            Serial.println("[FB] Sensor data published");
        } else {
            Serial.printf("[FB] Sensor publish failed: %s\n", fbS.errorReason());
        }
    } else {
        Serial.println("[FB] Offline, queuing sensor reading");
        addToBuffer(currentTemp, currentPH, currentDO, currentTurbNTU, currentWaterCm);
    }

    if (plotterMode) {
        Serial.printf("%lu,%.2f,%.1f,%.2f,%.1f,%.1f\n",
            now, currentPH, currentTemp, currentDO, currentTurbNTU,
            currentWaterCm >= 0 ? currentWaterCm : 0);
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
    fbSchedKey1 = prefs.getString("key1", "");
    fbSchedKey2 = prefs.getString("key2", "");
    feedGrams1 = prefs.getFloat("g1", 0);
    feedGrams2 = prefs.getFloat("g2", 0);
    prefs.end();
    lastSchedSync = 0;
    schedSyncPending = false;
    Serial.printf("[FEEDER] Schedule loaded: %02d:%02d(%.1fg) %02d:%02d(%.1fg) (key1=%s key2=%s)\n",
        feedHour1, feedMin1, feedGrams1, feedHour2, feedMin2, feedGrams2,
        fbSchedKey1.c_str(), fbSchedKey2.c_str());
}

static void saveFeederSchedule() {
    prefs.begin("feedtime", false);
    prefs.putInt("hr1", feedHour1);
    prefs.putInt("min1", feedMin1);
    prefs.putInt("hr2", feedHour2);
    prefs.putInt("min2", feedMin2);
    prefs.putString("key1", fbSchedKey1);
    prefs.putString("key2", fbSchedKey2);
    prefs.putFloat("g1", (float)feedGrams1);
    prefs.putFloat("g2", (float)feedGrams2);
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
        fedSlot1 = false;
        fedSlot2 = false;
        missedLogged1 = false;
        missedLogged2 = false;
    }
    if (!feedBusy) {
        if (!fedSlot1 && curH == feedHour1 && curM == feedMin1) {
            Serial.printf("[FEEDER] Auto-feed slot1 (%s key=%s)\n",
                fmtTime12(feedHour1, feedMin1).c_str(), fbSchedKey1.c_str());
            doFeed(fbSchedKey1, feedGrams1);
            fedSlot1 = true;
        }
        if (!fedSlot2 && curH == feedHour2 && curM == feedMin2) {
            Serial.printf("[FEEDER] Auto-feed slot2 (%s key=%s)\n",
                fmtTime12(feedHour2, feedMin2).c_str(), fbSchedKey2.c_str());
            doFeed(fbSchedKey2, feedGrams2);
            fedSlot2 = true;
        }

        // Missed feed detection — 10 min past schedule, still not fed
        int curMins = curH * 60 + curM;
        int sched1 = feedHour1 * 60 + feedMin1;
        int sched2 = feedHour2 * 60 + feedMin2;
        if (!fedSlot1 && !missedLogged1 && sched1 > 0 &&
            curMins >= sched1 + 10 && curMins < sched1 + 15) {
            logFeedAction("Feed skipped", "missed");
            Serial.printf("[FEEDER] Slot1 missed — no feed at %s\n",
                fmtTime12(feedHour1, feedMin1).c_str());
            missedLogged1 = true;
        }
        if (!fedSlot2 && !missedLogged2 && sched2 > 0 &&
            curMins >= sched2 + 10 && curMins < sched2 + 15) {
            logFeedAction("Feed skipped", "missed");
            Serial.printf("[FEEDER] Slot2 missed — no feed at %s\n",
                fmtTime12(feedHour2, feedMin2).c_str());
            missedLogged2 = true;
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

    struct FbSched { int hour24; int min; String key; double grams; };
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
        scheds[count].key = key;
        scheds[count].grams = 0;
        if (sub.get(d, "grams")) scheds[count].grams = d.doubleValue;
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
    String k1 = "", k2 = "";
    double g1 = 0, g2 = 0;
    if (count >= 1) { h1 = scheds[0].hour24; m1 = scheds[0].min; k1 = scheds[0].key; g1 = scheds[0].grams; }
    if (count >= 2) { h2 = scheds[1].hour24; m2 = scheds[1].min; k2 = scheds[1].key; g2 = scheds[1].grams; }

    bool changed = (h1 != feedHour1 || m1 != feedMin1 || h2 != feedHour2 || m2 != feedMin2 ||
                    k1 != fbSchedKey1 || k2 != fbSchedKey2 ||
                    g1 != feedGrams1 || g2 != feedGrams2);
    if (changed) {
        feedHour1 = h1; feedMin1 = m1; feedHour2 = h2; feedMin2 = m2;
        fbSchedKey1 = k1; fbSchedKey2 = k2;
        feedGrams1 = g1; feedGrams2 = g2;
        missedLogged1 = false; missedLogged2 = false;
        saveFeederSchedule();
        Serial.printf("[SCHED] Synced: %02d:%02d(%.1fg key=%s) %02d:%02d(%.1fg key=%s) %d sched(s)\n",
            feedHour1, feedMin1, feedGrams1, fbSchedKey1.c_str(),
            feedHour2, feedMin2, feedGrams2, fbSchedKey2.c_str(), count);
    }
    lastSchedSync = now;
}

static void markScheduleDispatched(const String& schedKey) {
    if (schedKey.isEmpty()) return;

    if (Firebase.ready()) {
        Firebase.RTDB.setBool(&fbW,
            String("/feeder/schedules/") + schedKey + "/isDone", true);

        // Write dispatched path so app/background helper can see it was fed
        String datePath = fmtDatePath();
        Firebase.RTDB.setBool(&fbW,
            String("/feeder/dispatched/") + datePath + "/" + schedKey, true);

        schedSyncPending = false;
        pendingSchedKey = "";
    } else {
        schedSyncPending = true;
        pendingSchedKey = schedKey;
        Serial.println("[FEEDER] isDone sync queued (offline)");
    }
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
        if (currentTurbAir) {
            lcd.print("Turb:  On Air ");
        } else {
            lcd.printf("Turb:%.0fNTU    ", currentTurbNTU);
        }
        lcd.setCursor(0, 1);
        String t1 = fmtTime12(feedHour1, feedMin1);
        String t2 = fmtTime12(feedHour2, feedMin2);
        lcd.printf("FD:%s %s", t1.c_str(), t2.c_str());
    } else {
        bool a1 = relays[0].active, a2 = relays[1].active, p = relays[2].active;
        bool schedOk = (millis() - lastSchedSync < 120000);
        lcd.setCursor(0, 0);
        lcd.printf("Pmp:%s PA1:%s", a1 ? "ON" : "OFF", a2 ? "ON" : "OFF");
        lcd.setCursor(0, 1);
        lcd.printf("SA2:%s Sched:%s", p ? "ON" : "OFF", schedOk ? "OK" : "--");
    }
}

// =============================================================================
// SERIAL COMMANDS
// =============================================================================

static void printHelp() {
    Serial.println();
    Serial.println("========== CrayCare All-in-One Commands ==========");
    Serial.println("--- Relays ---");
    Serial.println("  n1on / n1off         Water Pump ON/OFF");
    Serial.println("  n2on / n2off         Primary Aerator ON/OFF");
    Serial.println("  n3on / n3off         Secondary Aerator ON/OFF");
    Serial.println("  relay status         Show relay states");
    Serial.println("");
    Serial.println("--- Servo / Feeder ---");
    Serial.println("  servopause <ms>      Set servo open pause");
    Serial.println("  servoangle <open> <close>  Set open/close angles (0-180)");
    Serial.println("  servocycle           Run one feed cycle");
    Serial.println("  calrec <g> <ang> <ms>  Record: dispense g grams at angle/pause");
    Serial.println("  caldel <g>            Delete record for grams g");
    Serial.println("  callist               List all calibration records");
    Serial.println("  calclear              Clear all calibration records");
    Serial.println("  caltest <g>           Test: run feed cycle for g grams from table");
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
    Serial.println("  686                  Calibrate at pH 6.86 buffer (auto-detect)");
    Serial.println("  401                  Calibrate at pH 4.01 buffer (auto-detect)");
    Serial.println("  phread               Show raw voltage + calculated pH");
    Serial.println("  phshow               Show all pH calibration values");
    Serial.println("  phreset              Reset pH calibration (686/401)");
    Serial.println("");
    Serial.println("--- DO Calibration ---");
    Serial.println("  doclear              Calibrate in air (100% sat)");
    Serial.println("  doread               Read raw DO voltage (no save)");
    Serial.println("");
    Serial.println("--- Water Level Calibration ---");
    Serial.println("  tankheight <cm>      Set sensor height above tank bottom");
    Serial.println("  tankdepth <cm>       Set tank max water depth");
    Serial.println("  tankcal              Show current water level settings");
    Serial.println("");
    Serial.println("--- Plotter / Raw ---");
    Serial.println("  plotter              Toggle CSV stream for Serial Plotter (5s interval)");
    Serial.println("  raw                  Toggle raw sensor voltages (5s interval)");
    Serial.println("");
    Serial.println("--- Auto-Control Thresholds ---");
    Serial.println("  showthresholds        Show current thresholds");
    Serial.println("  setthreshold <sensor> <min> [max]  Set threshold (temp/ph/do/turb/waterlevel)");
    Serial.println("");
    Serial.println("--- Debug ---");
    Serial.println("  sensor <name> on|off  Enable/disable sensor (temp/ph/do/turb/water)");
    Serial.println("  sensor list           Show all sensor states");
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
    if (cmd == "n1on")  { digitalWrite(PIN_A1, LOW);  Serial.println("[CMD] Water Pump ON"); return; }
    if (cmd == "n1off") { digitalWrite(PIN_A1, HIGH); Serial.println("[CMD] Water Pump OFF"); return; }
    if (cmd == "n2on")  { digitalWrite(PIN_A2, LOW);  Serial.println("[CMD] Primary Aerator ON"); return; }
    if (cmd == "n2off") { digitalWrite(PIN_A2, HIGH); Serial.println("[CMD] Primary Aerator OFF"); return; }
    if (cmd == "n3on")  { digitalWrite(PIN_P, LOW);   Serial.println("[CMD] Secondary Aerator ON"); return; }
    if (cmd == "n3off") { digitalWrite(PIN_P, HIGH);  Serial.println("[CMD] Secondary Aerator OFF"); return; }
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
        if (v > 0) {
            servoPauseMs = v;
            saveServoPause(v);
        }
        return;
    }
    if (cmd == "servoangle") {
        int sp2 = arg.indexOf(' ');
        if (sp2 > 0) {
            int openAng = arg.substring(0, sp2).toInt();
            int closeAng = arg.substring(sp2 + 1).toInt();
            if (openAng >= 0 && openAng <= 180 && closeAng >= 0 && closeAng <= 180) {
                saveServoAngles(openAng, closeAng);
                Serial.printf("[CMD] Servo angles: Open=%d°, Close=%d°\n", openAng, closeAng);
            } else {
                Serial.println("[CMD] Invalid angles (must be 0-180)");
            }
        } else {
            Serial.printf("[CMD] Servo: Open=%d°, Close=%d°\n", servoOpenAngle, servoCloseAngle);
        }
        return;
    }
    if (cmd == "servocycle") {
        Serial.println("[CMD] Manual feed cycle");
        executeServoCycle();
        return;
    }
    if (cmd == "gramspause" || cmd == "gramsshift" || cmd == "gramscal") {
        Serial.println("[CMD] Calibration table is primary — use 'calrec'/'callist' instead");
        return;
    }
    if (cmd == "calrec") {
        int sp1 = arg.indexOf(' ');
        int sp2 = arg.lastIndexOf(' ');
        if (sp1 > 0 && sp2 > sp1) {
            double g = arg.substring(0, sp1).toDouble();
            int a = arg.substring(sp1 + 1, sp2).toInt();
            uint32_t p = (uint32_t)arg.substring(sp2 + 1).toInt();
            if (g > 0 && a >= 0 && a <= 180 && p >= 100 && p <= 10000) {
                int insertIdx = calCount;
                for (int i = 0; i < calCount; i++) {
                    if (fabs(calTable[i].grams - g) < 0.01) {
                        calTable[i].angle = a;
                        calTable[i].pauseMs = p;
                        saveCalTable();
                        Serial.printf("[CMD] Cal record updated: %.1fg → angle=%d° pause=%ums\n", g, a, p);
                        return;
                    }
                    if (calTable[i].grams > g) {
                        insertIdx = i;
                        break;
                    }
                }
                if (calCount >= CAL_MAX_RECORDS) {
                    Serial.println("[CMD] Cal table full (16/16) — delete a record first");
                    return;
                }
                for (int i = calCount; i > insertIdx; i--) {
                    calTable[i] = calTable[i - 1];
                }
                calTable[insertIdx].grams = g;
                calTable[insertIdx].angle = a;
                calTable[insertIdx].pauseMs = p;
                calCount++;
                saveCalTable();
                Serial.printf("[CMD] Cal record added: %.1fg → angle=%d° pause=%ums (%d/%d)\n",
                    g, a, p, calCount, CAL_MAX_RECORDS);
            } else {
                Serial.println("[CMD] Invalid: calrec <grams> <angle(0-180)> <pauseMs(100-10000)>");
            }
        } else {
            Serial.println("[CMD] Usage: calrec <grams> <angle> <pauseMs>");
        }
        return;
    }
    if (cmd == "caldel") {
        double g = arg.toDouble();
        if (g > 0 && calCount > 0) {
            int bestIdx = 0;
            double bestDiff = fabs(g - calTable[0].grams);
            for (int i = 1; i < calCount; i++) {
                double diff = fabs(g - calTable[i].grams);
                if (diff < bestDiff) {
                    bestDiff = diff;
                    bestIdx = i;
                }
            }
            Serial.printf("[CMD] Cal record deleted: %.1fg (was %.1fg → angle=%d° pause=%ums)\n",
                g, calTable[bestIdx].grams, calTable[bestIdx].angle, calTable[bestIdx].pauseMs);
            for (int i = bestIdx; i < calCount - 1; i++) {
                calTable[i] = calTable[i + 1];
            }
            calCount--;
            saveCalTable();
        } else {
            Serial.println("[CMD] No records to delete or invalid grams");
        }
        return;
    }
    if (cmd == "callist") {
        if (calCount == 0) {
            Serial.println("[CMD] Calibration table empty. Use 'calrec <g> <angle> <pauseMs>' to add records.");
        } else {
            Serial.printf("[CMD] Calibration table (%d/%d records):\n", calCount, CAL_MAX_RECORDS);
            for (int i = 0; i < calCount; i++) {
                Serial.printf("  #%d: %.1fg → angle=%d° pause=%ums\n",
                    i, calTable[i].grams, calTable[i].angle, calTable[i].pauseMs);
            }
        }
        return;
    }
    if (cmd == "calclear") {
        calCount = 0;
        saveCalTable();
        Serial.println("[CMD] Calibration table cleared");
        return;
    }
    if (cmd == "caltest") {
        double g = arg.toDouble();
        if (g > 0) {
            Serial.printf("[CMD] Test feed: %.1fg (from calibration table)\n", g);
            executeServoCycleFromTable(g);
        } else {
            Serial.println("[CMD] Usage: caltest <grams>");
        }
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
    if (cmd == "doread") {
        float v = readDORaw();
        Serial.printf("[DO] Raw voltage = %.3f V (%.0f mV)\n", v, v * 1000);
        return;
    }

    // --- Water level calibration ---
    if (cmd == "tankheight") {
        float v = arg.toFloat();
        if (v >= 10 && v <= 500) {
            sensorHeight = v;
            saveWaterLevelCalibration();
            Serial.printf("[CMD] sensorHeight=%.1fcm\n", sensorHeight);
        } else {
            Serial.println("[CMD] Invalid height (10-500cm)");
        }
        return;
    }
    if (cmd == "tankdepth") {
        float v = arg.toFloat();
        if (v >= 1 && v <= 500) {
            maxWaterDepth = v;
            saveWaterLevelCalibration();
            Serial.printf("[CMD] maxWaterDepth=%.1fcm\n", maxWaterDepth);
        } else {
            Serial.println("[CMD] Invalid depth (1-500cm)");
        }
        return;
    }
    if (cmd == "tankcal") {
        Serial.printf("  sensorHeight=%.1fcm (sensor to tank bottom)\n", sensorHeight);
        Serial.printf("  maxWaterDepth=%.1fcm (tank capacity)\n", maxWaterDepth);
        return;
    }

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

    // --- Sensor enable/disable ---
    if (cmd == "sensor") {
        int sp2 = arg.indexOf(' ');
        String sname = (sp2 == -1) ? arg : arg.substring(0, sp2);
        String sval  = (sp2 == -1) ? "" : arg.substring(sp2 + 1);
        sname.toLowerCase(); sval.toLowerCase();
        if (sname == "list") {
            Serial.println("--- Sensor states ---");
            for (int i = 0; i < 5; i++) {
                Serial.printf("  %s: %s\n", sensorNames[i], sensorEnabled[i] ? "ON" : "OFF");
            }
            return;
        }
        int sidx = -1;
        for (int i = 0; i < 5; i++) {
            if (sname == sensorNames[i]) { sidx = i; break; }
        }
        if (sidx < 0) {
            Serial.printf("[CMD] Unknown sensor '%s'. Try: temp, ph, do, turb, water\n", sname.c_str());
            return;
        }
        if (sval == "on") {
            sensorEnabled[sidx] = true;
            saveSensorEnabled();
            Serial.printf("[CMD] %s enabled\n", sensorNames[sidx]);
        } else if (sval == "off") {
            sensorEnabled[sidx] = false;
            saveSensorEnabled();
            Serial.printf("[CMD] %s disabled (will send -1 to Firebase)\n", sensorNames[sidx]);
        } else {
            Serial.println("[CMD] Usage: sensor <name> on|off  or  sensor list");
        }
        return;
    }

    // --- Auto-control thresholds ---
    if (cmd == "showthresholds") {
        Serial.println("--- Thresholds (auto-control) ---");
        Serial.printf("  temp:      %.1f - %.1f C\n", threshTempMin, threshTempMax);
        Serial.printf("  ph:        %.1f - %.1f\n", threshPHMin, threshPHMax);
        Serial.printf("  do:        %.1f - %.1f mg/L (aerator ON < %.1f)\n", threshDOMin, threshDOMax, threshDOMin);
        Serial.printf("  turb:      %.1f - %.1f NTU\n", threshTurbMin, threshTurbMax);
        Serial.printf("  waterlevel: %.1f - %.1f cm (pump ON < %.1f)\n", threshWaterMin, threshWaterMax, threshWaterMin);
        Serial.printf("  do_hysteresis:  %.1f\n", DO_HYSTERESIS);
        Serial.printf("  water_hysteresis: %.1f\n", WATER_HYSTERESIS);
        return;
    }
    if (cmd == "setthreshold") {
        int space = arg.indexOf(' ');
        if (space <= 0) { Serial.println("[CMD] Usage: setthreshold <sensor> <min> [max]"); return; }
        String sensor = arg.substring(0, space); sensor.toLowerCase();
        String rest = arg.substring(space + 1); rest.trim();
        float minVal = rest.toFloat();
        float maxVal = -1;
        int space2 = rest.indexOf(' ');
        if (space2 > 0) {
            minVal = rest.substring(0, space2).toFloat();
            maxVal = rest.substring(space2 + 1).toFloat();
        }
        bool ok = true;
        if (sensor == "temp")     { if (minVal > 0) threshTempMin = minVal; if (maxVal > 0) threshTempMax = maxVal; }
        else if (sensor == "ph")   { if (minVal > 0) threshPHMin = minVal; if (maxVal > 0) threshPHMax = maxVal; }
        else if (sensor == "do")   { if (minVal > 0) threshDOMin = minVal; if (maxVal > 0) threshDOMax = maxVal; }
        else if (sensor == "turb") { if (minVal > 0) threshTurbMin = minVal; if (maxVal > 0) threshTurbMax = maxVal; }
        else if (sensor == "waterlevel") { if (minVal > 0) threshWaterMin = minVal; if (maxVal > 0) threshWaterMax = maxVal; }
        else { Serial.printf("[CMD] Unknown sensor: %s\n", sensor.c_str()); ok = false; }
        if (ok) {
            saveAutoConfig();
            Serial.printf("[CMD] %s: min=%.1f max=%.1f\n", sensor.c_str(), minVal, maxVal > 0 ? maxVal : -1);
        }
        return;
    }

    // --- pH 686/401 calibration (standalone-style) ---
    if (cmd == "686") { calibratePH686(); return; }
    if (cmd == "401") { calibratePH401(); return; }
    if (cmd == "phread") { readPHVoltage(); return; }
    if (cmd == "phshow") { showPHCalibration(); return; }
    if (cmd == "phreset") { resetPHCalibration(); return; }

    // --- Plotter / Raw mode ---
    if (cmd == "plotter") {
        plotterMode = !plotterMode;
        Serial.printf("[CMD] Plotter mode: %s\n", plotterMode ? "ON" : "OFF");
        if (plotterMode) Serial.println("  CSV: epoch,pH,Temp,DO,Turb,Water");
        return;
    }
    if (cmd == "raw") {
        rawMode = !rawMode;
        Serial.printf("[CMD] Raw mode: %s\n", rawMode ? "ON" : "OFF");
        if (rawMode) Serial.println("  Output every 5s: pH_V, DO_mV, Turb_V, HC-SR04, Water");
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
    for (int i = 0; i < 10; i++) {
        delay(300);
        Serial.print(".");
    }
    Serial.println();
    Serial.println("========== CRAY CARE ==========");
    Serial.println("Firmware: All-in-One v2.0");
    Serial.println("Baud rate: 115200");
    Serial.println("SYNC_OK_115200");
    Serial.flush();

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
    loadWaterLevelCalibration();
    loadAutoConfig();
    loadSensorEnabled();
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
        Serial.println("[LCD] Detected and initialized");
    } else {
        Serial.println("[LCD] NOT DETECTED — check wiring (VCC=5V, GND, SDA=21, SCL=22, addr 0x27/0x3F)");
    }

    // WiFi
    loadWifiFromNVS();
    connectWiFi();

    esp_task_wdt_init(10, true);
    esp_task_wdt_add(NULL);
    Serial.println("[WDT] Hardware watchdog enabled (10s timeout)");

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
    esp_task_wdt_reset();
    processSerialCommands();
    unsigned long now = millis();

    // --- WiFi + Firebase init (one-time, retry until connected) ---
    if (!initialConnectDone) {
        if (WiFi.status() == WL_CONNECTED) {
            static bool timeChecked = false;
            if (!timeChecked) {
                initTime();
                struct tm t;
                if (!getLocalTime(&t)) {
                    Serial.println("[MAIN] Time not ready — retrying...");
                    if (lcdAddress != 0) {
                        lcd.clear(); lcd.setCursor(0, 0); lcd.print("Time sync fail");
                    }
                    delay(2000);
                    return;
                }
                timeChecked = true;
                if (lcdAddress != 0) {
                    lcd.clear(); lcd.setCursor(0, 0); lcd.print("WiFi OK!");
                    lcd.setCursor(0, 1); lcd.print("Connecting FB...");
                }
                connectFirebase();
            }

            if (Firebase.ready()) {
                initialConnectDone = true;
                lastFirebaseOK = millis();
                lastLoopTime = millis();
                timeChecked = false;
                Serial.println("[MAIN] Ready");
                if (lcdAddress != 0) {
                    lcd.clear(); lcd.setCursor(0, 0); lcd.print("System Ready!");
                    delay(1000);
                }
            }
        } else if (now - lastWifiRetry >= 10000) {
            lastWifiRetry = now;
            Serial.println("[WIFI] Retrying...");
            if (lcdAddress != 0) {
                lcd.clear(); lcd.setCursor(0, 0); lcd.print("Retrying WiFi...");
            }
            connectWiFi();
        }
        return;
    }

    // --- Software watchdog: reboot if Firebase stuck or loop stalled ---
    if (Firebase.ready()) {
        lastFirebaseOK = now;
    }
    if (now - lastFirebaseOK > 1800000) {
        Serial.printf("[WDT] Firebase unreachable for %lums, rebooting...\n", now - lastFirebaseOK);
        delay(100);
        ESP.restart();
    }
    if (now - lastLoopTime > 120000) {
        Serial.printf("[WDT] Loop stalled for %lums, rebooting...\n", now - lastLoopTime);
        delay(100);
        ESP.restart();
    }
    lastLoopTime = now;

    // --- Sensor reads ---
    if (now - lastSensorRead >= SENSOR_INTERVAL) {
        lastSensorRead = now;
        currentTemp = readTemperatureC();
        if (currentTemp <= -127) sensorEnabled[0] = false;
        if (!sensorEnabled[0]) currentTemp = -1;
        currentTurbV = readTurbidityVoltage();
        currentTurbAir = (currentTurbV < turbidityVAir);
        currentTurbNTU = currentTurbAir ? -1.0f : ntuFromVoltage(currentTurbV);
        if (!sensorEnabled[3]) { currentTurbNTU = -1; currentTurbAir = false; }
        currentPH = readPH();
        if (!sensorEnabled[1]) currentPH = -1;
        currentDO = readDO(currentTemp);
        if (readDORaw() < 0.1f) sensorEnabled[2] = false;
        if (!sensorEnabled[2]) currentDO = -1;
        currentWaterCm = readWaterLevelFiltered();
        if (!sensorEnabled[4]) currentWaterCm = -1;
        if (debugMode) {
            float rawDOV = readDORaw();
            Serial.printf("[DEBUG] T=%.1fC pH=%.2f DO=%.1f(% .0fmV) Turb V=%.3fV%s Water=%.0fcm\n",
                currentTemp, currentPH, currentDO, rawDOV * 1000, currentTurbV,
                currentTurbAir ? " AIR" : "", currentWaterCm >= 0 ? currentWaterCm : 0);
        } else {
            Serial.printf("[SENSORS] T=%.1fC pH=%.2f DO=%.1f Turb=%.0fNTU%s Water=%.0fcm\n",
                currentTemp, currentPH, currentDO, currentTurbNTU,
                currentTurbAir ? " AIR" : "", currentWaterCm >= 0 ? currentWaterCm : 0);
        }
    }

    // --- publishSensors() on its own clock, buffers when offline ---
    if (now - lastPublish >= PUBLISH_INTERVAL) {
        lastPublish = now;
        publishSensors();
    }

    // --- Auto-control runs every sensor cycle regardless of Firebase status ---
    autoControlLoop();

    // --- All other Firebase ops grouped ---
    if (Firebase.ready()) {
        // Retry pending isDone sync (if we were offline when feed fired)
        if (schedSyncPending && !pendingSchedKey.isEmpty()) {
            Serial.printf("[FEEDER] Retrying isDone sync for %s...\n", pendingSchedKey.c_str());
            Firebase.RTDB.setBool(&fbW,
                String("/feeder/schedules/") + pendingSchedKey + "/isDone", true);
            schedSyncPending = false;
            pendingSchedKey = "";
        }

        pollModes();
        pollConfig();
        pollCommands();
        pollFirebaseSchedules();
        checkFeederSchedule();
        writeStatus();

        if (now - lastHistoryPublish >= HISTORY_INTERVAL) {
            lastHistoryPublish = now;
            publishHistory();
        }
    }

    // --- Flush one buffered reading per loop (non-blocking) ---
    flushBufferTick();

    // --- LCD ---
    if (now - lastLcdUpdate >= LCD_INTERVAL) {
        lastLcdUpdate = now;
        updateLCD();
    }

    // --- Raw sensor output (every PUBLISH_INTERVAL) ---
    if (rawMode && now - lastRawOutput >= PUBLISH_INTERVAL) {
        lastRawOutput = now;
        float rawPHV = readPHRawVoltage();
        float rawDOV = readDORaw();
        float rawDist = readWaterLevelCm();
        bool phProbeOK = (rawPHV >= 0.5f && rawPHV <= 2.8f);
        Serial.printf("[RAW] pH_V=%s | DO_mV=%.0f | Turb_V=%.3f | HC-SR04=%.1fcm → Water=%.1fcm\n",
            phProbeOK ? String(rawPHV, 3).c_str() : "--",
            rawDOV * 1000, currentTurbV,
            rawDist >= 0 ? rawDist : 0,
            currentWaterCm >= 0 ? currentWaterCm : 0);
    }
}
