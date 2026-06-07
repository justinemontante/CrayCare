#pragma once

// Minimal stub definitions to allow compilation without the full Firebase library.
// These provide the subset of the API used by this project.

#include <Arduino.h>

struct FirebaseData {
    String _errorReason = "";
    const char* errorReason() const { return _errorReason.c_str(); }
    void setError(const char* msg) { _errorReason = msg; }
    // In real library, jsonObject() returns FirebaseJson*; stub returns nullptr.
    bool jsonObject() const { return false; }
};

struct FirebaseAuth {
    // Stub tokenReady always true.
    bool tokenReady() const { return true; }
    // Placeholder for user credentials.
    struct { const char* email = nullptr; const char* password = nullptr; } user;
};

struct FirebaseConfig {
    const char* api_key = nullptr;
    const char* database_url = nullptr;
};

class FirebaseJson {
public:
    void add(const char* key, const char* value) {}
    void add(const char* key, double value) {}
    void add(const char* key, bool value) {}
    // For compatibility with .as<T>() in stub, provide conversion operators.
    // Not used in this stub.
};

class FirebaseRTDBClass {
public:
    bool setJSON(FirebaseData* fbdo, const char* path, FirebaseJson* json) { return true; }
    bool setJSON(FirebaseData* fbdo, const char* path, const String& payload) { return true; }
    bool getJSON(FirebaseData* fbdo, const char* path) { return false; }
};

class FirebaseClass {
public:
    FirebaseRTDBClass RTDB;
    bool ready() const { return true; }
    void begin(FirebaseConfig* config, FirebaseAuth* auth) {}
    bool signUp(FirebaseAuth* auth, const char* email, const char* password) { return true; }
};

// Global instance as in original library.
extern FirebaseClass Firebase;
