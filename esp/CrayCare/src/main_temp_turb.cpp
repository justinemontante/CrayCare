#include "common.h"
#include "turbidity.h"

// Simple wrapper that runs only the sensor logic (no servo).

void setup() {
    Serial.begin(115200);
    Serial.println("=== CrayCare – Sensor‑Only Firmware ===");
    if (!ensureFirebaseReady()) {
        Serial.println("[ERROR] Firebase not ready – continuing with sensor only");
    }
    // Load calibration from NVS and start DS18B20
    loadTurbidityFromNVS();
    initTemperatureSensor();
}

unsigned long lastPublish = 0;
const unsigned long publishInterval = 5000; // ms

void loop() {
    // Read sensors
    float temperatureC = readTemperatureC();
    float turbVoltage = readTurbidityVoltage();
    turbidityAir = (turbVoltage < turbidityVAir);
    float turbNTU = ntuFromVoltage(turbVoltage);

    // Debug output
    Serial.printf("[DEBUG] Temp %.2f C | Turb V %.3f V | Air %s\n",
                  temperatureC, turbVoltage, turbidityAir ? "YES" : "NO");

    // Publish to Firebase at interval
    unsigned long now = millis();
    if (now - lastPublish >= publishInterval && Firebase.ready()) {
        String payload = buildSensorJson(temperatureC, turbNTU);
        String path = "/sensor_data/latest"; // example node
        if (Firebase.RTDB.setJSON(&fbdo, path, payload)) {
            Serial.println("[FIREBASE] Published latest sensor data");
        } else {
            Serial.print("[FIREBASE] Publish failed: ");
            Serial.println(fbdo.errorReason());
        }
        lastPublish = now;
    }

    delay(500); // sensor loop delay
}
