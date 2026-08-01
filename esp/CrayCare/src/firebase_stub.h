#pragma once

// Minimal stub definitions to allow compilation without the full Firebase library.
// These provide the subset of the API used by this project.

#include <Arduino.h>

struct FirebaseData {
    String _errorReason = "";
    const char* errorReason() const { return _errorReason.c_str(); }
    void setError(const char* msg) { _errorReason = msg; }
    bool jsonObject() const { return false; }
    String data() const { return ""; }
    void setResponseSize(int) {}
};

struct FirebaseAuth {
    bool tokenReady() const { return true; }
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
    void setJsonData(const String&) {}
    bool get(FirebaseJsonData& d, const char* key) const { return false; }
    size_t iteratorBegin() { return 0; }
    void iteratorGet(size_t, int&, String&, String&) {}
    void iteratorEnd() {}
};

struct FirebaseJsonData {
    String stringValue;
    double doubleValue = 0;
    float floatValue = 0;
    bool boolValue = false;
};

class FirebaseRTDBClass {
public:
    bool setJSON(FirebaseData* fbdo, const char* path, FirebaseJson* json) { return true; }
    bool setJSON(FirebaseData* fbdo, const char* path, const String& payload) { return true; }
    bool getJSON(FirebaseData* fbdo, const char* path) { return false; }
    bool getJSON(FirebaseData* fbdo, const char* path, FirebaseJson* json) { return false; }
    bool setBool(FirebaseData* fbdo, const char* path, bool value) { return true; }
    bool push(FirebaseData* fbdo, const char* path, FirebaseJson* json) { return true; }
    bool pushJSON(FirebaseData* fbdo, const char* path, FirebaseJson* json) { return true; }
    bool deleteNode(FirebaseData* fbdo, const char* path) { return true; }
};

class FirebaseFirestoreClass {
public:
    bool setDocument(FirebaseData* fbdo, const char* projectID, const char* token,
                     const char* docPath, FirebaseJson* json, const char* mask = "") { return true; }
    bool createDocument(FirebaseData* fbdo, const char* projectID, const char* token,
                        const char* colPath, FirebaseJson* json, const char* mask = "") { return true; }
    bool getDocument(FirebaseData* fbdo, const char* projectID, const char* token,
                     const char* docPath, const char* mask = "") { return false; }
    bool deleteDocument(FirebaseData* fbdo, const char* projectID, const char* token,
                        const char* docPath) { return true; }
    bool listDocuments(FirebaseData* fbdo, const char* projectID, const char* token,
                       const char* colPath, const char* pageToken = "", int pageSize = 100) { return false; }
};

class FirebaseClass {
public:
    FirebaseRTDBClass RTDB;
    FirebaseFirestoreClass Firestore;
    bool ready() const { return true; }
    void begin(FirebaseConfig* config, FirebaseAuth* auth) {}
    bool signUp(FirebaseAuth* auth, const char* email, const char* password) { return true; }
};

// Global instance as in original library.
extern FirebaseClass Firebase;
