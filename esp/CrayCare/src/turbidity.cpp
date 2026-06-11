#include "turbidity.h"

// ----- Pin values -----
const int TURBIDITY_PIN = 34; // analog input (ADC1 channel 6 on ESP32)
const int ONE_WIRE_PIN = 4;   // DS18B20 data pin

// ----- Calibration defaults -----
float turbidityVClear = 1.50f; // volts for 0 NTU (clear water)
float turbidityVDirty = 1.65f; // volts for ~500 NTU (dirty water)
float turbidityVAir   = 1.00f; // volts below which we consider "air"

bool turbidityAir = false;

// ----- Sensor objects -----
OneWire oneWire(ONE_WIRE_PIN);
DallasTemperature ds18b20(&oneWire);

// For smoothing turbidity values (simple moving average)
static const size_t TURB_BUF_SIZE = 20;
static float turbBuf[TURB_BUF_SIZE];
static size_t turbIdx = 0;
static bool turbBufFilled = false;

void loadTurbidityFromNVS() {
    prefs.begin("turbidity", false);
    turbidityVClear = prefs.getFloat("vClear", turbidityVClear);
    turbidityVDirty = prefs.getFloat("vDirty", turbidityVDirty);
    turbidityVAir   = prefs.getFloat("vAir",   turbidityVAir);
    prefs.end();
    Serial.printf("[NVS] Loaded turbidity calibration: clear=%.3f V, dirty=%.3f V, air=%.3f V\n",
                  turbidityVClear, turbidityVDirty, turbidityVAir);
}

void saveTurbidityToNVS() {
    prefs.begin("turbidity", false);
    prefs.putFloat("vClear", turbidityVClear);
    prefs.putFloat("vDirty", turbidityVDirty);
    prefs.putFloat("vAir",   turbidityVAir);
    prefs.end();
    Serial.println("[NVS] Saved turbidity calibration");
}

void loadTurbidityFromFirebase() {
    // Stub: No Firebase calibration fetch in this build.
    Serial.println("[FIREBASE] loadTurbidityFromFirebase stub called – no action");
}

float readTurbidityVoltage() {
    // Oversample: take 10 readings, average them
    float sum = 0.0f;
    for (int s = 0; s < 50; s++) {
        sum += analogRead(TURBIDITY_PIN);
        delay(2);
    }
    float raw = (sum / 50.0f) / 4095.0f * 3.3f;
    // Store in moving‑average buffer (size 10)
    turbBuf[turbIdx++] = raw;
    if (turbIdx >= TURB_BUF_SIZE) {
        turbIdx = 0;
        turbBufFilled = true;
    }
    // Compute average of buffer
    float avg = 0.0f;
    size_t count = turbBufFilled ? TURB_BUF_SIZE : turbIdx;
    for (size_t i = 0; i < count; ++i) avg += turbBuf[i];
    return avg / (float)count;
}

float ntuFromVoltage(float V) {
    // Clamp to calibration range
    if (V <= turbidityVClear) return 0.0f;
    if (V >= turbidityVDirty) return 500.0f; // approximate upper bound
    // Linear interpolation between clear and dirty
    float fraction = (V - turbidityVClear) / (turbidityVDirty - turbidityVClear);
    return fraction * 500.0f; // 0‑500 NTU range
}

String buildSensorJson(float temperatureC, float turbidityNTU) {
    // Compose a compact JSON payload for Firebase "latest"
    String json = "{";
    json += "\"temperature\":" + String(temperatureC, 2) + ",";
    json += "\"turbidity\":" + String(turbidityNTU, 2) + ",";
    json += "\"turbidityAir\":";
    json += (turbidityAir ? "true" : "false");
    json += "}";
    return json;
}

void updateTurbidityCalibration(float clearV, float dirtyV, float airV) {
    turbidityVClear = clearV;
    turbidityVDirty = dirtyV;
    turbidityVAir   = airV;
    saveTurbidityToNVS();
}

// Helper to initialize DS18B20 sensor – called from setup wrappers.
void initTemperatureSensor() {
    ds18b20.begin();
    // Optionally check device count
    Serial.print("[TEMP] DS18B20 devices found: ");
    Serial.println(ds18b20.getDeviceCount());
}

float readTemperatureC() {
    ds18b20.requestTemperatures();
    // Assuming only one sensor; get the first address
    return ds18b20.getTempCByIndex(0);
}
