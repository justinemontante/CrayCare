#pragma once

#include <Arduino.h>
#include <WiFi.h>
#ifdef USE_REAL_FIREBASE
#include <Firebase_ESP_Client.h>
#else
#include "firebase_stub.h"
#endif
#include <Preferences.h>
#include <time.h>

// Wi‑Fi credentials (replace with your own values)
extern const char* ssid;
extern const char* password;

// Firebase credentials (replace with your own values)
extern const char* firebase_api_key;
extern const char* firebase_user_email;
extern const char* firebase_user_password;
extern const char* firebase_database_url;

// Firebase objects (single instance for the whole firmware)
extern FirebaseData fbdo;
extern FirebaseAuth auth;
extern FirebaseConfig config;

// NVS preferences (used for turbidity calibration persistence)
extern Preferences prefs;

// Wi‑Fi NVS keys (persistent SSID + password)
extern const char* WIFI_NAMESPACE;   // "wifi"
extern const char* WIFI_KEY_SSID;   // "ssid"
extern const char* WIFI_KEY_PASS;   // "password"

// Helper functions
void connectWiFi();
void initTime();
bool connectFirebase();
bool ensureFirebaseReady(); // calls Wi‑Fi, time, Firebase in order
unsigned long getEpochMillis();

// Wi‑Fi NVS helper prototypes
void loadWifiFromNVS();
void saveWifiSSIDToNVS(const char* newSSID);
void saveWifiPasswordToNVS(const char* newPass);
void resetWifiToDefault();
String getStoredWifiSSID();
String getStoredWifiPassword();

