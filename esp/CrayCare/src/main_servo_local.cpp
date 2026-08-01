#include <Arduino.h>
#include <Preferences.h>
#include "servo_ctrl.h"

Preferences prefs;

static int servoOpenAngle = 180;
static int servoCloseAngle = 0;

static const char* NVS_NS = "servo";

static void loadConfig() {
    prefs.begin(NVS_NS, true);
    servoPauseMs = prefs.getUInt("pause", 2000);
    servoOpenAngle = prefs.getInt("openAng", 180);
    servoCloseAngle = prefs.getInt("closeAng", 0);
    prefs.end();
    Serial.printf("[NVS] Loaded: pause=%ums open=%d close=%d\n",
        servoPauseMs, servoOpenAngle, servoCloseAngle);
}

static void saveConfig() {
    prefs.begin(NVS_NS, false);
    prefs.putUInt("pause", servoPauseMs);
    prefs.putInt("openAng", servoOpenAngle);
    prefs.putInt("closeAng", servoCloseAngle);
    prefs.end();
    Serial.println("[NVS] Config saved");
}

static void printHelp() {
    Serial.println();
    Serial.println("=== Servo Local Test Commands ===");
    Serial.println("  open                  Move to open angle");
    Serial.println("  close                 Move to close angle");
    Serial.println("  angle <0-180>         Move to specific angle");
    Serial.println("  cycle                 Open -> pause -> close");
    Serial.println("  pause <ms>            Set and save pause duration");
    Serial.println("  openang <0-180>       Set and save open angle");
    Serial.println("  closeang <0-180>      Set and save close angle");
    Serial.println("  status                Show current config");
    Serial.println("  restart               Reboot ESP32");
    Serial.println("  help / ?              This list");
    Serial.println("================================");
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

    if (cmd == "open") {
        setServoAngle(servoOpenAngle);
        Serial.printf("[CMD] Open -> %d degrees\n", servoOpenAngle);
        return;
    }
    if (cmd == "close") {
        setServoAngle(servoCloseAngle);
        Serial.printf("[CMD] Close -> %d degrees\n", servoCloseAngle);
        return;
    }
    if (cmd == "angle") {
        int a = arg.toInt();
        if (a >= 0 && a <= 180) {
            setServoAngle(a);
            Serial.printf("[CMD] Angle -> %d degrees\n", a);
        } else {
            Serial.println("[CMD] Invalid angle (0-180)");
        }
        return;
    }
    if (cmd == "cycle") {
        Serial.printf("[CMD] Cycle: open=%d pause=%ums close=%d\n",
            servoOpenAngle, servoPauseMs, servoCloseAngle);
        setServoAngle(servoOpenAngle);
        delay(servoPauseMs);
        setServoAngle(servoCloseAngle);
        Serial.println("[CMD] Cycle complete");
        return;
    }
    if (cmd == "pause") {
        uint32_t v = (uint32_t)arg.toInt();
        if (v >= 100 && v <= 30000) {
            servoPauseMs = v;
            saveConfig();
            Serial.printf("[CMD] Pause set to %u ms\n", v);
        } else {
            Serial.println("[CMD] Invalid pause (100-30000 ms)");
        }
        return;
    }
    if (cmd == "openang") {
        int a = arg.toInt();
        if (a >= 0 && a <= 180) {
            servoOpenAngle = a;
            saveConfig();
            Serial.printf("[CMD] Open angle set to %d degrees\n", a);
        } else {
            Serial.println("[CMD] Invalid angle (0-180)");
        }
        return;
    }
    if (cmd == "closeang") {
        int a = arg.toInt();
        if (a >= 0 && a <= 180) {
            servoCloseAngle = a;
            saveConfig();
            Serial.printf("[CMD] Close angle set to %d degrees\n", a);
        } else {
            Serial.println("[CMD] Invalid angle (0-180)");
        }
        return;
    }
    if (cmd == "status") {
        Serial.printf("  Open angle: %d deg\n", servoOpenAngle);
        Serial.printf("  Close angle: %d deg\n", servoCloseAngle);
        Serial.printf("  Pause: %u ms\n", servoPauseMs);
        return;
    }
    if (cmd == "restart") {
        Serial.println("[CMD] Rebooting...");
        delay(500);
        ESP.restart();
    }

    Serial.println("[CMD] Unknown - type 'help'");
}

void setup() {
    Serial.begin(115200);
    Serial.println("=== Servo Local Test ===");

    initServo();
    loadConfig();

    Serial.println("[MAIN] Ready - type 'help'");
}

void loop() {
    processSerialCommands();
}
