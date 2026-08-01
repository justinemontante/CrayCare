/* -------------------------------------------------------------
 *  CrayCare – ESP32 Temperature + Turbidity Only
 *
 *  This sketch reads a DS18B20 temperature sensor (OneWire) and an
 *  analog turbidity sensor, smooths the values, and publishes a minimal
 *  JSON payload to Firebase Realtime Database.
 *
 *  It is deliberately lightweight – no feeder code, no ultrasonic sensor.
 *  Place‑holders (TODO comments) are left for the water‑level sensor that
 *  will be added later.
 * ----------------------------------------------------------- */

#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>
#include <Firebase_ESP_Client.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include <time.h>

// ------------------------------------------------------------------
//  Pin definitions
// ------------------------------------------------------------------
#define TEMP_PIN        4   // OneWire bus for DS18B20
#define TURBIDITY_PIN   34  // ADC1 channel (input only)

// ------------------------------------------------------------------
//  Firebase configuration & paths
// ------------------------------------------------------------------
#define FIREBASE_API_KEY          "AIzaSyCjDOkzE4iubiLx_xA2YufMUMo6jgIKcaw"
#define FIREBASE_DATABASE_URL     "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app"

#define FIREBASE_LATEST_PATH      "/sensor_readings/latest"
#define FIREBASE_HISTORY_PATH     "/sensor_readings/history"

#define FIREBASE_SEND_INTERVAL_MS     5000   // every 5 s – latest payload
#define FIREBASE_HISTORY_INTERVAL_MS  60000   // every 60 s – history entry
#define SENSOR_POLL_MS                500    // read sensors twice per second

// ------------------------------------------------------------------
//  Smoothing buffers
// ------------------------------------------------------------------
#define SMOOTH_WINDOW   10
float tempBuffer[SMOOTH_WINDOW];
float turbidityBuffer[SMOOTH_WINDOW];
uint8_t tempIdx = 0, turbIdx = 0;
uint8_t tempCount = 0, turbCount = 0;

// ------------------------------------------------------------------
//  Calibration constants (same as original code)
// ------------------------------------------------------------------
float turbidityVClear   = 1.50;   // V -> 0 NTU (clear water)
float turbidityVDirty   = 1.40;   // V -> 500 NTU (dirty water)
float turbidityVAirMax  = 1.30;   // V < this = air / no water

// ------------------------------------------------------------------
//  Global objects
// ------------------------------------------------------------------
Preferences prefs;
String ssid, pass;
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
bool firebaseReady = false;

OneWire oneWire(TEMP_PIN);
DallasTemperature tempSensors(&oneWire);

// ------------------------------------------------------------------
//  Helper functions
// ------------------------------------------------------------------
float voltageFromADC(uint8_t pin) {
  uint16_t raw = analogRead(pin);
  return (float)raw * (3.3f / 4095.0f);
}

float ntuFromVoltage(float v) {
  if (v < turbidityVAirMax) return 0.0f;               // air / no water
  float ntu = (turbidityVClear - v) * 500.0f /
              (turbidityVClear - turbidityVDirty);
  if (ntu < 0.0f) ntu = 0.0f;
  if (ntu > 1000.0f) ntu = 1000.0f;
  return ntu;
}

float slidingAverage(const float buffer[], uint8_t count) {
  if (count == 0) return 0.0f;
  float sum = 0.0f;
  uint8_t n = min(count, (uint8_t)SMOOTH_WINDOW);
  for (uint8_t i = 0; i < n; ++i) sum += buffer[i];
  return sum / n;
}

unsigned long getEpochMillis() {
  time_t now;
  time(&now);
  if (now < 1700000000) return 0;
  return (unsigned long)now * 1000UL;
}

// ------------------------------------------------------------------
//  Wi‑Fi & Firebase helpers (reuse original logic)
// ------------------------------------------------------------------
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
    Serial.println(" FAILED — check SSID/password");
    Serial.println("Type RESET_WIFI to reconfigure");
  }
}

void initTime() {
  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("Syncing time");
  for (int i = 0; i < 20; ++i) {
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
  Serial.println("[FIREBASE] Token expired, re‑authenticating...");
  if (Firebase.signUp(&config, &auth, "", "")) {
    firebaseReady = true;
    Serial.println("[FIREBASE] Re‑auth OK");
    return true;
  }
  Serial.printf("[FIREBASE] Re‑auth failed: %s\n", config.signer.signupError.message.c_str());
  return false;
}

// ------------------------------------------------------------------
//  Sensor reading functions
// ------------------------------------------------------------------
void readTemperature() {
  tempSensors.requestTemperatures();
  float raw = tempSensors.getTempCByIndex(0);
  if (raw < -10.0f || raw > 60.0f) return; // sanity check
  tempBuffer[tempIdx] = raw;
  tempIdx = (tempIdx + 1) % SMOOTH_WINDOW;
  if (tempCount < SMOOTH_WINDOW) ++tempCount;
}

void readTurbidity() {
  float voltage = voltageFromADC(TURBIDITY_PIN);
  float ntu = ntuFromVoltage(voltage);
  turbidityBuffer[turbIdx] = ntu;
  turbIdx = (turbIdx + 1) % SMOOTH_WINDOW;
  if (turbCount < SMOOTH_WINDOW) ++turbCount;
}

// ------------------------------------------------------------------
//  Build JSON payload (minimal)
// ------------------------------------------------------------------
void buildSensorJson(FirebaseJson &json) {
  json.set("temperature", slidingAverage(tempBuffer, tempCount));
  json.set("turbidity",  slidingAverage(turbidityBuffer, turbCount));
}

// ------------------------------------------------------------------
//  Setup / Loop
// ------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(500);

  // ADC configuration – same as original code
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  tempSensors.begin();
  connectWiFi();
  initTime();
  connectFirebase();

  Serial.println("\n=== CrayCare – Temp + Turbidity Only ===");
}

void loop() {
  unsigned long now = millis();

  // --------------------------------------------------------------
  // 1️⃣  Poll sensors
  // --------------------------------------------------------------
  static unsigned long lastPoll = 0;
  if (now - lastPoll >= SENSOR_POLL_MS) {
    lastPoll = now;
    readTemperature();
    readTurbidity();
  }

  // --------------------------------------------------------------
  // 2️⃣  Send latest (every 5 s)
  // --------------------------------------------------------------
  static unsigned long lastSend = 0;
  if (now - lastSend >= FIREBASE_SEND_INTERVAL_MS) {
    lastSend = now;
    if (ensureFirebaseReady()) {
      FirebaseJson json;
      buildSensorJson(json);
      if (Firebase.RTDB.updateNode(&fbdo, FIREBASE_LATEST_PATH, &json))
        Serial.println("[FB] Latest sent");
      else
        Serial.printf("[FB] Latest error: %s\n", fbdo.errorReason().c_str());
    }
  }

  // --------------------------------------------------------------
  // 3️⃣  Send history entry (every 60 s)
  // --------------------------------------------------------------
  static unsigned long lastHist = 0;
  if (now - lastHist >= FIREBASE_HISTORY_INTERVAL_MS) {
    lastHist = now;
    if (ensureFirebaseReady()) {
      FirebaseJson json;
      buildSensorJson(json);
      json.set("timestamp", getEpochMillis());
      if (Firebase.RTDB.pushJSON(&fbdo, FIREBASE_HISTORY_PATH, &json))
        Serial.println("[FB] History saved");
      else
        Serial.printf("[FB] History error: %s\n", fbdo.errorReason().c_str());
    }
  }

  // --------------------------------------------------------------
  // 4️⃣  Wi‑Fi reconnect safeguard
  // --------------------------------------------------------------
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WIFI] Reconnecting...");
    WiFi.disconnect();
    WiFi.begin(ssid.c_str(), pass.c_str());
    delay(1000);
  }

  // --------------------------------------------------------------
  // 5️⃣  TODO: Water‑level sensor (ultrasonic) will be added here later
  // --------------------------------------------------------------
  // TODO: readWaterLevel();
  // TODO: include waterLevelPercent in buildSensorJson();
}
