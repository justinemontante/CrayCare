#include <Arduino.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <Preferences.h>
#include "do_ctrl.h"

Preferences prefs;

#define LCD_ADDR    0x27
#define LCD_COLS    16
#define LCD_ROWS    2

#define SENSOR_INTERVAL  1000
#define LCD_INTERVAL     500

#define FIXED_TEMP_C     25.0f

#define STABLE_BUF_SIZE   10
#define STABLE_RANGE_THR  0.1f
#define STABLE_COUNT_REQ  5
#define CALIB_MSG_MS      3000

static LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS);
static float currentDO = 5.0f;
static unsigned long lastSensorRead = 0;
static unsigned long lastLcdUpdate = 0;
static bool debugMode = false;
static uint8_t lcdAddress = 0;

static float doBuf[STABLE_BUF_SIZE];
static size_t doIdx = 0;
static bool doBufFilled = false;
static bool isStable = false;
static int stableCount = 0;
static unsigned long calibMsgUntil = 0;
static float lastCalibVoltage = 0;

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
    Serial.println("[LCD] Not detected (check wiring, 5V, SDA=21, SCL=22)");
    return false;
}

static float readRawDOVoltage() {
    uint32_t sum = 0;
    for (int i = 0; i < 10; i++) {
        sum += analogRead(DO_PIN);
        delay(1);
    }
    return (sum / 10.0f) * (3.3f / 4095.0f);
}

static void checkStability(float doValue) {
    doBuf[doIdx++] = doValue;
    if (doIdx >= STABLE_BUF_SIZE) {
        doIdx = 0;
        doBufFilled = true;
    }
    size_t count = doBufFilled ? STABLE_BUF_SIZE : doIdx;
    if (count < 3) return;

    float minVal = doBuf[0], maxVal = doBuf[0];
    for (size_t i = 1; i < count; i++) {
        if (doBuf[i] < minVal) minVal = doBuf[i];
        if (doBuf[i] > maxVal) maxVal = doBuf[i];
    }
    float range = maxVal - minVal;

    if (range < STABLE_RANGE_THR) {
        stableCount++;
        if (stableCount >= STABLE_COUNT_REQ && !isStable) {
            isStable = true;
            Serial.printf("[DO] ** STABLE ** (range=%.3f over %u samples)\n", range, count);
        }
    } else {
        stableCount = 0;
        if (isStable) {
            isStable = false;
            Serial.printf("[DO] Unstable (range=%.3f) - stabilizing...\n", range);
        }
    }
}

static void updateLCD() {
    if (lcdAddress == 0) return;
    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.printf("DO:%5.1f mg/L", currentDO);

    unsigned long now = millis();
    if (now < calibMsgUntil) {
        lcd.setCursor(0, 1);
        lcd.printf("Calibrated! %.3fV", lastCalibVoltage);
        return;
    }

    lcd.setCursor(0, 1);
    if (debugMode) {
        float v = readRawDOVoltage();
        lcd.printf("V:%1.3fV T:%dC", v, FIXED_TEMP_C);
    } else if (isStable) {
        lcd.printf("** STABLE ** doclear");
    } else {
        lcd.printf("Stabilizing...");
    }
}

static void printHelp() {
    Serial.println();
    Serial.println("=== DO Local Test Commands ===");
    Serial.println("  doclear       Calibrate DO in air");
    Serial.println("  debugmode     Toggle debug (show raw V)");
    Serial.println("  restart       Reboot ESP32");
    Serial.println("  help / ?      This list");
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
    cmd.toLowerCase();

    if (cmd == "help" || cmd == "?") { printHelp(); return; }
    if (cmd == "doclear") {
        calibrateDOInAir();
        calibMsgUntil = millis() + CALIB_MSG_MS;
        lastCalibVoltage = doAirVoltage;
        return;
    }
    if (cmd == "debugmode") { debugMode = !debugMode; Serial.printf("[CMD] Debug mode: %s\n", debugMode ? "ON" : "OFF"); return; }
    if (cmd == "restart") { Serial.println("[CMD] Rebooting..."); delay(500); ESP.restart(); }
    Serial.println("[CMD] Unknown - type 'help'");
}

void setup() {
    Serial.begin(115200);
    Serial.println("=== DO Local Test ===");

    analogSetAttenuation(ADC_11db);
    analogSetWidth(12);
    analogSetPinAttenuation(DO_PIN, ADC_11db);

    initDOSensor();

    if (detectLCD()) {
        lcd.init();
        lcd.backlight();
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print("DO Local Test");
        lcd.setCursor(0, 1);
        lcd.print("Starting...");
        delay(1000);
    }

    Serial.println("[MAIN] Ready - type 'help'");
    Serial.println("[MAIN] Probe in bottle with damp cotton, wait for STABLE, then: doclear");
}

void loop() {
    processSerialCommands();
    unsigned long now = millis();

    if (now - lastSensorRead >= SENSOR_INTERVAL) {
        lastSensorRead = now;
        currentDO = readDO(FIXED_TEMP_C);
        Serial.printf("[DO] %.2f mg/L", currentDO);
        checkStability(currentDO);
        if (isStable) Serial.print("  [STABLE]");
        Serial.println();
    }

    if (now - lastLcdUpdate >= LCD_INTERVAL) {
        lastLcdUpdate = now;
        updateLCD();
    }
}
