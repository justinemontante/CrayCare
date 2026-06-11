#include "common.h"
#include <stdlib.h> // for strdup, free

// ***** Wi‑Fi & Firebase credentials *****

// ----- Wi‑Fi NVS constants -----
const char* WIFI_NAMESPACE = "wifi";
const char* WIFI_KEY_SSID  = "ssid";
const char* WIFI_KEY_PASS  = "password";

// Replace these placeholders with your actual network and Firebase details.
const char* ssid = "YOUR_SSID";
const char* password = "YOUR_PASSWORD";

const char* firebase_api_key = "AIzaSyBIidS1Y6wysetztz1pSSIWlHTcaQFeAE4";
const char* firebase_user_email = "esp32@craycare.com";
const char* firebase_user_password = "Craycare123";
const char* firebase_database_url = "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app";

// ***** Global Firebase objects *****
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// ***** Preferences (NVS) *****
Preferences prefs;

void connectWiFi() {
    Serial.print("[WIFI] Connecting to ");
    Serial.println(ssid);
    WiFi.begin(ssid, password);
    uint8_t attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30) {
        delay(500);
        Serial.print(".");
        attempts++;
    }
    if (WiFi.status() == WL_CONNECTED) {
        Serial.println();
        Serial.print("[WIFI] Connected! IP: ");
        Serial.println(WiFi.localIP());
    } else {
        Serial.println("\n[WIFI] Connection failed");
    }
}

void initTime() {
    // Configure NTP – required for Firebase token signing
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");
    struct tm timeInfo;
    if (!getLocalTime(&timeInfo)) {
        Serial.println("[TIME] Failed to obtain time");
    } else {
        Serial.println("[TIME] Time synchronized");
    }
}

#ifdef USE_REAL_FIREBASE
void tokenStatusCallback(TokenInfo info) {
    Serial.printf("[FIREBASE] Token status: %s\n",
        info.status == token_status_ready ? "ready" : "update");
}

bool connectFirebase() {
    config.api_key = firebase_api_key;
    config.database_url = firebase_database_url;
    config.token_status_callback = tokenStatusCallback;
    auth.user.email = firebase_user_email;
    auth.user.password = firebase_user_password;
    Firebase.reconnectWiFi(true);
    fbdo.setResponseSize(4096);
    Firebase.begin(&config, &auth);
    Serial.println("[FIREBASE] begin() called — connecting...");
    return true;
}
#else
bool connectFirebase() {
    Serial.println("[FIREBASE] Stubbed connection – no real Firebase used");
    return true;
}
#endif

bool ensureFirebaseReady() {
    // Load any stored SSID from NVS (non‑volatile configuration)
    loadWifiFromNVS();
    connectWiFi();
    if (WiFi.status() != WL_CONNECTED) return false;
    initTime();
    return connectFirebase();
}

// ----- Wi‑Fi NVS helpers ---------------------------------------------------
void loadWifiFromNVS() {
    prefs.begin(WIFI_NAMESPACE, false);
    String storedSSID = prefs.getString(WIFI_KEY_SSID, "");
    String storedPass = prefs.getString(WIFI_KEY_PASS, "");
    prefs.end();
    if (storedSSID.length() > 0) {
        if (ssid && ssid != "YOUR_SSID") free((void*)ssid);
        ssid = strdup(storedSSID.c_str());
        Serial.println("[NVS] Loaded stored Wi‑Fi SSID");
    } else {
        Serial.println("[NVS] No saved SSID – using default");
    }
    if (storedPass.length() > 0) {
        if (password && password != "YOUR_PASSWORD") free((void*)password);
        password = strdup(storedPass.c_str());
        Serial.println("[NVS] Loaded stored Wi‑Fi password");
    } else {
        Serial.println("[NVS] No saved password – using default");
    }
}

void saveWifiSSIDToNVS(const char* newSSID) {
    if (ssid && ssid != "YOUR_SSID") free((void*)ssid);
    ssid = strdup(newSSID);
    prefs.begin(WIFI_NAMESPACE, false);
    prefs.putString(WIFI_KEY_SSID, newSSID);
    prefs.end();
    Serial.println("[NVS] Wi‑Fi SSID saved");
}

void saveWifiPasswordToNVS(const char* newPass) {
    if (password && password != "YOUR_PASSWORD") free((void*)password);
    password = strdup(newPass);
    prefs.begin(WIFI_NAMESPACE, false);
    prefs.putString(WIFI_KEY_PASS, newPass);
    prefs.end();
    Serial.println("[NVS] Wi‑Fi password saved");
}

void resetWifiToDefault() {
    prefs.begin(WIFI_NAMESPACE, false);
    prefs.remove(WIFI_KEY_SSID);
    prefs.remove(WIFI_KEY_PASS);
    prefs.end();
    if (ssid && ssid != "YOUR_SSID") free((void*)ssid);
    ssid = "YOUR_SSID";
    password = "YOUR_PASSWORD";
    Serial.println("[NVS] Wi‑Fi credentials cleared – defaults will be used");
}

String getStoredWifiSSID() {
    prefs.begin(WIFI_NAMESPACE, false);
    String stored = prefs.getString(WIFI_KEY_SSID, ssid);
    prefs.end();
    return stored;
}

String getStoredWifiPassword() {
    prefs.begin(WIFI_NAMESPACE, false);
    String stored = prefs.getString(WIFI_KEY_PASS, password);
    prefs.end();
    return stored;
}

uint64_t getEpochMillis() {
    struct tm timeInfo;
    if (!getLocalTime(&timeInfo)) {
        return 0;
    }
    return (uint64_t)mktime(&timeInfo) * 1000ULL;
}
