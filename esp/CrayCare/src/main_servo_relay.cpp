#include "common.h"
#include "servo_ctrl.h"

#define PIN_A1 26
#define PIN_A2 27
#define PIN_P  14

#define DEV_A1 "aerator1"
#define DEV_A2 "aerator2"
#define DEV_P  "pump"
#define LBL_A1 "Aerator 1"
#define LBL_A2 "Aerator 2"
#define LBL_P  "Water Pump"

enum RMode { RM_OFF, RM_ON, RM_AUTO };

struct RelayCtx {
    int pin;
    RMode mode;
    bool active;
    const char* devId;
    const char* label;
};

static RelayCtx relays[3] = {
    {PIN_A1, RM_OFF, false, DEV_A1, LBL_A1},
    {PIN_A2, RM_OFF, false, DEV_A2, LBL_A2},
    {PIN_P,  RM_OFF, false, DEV_P,  LBL_P},
};

static FirebaseData fbW;

static bool feedBusy = false;
static int  feedCount = 0;
static unsigned long lastStatus = 0;
static unsigned long lastModesPoll = 0;
static unsigned long lastCmdPoll = 0;

static void applyMode(int idx, const String& modeStr);

static void pollModes() {
    if (!Firebase.ready()) return;
    unsigned long now = millis();
    if (now - lastModesPoll < 3000) return;
    lastModesPoll = now;

    FirebaseJson j;
    if (!Firebase.RTDB.getJSON(&fbW, "/devices/modes", &j)) {
        Serial.println("[MODES] poll FAILED");
        return;
    }

    FirebaseJsonData d;
    if (j.get(d, DEV_A1)) { Serial.printf("[MODES-POLL] %s=%s\n", DEV_A1, d.stringValue.c_str()); applyMode(0, d.stringValue); }
    if (j.get(d, DEV_A2)) { Serial.printf("[MODES-POLL] %s=%s\n", DEV_A2, d.stringValue.c_str()); applyMode(1, d.stringValue); }
    if (j.get(d, DEV_P))  { Serial.printf("[MODES-POLL] %s=%s\n", DEV_P, d.stringValue.c_str()); applyMode(2, d.stringValue); }
}

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
    j.add("action", action);
    j.add("type", type);
    j.add("time", fmtTime());
    j.add("date", fmtDate());
    j.add("userName", "ESP32");
    j.add("timestamp", (double)getEpochMillis());
    Firebase.RTDB.push(&fbW, String("/devices/logs/") + devId, &j);
}

static void logFeedAction(const char* action, const char* type) {
    if (!Firebase.ready()) return;
    FirebaseJson j;
    j.add("action", action);
    j.add("type", type);
    j.add("time", fmtTime());
    j.add("date", fmtDate());
    j.add("userName", "ESP32");
    j.add("timestamp", (double)getEpochMillis());
    Firebase.RTDB.push(&fbW, "/feeder/logs", &j);
}

static void applyMode(int idx, const String& modeStr) {
    RelayCtx* r = &relays[idx];
    String m = modeStr;
    m.toLowerCase();
    RMode newMode;
    bool newActive;
    if (m == "on") {
        newMode = RM_ON; newActive = true;
    } else if (m == "off") {
        newMode = RM_OFF; newActive = false;
    } else {
        newMode = RM_AUTO; newActive = false;
    }
    if (r->mode == newMode && r->active == newActive) return;
    bool wasActive = r->active;
    r->mode = newMode;
    r->active = newActive;
    digitalWrite(r->pin, newActive ? LOW : HIGH);
    Serial.printf("[RELAY] %s (GPIO%d) = %s\n", r->label, r->pin, newActive ? "ON" : "OFF");
    if (wasActive != newActive && newMode == RM_AUTO) {
        logDeviceAction(r->devId, newActive ? "Switched ON (AUTO)" : "Switched OFF (AUTO)", "auto");
    }
}



static void doFeed() {
    if (feedBusy) return;
    feedBusy = true;
    if (Firebase.ready()) {
        Firebase.RTDB.setBool(&fbW, "/feeder/status/isRunning", true);
    }
    executeServoCycle();
    feedCount++;
    unsigned long now = getEpochMillis();
    if (Firebase.ready()) {
        FirebaseJson j;
        j.add("isRunning", false);
        j.add("feedCount", feedCount);
        j.add("lastSeen", (double)now);
        j.add("hopperLevel", 100.0);
        j.add("feedSource", "esp32");
        j.add("feederError", "");
        Firebase.RTDB.setJSON(&fbW, "/feeder/status", &j);
        logFeedAction("Feed dispensed", "auto");
    }
    feedBusy = false;
}

static void pollCommands() {
    if (!Firebase.ready()) return;
    unsigned long now = millis();
    if (now - lastCmdPoll < 5000) return;
    lastCmdPoll = now;

    FirebaseJson j;
    if (!Firebase.RTDB.getJSON(&fbW, "/feeder/commands", &j)) return;

    FirebaseJsonData d;
    size_t n = j.iteratorBegin();
    if (n > 0) Serial.printf("[POLL] %u command(s) found\n", n);
    for (size_t i = 0; i < n; i++) {
        int itType;
        String key, value;
        j.iteratorGet(i, itType, key, value);
        if (itType == FirebaseJson::JSON_OBJECT) {
            FirebaseJson sub;
            sub.setJsonData(value);
            sub.get(d, "action");
            if (d.stringValue == "feed_now") {
                sub.get(d, "timestamp");
                int64_t ts = (int64_t)d.doubleValue;
                int64_t nowMs = (int64_t)getEpochMillis();
                if (nowMs > 0 && nowMs - ts < 30000) {
                    Serial.printf("[POLL] Processing feed command %s\n", key.c_str());
                    String path = String("/feeder/commands/") + key;
                    Firebase.RTDB.deleteNode(&fbW, path);
                    doFeed();
                } else if (nowMs > 0) {
                    Serial.printf("[POLL] Removing stale command %s\n", key.c_str());
                    Firebase.RTDB.deleteNode(&fbW, String("/feeder/commands/") + key);
                }
            }
        }
    }
    j.iteratorEnd();
}

static void writeStatus() {
    if (!Firebase.ready()) return;
    FirebaseJson j;
    j.add("isRunning", feedBusy);
    j.add("feedCount", feedCount);
    j.add("lastSeen", (double)getEpochMillis());
    j.add("hopperLevel", 100.0);
    j.add("feedSource", "esp32");
    j.add("feederError", "");
    Firebase.RTDB.setJSON(&fbW, "/feeder/status", &j);
}

static void printHelp() {
    Serial.println("Commands:");
    Serial.println("  n1on / n1off       Aerator 1 ON/OFF");
    Serial.println("  n2on / n2off       Aerator 2 ON/OFF");
    Serial.println("  n3on / n3off       Pump ON/OFF");
    Serial.println("  relay status       Show relay states");
    Serial.println("  servopause <ms>    Set servo open pause");
    Serial.println("  servocycle         Run one feed cycle");
    Serial.println("  wifissid <s>       Set WiFi SSID");
    Serial.println("  wifipass <p>       Set WiFi password");
    Serial.println("  wifireset          Reset WiFi credentials");
    Serial.println("  wifistatus         Show stored credentials");
    Serial.println("  help / ?           This list");
}

static void processSerial() {
    if (!Serial.available()) return;
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.length() == 0) return;
    int sp = line.indexOf(' ');
    String cmd = (sp == -1) ? line : line.substring(0, sp);
    String arg = (sp == -1) ? "" : line.substring(sp + 1);
    cmd.toLowerCase();

    if (cmd == "help" || cmd == "?") { printHelp(); return; }
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
    if (cmd == "wifissid") {
        arg.trim();
        if (arg.length() > 0 && arg.length() <= 32) {
            saveWifiSSIDToNVS(arg.c_str());
            Serial.printf("[CMD] SSID saved: %s\n", arg.c_str());
        }
        return;
    }
    if (cmd == "wifipass") {
        arg.trim();
        if (arg.length() > 0 && arg.length() <= 64) {
            saveWifiPasswordToNVS(arg.c_str());
            Serial.println("[CMD] Password saved");
        }
        return;
    }
    if (cmd == "wifireset") { resetWifiToDefault(); return; }
    if (cmd == "wifistatus") {
        Serial.printf("SSID: %s\n", getStoredWifiSSID().c_str());
        Serial.printf("Pass: %s (%u chars)\n",
            getStoredWifiPassword().length() > 0 ? "***" : "(empty)",
            getStoredWifiPassword().length());
        return;
    }
    Serial.println("[CMD] Unknown - type 'help'");
}

void setup() {
    Serial.begin(115200);
    Serial.println("=== CrayCare Servo + Relay Firmware ===");

    pinMode(PIN_A1, OUTPUT); digitalWrite(PIN_A1, HIGH);
    pinMode(PIN_A2, OUTPUT); digitalWrite(PIN_A2, HIGH);
    pinMode(PIN_P,  OUTPUT); digitalWrite(PIN_P,  HIGH);

    initServo();

    loadWifiFromNVS();
    connectWiFi();
}

static bool initialConnectDone = false;

void loop() {
    processSerial();

    if (!initialConnectDone) {
        if (WiFi.status() != WL_CONNECTED) {
            static unsigned long lastWifiRetry = 0;
            unsigned long now = millis();
            if (now - lastWifiRetry > 10000) {
                lastWifiRetry = now;
                connectWiFi();
            }
            return;
        }
        initTime();
        connectFirebase();
        initialConnectDone = true;
        Serial.println("[MAIN] Initial WiFi+Firebase connect done");
    }

    if (Firebase.ready()) {
        writeStatus();

        pollModes();
        pollCommands();

        unsigned long now = millis();
        if (now - lastStatus >= 5000) {
            writeStatus();
            lastStatus = now;
        }
    }
}
