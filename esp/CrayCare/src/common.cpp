#include "common.h"
#include <stdlib.h> // for strdup, free
#include "esp_task_wdt.h"

// ***** Wi‑Fi & Firebase credentials *****

// ----- Wi‑Fi NVS constants -----
const char* WIFI_NAMESPACE = "wifi";
const char* WIFI_KEY_SSID  = "ssid";
const char* WIFI_KEY_PASS  = "password";

const char* ssid = NULL;
const char* password = NULL;

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

void initWiFi() {
    WiFi.mode(WIFI_STA);
    WiFi.persistent(false);
    Serial.println("[WIFI] Stack initialized");
}

void connectWiFi() {
    if (!ssid || strlen(ssid) == 0) {
        Serial.println("[WIFI] No credentials — use 'wifissid <SSID>' and 'wifipass <PASS>'");
        return;
    }
    Serial.print("[WIFI] Connecting to \"");
    Serial.print(ssid);
    Serial.println("\"");
    WiFi.begin(ssid, password);
    uint8_t attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 40) {
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
    // Configure NTP – UTC+8 for Philippines/Asia
    configTime(8 * 3600, 0, "asia.pool.ntp.org", "time.google.com");
    struct tm timeInfo;
    if (!getLocalTime(&timeInfo)) {
        Serial.println("[TIME] Failed to obtain time");
    } else {
        Serial.println("[TIME] Time synchronized");
    }
}

#ifdef USE_REAL_FIREBASE
void tokenStatusCallback(TokenInfo info) {
    if (info.status == token_status_ready) {
        Serial.println("[FIREBASE] Token READY");
    } else if (info.status == token_status_error) {
        Serial.printf("[FIREBASE] Token ERROR: %s\n", info.error.message.c_str());
    } else {
        Serial.printf("[FIREBASE] Token: processing...\n");
    }
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
    initWiFi();
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
        if (ssid) free((void*)ssid);
        ssid = strdup(storedSSID.c_str());
        Serial.printf("[NVS] Loaded Wi‑Fi SSID: \"%s\"\n", ssid);
    } else {
        Serial.println("[NVS] No saved WiFi — waiting for serial input");
    }
    if (storedPass.length() > 0) {
        if (password) free((void*)password);
        password = strdup(storedPass.c_str());
        Serial.println("[NVS] Loaded Wi‑Fi password");
    }
}

void saveWifiSSIDToNVS(const char* newSSID) {
    if (ssid) free((void*)ssid);
    ssid = strdup(newSSID);
    prefs.begin(WIFI_NAMESPACE, false);
    prefs.putString(WIFI_KEY_SSID, newSSID);
    prefs.end();
    Serial.println("[NVS] Wi‑Fi SSID saved");
}

void saveWifiPasswordToNVS(const char* newPass) {
    if (password) free((void*)password);
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
    if (ssid) { free((void*)ssid); ssid = NULL; }
    if (password) { free((void*)password); password = NULL; }
    WiFi.disconnect(true);
    Serial.println("[NVS] WiFi cleared — type 'wifissid <SSID>' then 'wifipass <PASS>'");
}

void reconnectWiFi() {
    WiFi.disconnect(true);
    delay(200);
    connectWiFi();
}

void scanWiFiNetworks() {
    Serial.println("[WIFI] Scanning...");
    int n = WiFi.scanNetworks();
    if (n <= 0) {
        Serial.printf("[WIFI] No networks found (code=%d)\n", n);
    } else {
        Serial.printf("[WIFI] %d networks found:\n", n);
        for (int i = 0; i < n; i++) {
            Serial.printf("  %d: \"%s\" (%d dBm) %s\n",
                i + 1,
                WiFi.SSID(i).c_str(),
                WiFi.RSSI(i),
                WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "OPEN" : "secure");
        }
    }
    WiFi.scanDelete();
}

String getStoredWifiSSID() {
    prefs.begin(WIFI_NAMESPACE, false);
    String stored = prefs.getString(WIFI_KEY_SSID, "");
    prefs.end();
    return stored;
}

String getStoredWifiPassword() {
    prefs.begin(WIFI_NAMESPACE, false);
    String stored = prefs.getString(WIFI_KEY_PASS, "");
    prefs.end();
    return stored;
}

uint64_t getEpochMillis() {
    struct tm timeInfo;
    if (!getLocalTime(&timeInfo)) {
        return (uint64_t)millis();  // fallback to uptime when NTP not synced
    }
    return (uint64_t)mktime(&timeInfo) * 1000ULL;
}
