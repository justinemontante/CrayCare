#include "common.h"
#include "turbidity.h"
#include <LiquidCrystal_I2C.h>
#include <Wire.h>

// =============================================================================
// CONFIGURATION
// =============================================================================

// --- Pins ---
#define TRIG_PIN        32
#define ECHO_PIN        33
// DS18B20: GPIO 4 (via turbidity.h)
// Turbidity: GPIO 34 (via turbidity.h)
// LCD I2C: SDA=GPIO21, SCL=GPIO22

// --- Timing (ms) ---
#define SENSOR_INTERVAL     1000
#define PUBLISH_INTERVAL    5000
#define LCD_INTERVAL        3000
#define WIFI_RETRY_INTERVAL 30000

// --- HC-SR04 ---
#define SOUND_SPEED_CM_US   0.034
#define MAX_DIST_CM         400
#define ECHO_TIMEOUT_US     30000

// --- LCD ---
#define LCD_ADDR    0x27
#define LCD_COLS    16
#define LCD_ROWS    2

// =============================================================================

static FirebaseData fb;
static LiquidCrystal_I2C lcd(LCD_ADDR, LCD_COLS, LCD_ROWS);

static unsigned long lastSensorRead = 0;
static unsigned long lastPublish = 0;
static unsigned long lastLcdUpdate = 0;
static unsigned long lastWifiRetry = 0;
static int lcdPage = 0;
static bool initialConnectDone = false;

static float currentTemp = 0;
static float currentTurbNTU = 0;
static float currentTurbV = 0;
static bool currentTurbAir = false;
static float currentWaterCm = -1;
static bool debugMode = false;

// ---- Forward declarations ----
static void scanI2C();
static float readWaterLevelCm();
static void publishSensors();
static void updateLCD();
static void printHelp();
static void processSerialCommands();

// ---- I2C helpers ----
static uint8_t lcdAddress = 0;

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

// ---- HC-SR04 ----
static float readWaterLevelCm() {
    digitalWrite(TRIG_PIN, LOW);
    delayMicroseconds(2);
    digitalWrite(TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(TRIG_PIN, LOW);

    long duration = pulseIn(ECHO_PIN, HIGH, ECHO_TIMEOUT_US);
    if (duration == 0) return -1;

    float distance = duration * SOUND_SPEED_CM_US / 2.0;
    if (distance < 2 || distance > MAX_DIST_CM) return -1;

    return distance;
}

// ---- Firebase publish ----
static void publishSensors() {
    if (!Firebase.ready()) return;

    FirebaseJson j;
    j.add("temperature", currentTemp);
    j.add("turbidity", currentTurbNTU);
    j.add("turbidityAir", currentTurbAir);
    j.add("waterLevelPercent", currentWaterCm);

    if (Firebase.RTDB.setJSON(&fb, "/sensor_readings/latest", &j)) {
        Serial.println("[FIREBASE] Published");
    } else {
        Serial.printf("[FIREBASE] Failed: %s\n", fb.errorReason());
    }
}

// ---- LCD ----
static void updateLCD() {
    if (lcdAddress == 0) return;
    lcdPage = (lcdPage + 1) % 2;
    lcd.clear();

    if (lcdPage == 0) {
        if (debugMode) {
            lcd.setCursor(0, 0);
            lcd.printf("T:%.1fC W:%.0fcm", currentTemp, currentWaterCm >= 0 ? currentWaterCm : 0);
            lcd.setCursor(0, 1);
            lcd.printf("V:%.3fV NTU:%.0f", currentTurbV, currentTurbNTU);
        } else {
            lcd.setCursor(0, 0);
            lcd.printf("T:%.1fC W:%.0fcm", currentTemp, currentWaterCm >= 0 ? currentWaterCm : 0);
            lcd.setCursor(0, 1);
            lcd.printf("Turb:%.1fNTU", currentTurbNTU);
        }
    } else {
        lcd.setCursor(0, 0);
        if (currentWaterCm >= 0) {
            lcd.printf("Water:%.0fcm", currentWaterCm);
        } else {
            lcd.print("Water:--cm  ");
        }
        if (WiFi.status() == WL_CONNECTED) {
            lcd.setCursor(0, 1);
            lcd.print("WiFi OK");
        } else {
            lcd.setCursor(0, 1);
            lcd.print("No WiFi");
        }
    }
}

// ---- Help ----
static void printHelp() {
    Serial.println();
    Serial.println("========== CrayCare Sensor Commands ==========");
    Serial.println("--- WiFi ---");
    Serial.println("  wifissid <SSID>       Save WiFi SSID to NVS");
    Serial.println("  wifipass <PASSWORD>   Save WiFi password to NVS");
    Serial.println("  wifireset             Reset WiFi to defaults");
    Serial.println("  wifistatus            Show stored WiFi credentials");
    Serial.println("");
    Serial.println("--- Turbidity Calibration ---");
    Serial.println("  turbclear <V>         Voltage for 0 NTU (clear water)");
    Serial.println("  turbdirty <V>         Voltage for ~500 NTU (dirty water)");
    Serial.println("  turbair <V>           Voltage threshold for air/no water");
    Serial.println("");
    Serial.println("--- Debug ---");
    Serial.println("  debugmode [0/1]       Toggle or set debug mode (shows raw voltage)");
    Serial.println("  debugstatus           Show system status");
    Serial.println("");
    Serial.println("--- System ---");
    Serial.println("  restart               Reboot ESP32 (use after WiFi change)");
    Serial.println("  i2cscan               Scan I2C bus for devices");
    Serial.println("  help / ?              Show this list");
    Serial.println("=============================================");
    Serial.println();
}

// ---- Serial commands ----
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

    // --- WiFi ---
    if (cmd == "wifissid") {
        arg.trim();
        if (arg.length() > 0 && arg.length() <= 32) {
            saveWifiSSIDToNVS(arg.c_str());
            Serial.printf("[CMD] SSID saved: %s\n", arg.c_str());
            Serial.println("[CMD] Type 'restart' to reconnect with new credentials");
        } else {
            Serial.println("[CMD] SSID must be 1-32 characters");
        }
        return;
    }
    if (cmd == "wifipass") {
        arg.trim();
        if (arg.length() > 0 && arg.length() <= 64) {
            saveWifiPasswordToNVS(arg.c_str());
            Serial.println("[CMD] Password saved");
            Serial.println("[CMD] Type 'restart' to reconnect with new credentials");
        } else {
            Serial.println("[CMD] Password must be 1-64 characters");
        }
        return;
    }
    if (cmd == "wifireset") {
        resetWifiToDefault();
        Serial.println("[CMD] WiFi reset to defaults — type 'restart'");
        return;
    }
    if (cmd == "wifistatus") {
        Serial.printf("  SSID: %s\n", getStoredWifiSSID().c_str());
        Serial.printf("  Password: %s (%u chars)\n",
            getStoredWifiPassword().length() > 0 ? "***" : "(empty)",
            getStoredWifiPassword().length());
        Serial.printf("  Connected: %s\n", WiFi.status() == WL_CONNECTED ? "YES" : "NO");
        if (WiFi.status() == WL_CONNECTED) {
            Serial.printf("  IP: %s\n", WiFi.localIP().toString().c_str());
        }
        return;
    }

    // --- Turbidity calibration ---
    if (cmd == "turbclear" || cmd == "turblclear") {
        float v = arg.toFloat();
        if (v > 0) {
            updateTurbidityCalibration(v, turbidityVDirty, turbidityVAir);
            Serial.printf("[CMD] turbidityVClear = %.3f V (saved to NVS)\n", v);
        } else {
            Serial.println("[CMD] Invalid voltage");
        }
        return;
    }
    if (cmd == "turbdirty") {
        float v = arg.toFloat();
        if (v > 0) {
            updateTurbidityCalibration(turbidityVClear, v, turbidityVAir);
            Serial.printf("[CMD] turbidityVDirty = %.3f V (saved to NVS)\n", v);
        } else {
            Serial.println("[CMD] Invalid voltage");
        }
        return;
    }
    if (cmd == "turbair") {
        float v = arg.toFloat();
        if (v > 0) {
            updateTurbidityCalibration(turbidityVClear, turbidityVDirty, v);
            Serial.printf("[CMD] turbidityVAir = %.3f V (saved to NVS)\n", v);
        } else {
            Serial.println("[CMD] Invalid voltage");
        }
        return;
    }

    // --- Debug ---
    if (cmd == "debugmode") {
        if (arg.length() > 0) {
            debugMode = (arg.toInt() != 0);
        } else {
            debugMode = !debugMode;
        }
        Serial.printf("[CMD] Debug mode: %s\n", debugMode ? "ON" : "OFF");
        return;
    }
    if (cmd == "debugstatus") {
        Serial.printf("  Debug mode: %s\n", debugMode ? "ON" : "OFF");
        Serial.printf("  LCD: %s\n", lcdAddress != 0 ? "Connected" : "Not detected");
        Serial.printf("  WiFi: %s\n", WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected");
        if (WiFi.status() == WL_CONNECTED) {
            Serial.printf("  IP: %s\n", WiFi.localIP().toString().c_str());
        }
        Serial.printf("  Firebase: %s\n", Firebase.ready() ? "Ready" : "Not ready");
        return;
    }

    // --- System ---
    if (cmd == "restart") {
        Serial.println("[CMD] Rebooting...");
        delay(500);
        ESP.restart();
        return;
    }
    if (cmd == "i2cscan") { scanI2C(); return; }

    Serial.println("[CMD] Unknown — type 'help'");
}

// ---- Setup ----
void setup() {
    Serial.begin(115200);
    Serial.println("=== CrayCare — Sensor Firmware ===");

    pinMode(TRIG_PIN, OUTPUT);
    pinMode(ECHO_PIN, INPUT);
    digitalWrite(TRIG_PIN, LOW);

    // Load calibration
    loadTurbidityFromNVS();
    initTemperatureSensor();

    // Detect LCD
    if (detectLCD()) {
        lcd.init();
        lcd.backlight();
        lcd.clear();
        lcd.setCursor(0, 0);
        lcdAddress == 0x3F ? lcd.print("LCD Addr: 0x3F") : lcd.print("LCD Addr: 0x27");
        delay(1500);
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print("CrayCare Sensor");
        lcd.setCursor(0, 1);
        lcd.print("Starting...");
    }

    // WiFi (non-blocking — retry in loop)
    loadWifiFromNVS();
    if (WiFi.status() != WL_CONNECTED) {
        connectWiFi();
    }

    Serial.println("[MAIN] Setup complete — waiting for WiFi in loop()");
    if (lcdAddress != 0) {
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print("Waiting WiFi...");
    }
}

// ---- Loop ----
void loop() {
    processSerialCommands();

    unsigned long now = millis();

    // --- WiFi + Firebase init (retry until connected) ---
    if (!initialConnectDone) {
        if (WiFi.status() == WL_CONNECTED) {
            Serial.println("[MAIN] WiFi connected — initializing Firebase...");
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
            Serial.println("[MAIN] Firebase init done");
            if (lcdAddress != 0) {
                lcd.clear();
                lcd.setCursor(0, 0);
                lcd.print("Sensor Ready!");
                delay(1000);
            }
        } else if (now - lastWifiRetry >= WIFI_RETRY_INTERVAL) {
            lastWifiRetry = now;
            Serial.println("[WIFI] Retrying connection...");
            if (lcdAddress != 0) {
                lcd.clear();
                lcd.setCursor(0, 0);
                lcd.print("Retrying WiFi...");
            }
            connectWiFi();
        }
        return; // don't read sensors until connected
    }

    // --- Sensor reads ---
    if (now - lastSensorRead >= SENSOR_INTERVAL) {
        lastSensorRead = now;
        currentTemp = readTemperatureC();
        currentTurbV = readTurbidityVoltage();
        currentTurbAir = (currentTurbV < turbidityVAir);
        currentTurbNTU = ntuFromVoltage(currentTurbV);
        currentWaterCm = readWaterLevelCm();

        if (debugMode) {
            Serial.printf("[DEBUG] T=%.1fC Turb V=%.3fV NTU=%.1f%s Water=%.0fcm\n",
                currentTemp, currentTurbV, currentTurbNTU, currentTurbAir ? " AIR" : "",
                currentWaterCm >= 0 ? currentWaterCm : 0);
        } else {
            Serial.printf("[SENSORS] T=%.1fC Turb=%.1fNTU%s Water=%.0fcm\n",
                currentTemp, currentTurbNTU, currentTurbAir ? " AIR" : "",
                currentWaterCm >= 0 ? currentWaterCm : 0);
        }
    }

    // --- Firebase publish ---
    if (Firebase.ready() && now - lastPublish >= PUBLISH_INTERVAL) {
        lastPublish = now;
        publishSensors();
    }

    // --- LCD update ---
    if (now - lastLcdUpdate >= LCD_INTERVAL) {
        lastLcdUpdate = now;
        updateLCD();
    }
}
