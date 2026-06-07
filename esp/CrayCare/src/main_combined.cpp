#include "common.h"
#include "turbidity.h"
#include "servo_ctrl.h"

// Combined firmware – runs sensor polling, servo feeding, Firebase sync, and Serial UI.

// Timing intervals (ms)
const unsigned long SENSOR_READ_INTERVAL   = 500;   // 0.5 s
const unsigned long FIREBASE_PUBLISH_INTERVAL = 5000; // 5 s (latest data)
const unsigned long FIREBASE_HISTORY_INTERVAL = 60000; // 60 s (historical log)
const unsigned long TURB_CONFIG_RELOAD_INTERVAL = 60000; // 60 s

unsigned long lastSensorRead = 0;
unsigned long lastPublish = 0;
unsigned long lastHistory = 0;
unsigned long lastConfigReload = 0;

// Helper to send the latest sensor JSON to Firebase under "/sensor_data/latest"
void publishLatest(float temperatureC, float turbNTU) {
    if (!Firebase.ready()) return;
    FirebaseJson json;
    json.add("temperature", temperatureC);
    json.add("turbidity", turbNTU);
    json.add("turbidityAir", turbidityAir);
    if (Firebase.RTDB.setJSON(&fbdo, "/sensor_data/latest", &json)) {
        Serial.println("[FIREBASE] Latest sensor data sent");
    } else {
        Serial.print("[FIREBASE] Publish failed: ");
        Serial.println(fbdo.errorReason());
    }
}
// Helper to push a history entry with timestamp under "/sensor_data/history/<epoch>"
void publishHistory(float temperatureC, float turbNTU) {
    if (!Firebase.ready()) return;
    unsigned long epoch = getEpochMillis();
    String path = "/sensor_data/history/" + String(epoch);
    FirebaseJson json;
    json.add("temperature", temperatureC);
    json.add("turbidity", turbNTU);
    json.add("turbidityAir", turbidityAir);
    if (Firebase.RTDB.setJSON(&fbdo, path.c_str(), &json)) {
        Serial.println("[FIREBASE] History entry logged");
    } else {
        Serial.print("[FIREBASE] History failed: ");
        Serial.println(fbdo.errorReason());
    }
}

// ----------------------------- Serial command handling -----------------------------
void printHelp() {
    Serial.println("Available commands:");
    Serial.println("  servoPause <ms>   – set pause (open → close) in ms");
    Serial.println("  servoCycle <ms>   – set full cycle period (optional, 0 = default behavior)");
    Serial.println("  turbClear <V>     – set clear‑water calibration voltage");
    Serial.println("  turbDirty <V>     – set dirty‑water calibration voltage");
    Serial.println("  turbAir <V>       – set air‑threshold voltage");
    Serial.println("  wifiSSID <SSID>   – set Wi‑Fi network name (saved to NVS, password unchanged)");
    Serial.println("  wifiPass <pass>   – set Wi‑Fi password (saved to NVS)");
    Serial.println("  wifiReset         – clear saved SSID and password, revert to defaults");
    Serial.println("  wifiStatus        – show currently stored credentials");
    Serial.println("  help or ?         – show this list");
}

void processSerialCommands() {
    if (!Serial.available()) return;
    String line = Serial.readStringUntil('\n');
    line.trim();
    line.toLowerCase(); // command keyword case‑insensitive
    if (line.length() == 0) return;
    // Split into command + argument
    int spaceIdx = line.indexOf(' ');
    String cmd = (spaceIdx == -1) ? line : line.substring(0, spaceIdx);
    String arg = (spaceIdx == -1) ? "" : line.substring(spaceIdx + 1);

    if (cmd == "help" || cmd == "?") {
        printHelp();
        return;
    }

    if (cmd == "servopause") {
        uint32_t val = arg.toInt();
        if (val > 0) {
            servoPauseMs = val;
            Serial.printf("[CMD] Servo pause set to %u ms\n", servoPauseMs);
        }
        return;
    }
    if (cmd == "servocycle") {
        uint32_t val = arg.toInt();
        servoCycleMs = val; // may be zero
        Serial.printf("[CMD] Servo cycle interval set to %u ms\n", servoCycleMs);
        return;
    }
    if (cmd == "turblclear" || cmd == "turbclear") {
        float v = arg.toFloat();
        if (v > 0) {
            turbidityVClear = v;
            saveTurbidityToNVS();
            Serial.printf("[CMD] turbidityVClear = %.3f V\n", turbidityVClear);
        }
        return;
    }
    if (cmd == "turbdirty") {
        float v = arg.toFloat();
        if (v > 0) {
            turbidityVDirty = v;
            saveTurbidityToNVS();
            Serial.printf("[CMD] turbidityVDirty = %.3f V\n", turbidityVDirty);
        }
        return;
    }
    if (cmd == "turbair") {
        float v = arg.toFloat();
        if (v > 0) {
            turbidityVAir = v;
            saveTurbidityToNVS();
            Serial.printf("[CMD] turbidityVAir = %.3f V\n", turbidityVAir);
        }
        return;
    }
    // ----- Wi‑Fi commands -----
    if (cmd == "wifissid") {
        arg.trim();
        if (arg.length() == 0) {
            Serial.println("[CMD] SSID cannot be empty");
        } else {
            if (arg.length() > 32) arg = arg.substring(0,32);
            saveWifiSSIDToNVS(arg.c_str());
            Serial.printf("[CMD] Wi‑Fi SSID saved as %s\n", arg.c_str());
        }
        return;
    }
    if (cmd == "wifipass") {
        arg.trim();
        if (arg.length() == 0) {
            Serial.println("[CMD] Password cannot be empty");
        } else {
            if (arg.length() > 64) arg = arg.substring(0,64);
            saveWifiPasswordToNVS(arg.c_str());
            Serial.println("[CMD] Wi‑Fi password saved");
        }
        return;
    }
    if (cmd == "wifireset") {
        resetWifiToDefault();
        Serial.println("[CMD] Wi‑Fi credentials reset to compile‑time defaults");
        return;
    }
    if (cmd == "wifistatus") {
        String curSSID = getStoredWifiSSID();
        String curPass = getStoredWifiPassword();
        Serial.printf("[STATUS] Stored SSID: %s\n", curSSID.c_str());
        Serial.printf("[STATUS] Stored password: %s (length %u)\n", curPass.length() > 0 ? "***" : "(empty)", curPass.length());
        return;
    }
    Serial.println("[CMD] Unknown command – type 'help' for list");
}

void setup() {
    Serial.begin(115200);
    Serial.println("=== CrayCare – Combined Servo + Sensor Firmware ===");
    // Initialize core services
    if (!ensureFirebaseReady()) {
        Serial.println("[WARN] Firebase not ready – continuing with partial functionality");
    }
    // Load calibration from NVS and start sensors
    loadTurbidityFromNVS();
    initTemperatureSensor();
    initServo();
    // Initial config pull from Firebase (if any)
    loadTurbidityFromFirebase();
    lastConfigReload = millis();
}

void loop() {
    unsigned long now = millis();

    // ---- Serial UI ----
    processSerialCommands();

    // ---- Sensor read (every 500 ms) ----
    if (now - lastSensorRead >= SENSOR_READ_INTERVAL) {
        float temperatureC = readTemperatureC();
        float turbVoltage = readTurbidityVoltage();
        turbidityAir = (turbVoltage < turbidityVAir);
        float turbNTU = ntuFromVoltage(turbVoltage);

        // Debug output
        Serial.printf("[DEBUG] Temp %.2f C | Turb V %.3f V | Air %s\n",
                      temperatureC, turbVoltage, turbidityAir ? "YES" : "NO");

        // Publish latest every FIREBASE_PUBLISH_INTERVAL (if time)
        if (now - lastPublish >= FIREBASE_PUBLISH_INTERVAL) {
            publishLatest(temperatureC, turbNTU);
            lastPublish = now;
        }
        // History log every FIREBASE_HISTORY_INTERVAL
        if (now - lastHistory >= FIREBASE_HISTORY_INTERVAL) {
            publishHistory(temperatureC, turbNTU);
            lastHistory = now;
        }
        lastSensorRead = now;
    }

    // ---- Servo feeding cycle ----
    static unsigned long lastServoCycle = 0;
    if (now - lastServoCycle >= (servoCycleMs > 0 ? servoCycleMs : (servoPauseMs + 2000))) {
        // Run a feeding cycle (open → pause → close → optional extra wait)
        executeServoCycle();
        lastServoCycle = now;
    }

    // ---- Periodic turbidity config reload from Firebase ----
    if (now - lastConfigReload >= TURB_CONFIG_RELOAD_INTERVAL) {
        loadTurbidityFromFirebase();
        lastConfigReload = now;
    }
}
