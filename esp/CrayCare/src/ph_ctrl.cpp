#include "ph_ctrl.h"
#include <Preferences.h>

extern Preferences prefs;

// =============================================================================
// HARDWARE
// =============================================================================

const int PH_PIN = 35;
#define PH_DIVIDER_RATIO 0.5f

// =============================================================================
// EXISTING CALIBRATION (phcal7 / phcal4) — uses global prefs, namespace "ph"
// =============================================================================

float pHValue = 7.0f;
float phNeutralVoltage = 2.5f;
float phSlope = 0.18f;

static const size_t PH_BUF_SIZE = 10;
static float phBuf[PH_BUF_SIZE];
static size_t phIdx = 0;
static bool phBufFilled = false;

void initPHSensor() {
    pinMode(PH_PIN, INPUT);
    loadPHCalibration();
}

float readPHRawVoltage() {
    uint32_t sum = 0;
    for (size_t i = 0; i < 10; i++) {
        sum += analogRead(PH_PIN);
        delay(1);
    }
    return (sum / 10.0f) * (3.3f / 4095.0f) / PH_DIVIDER_RATIO;
}

float readPH() {
    // --- Try 686/401 calibration first (namespace "phcal") ---
    {
        Preferences phcalPrefs;
        phcalPrefs.begin("phcal", true);
        float v686_cal = phcalPrefs.getFloat("v686", 0.0f);
        float v401_cal = phcalPrefs.getFloat("v401", 0.0f);
        phcalPrefs.end();

        if (v686_cal > 0.0f && v401_cal > 0.0f) {
            float m = (v686_cal - v401_cal) / (6.86f - 4.01f);
            float s = fabs(m);
            if (s > 0.001f && s < 1.0f) {
                float nv = v686_cal + m * (7.0f - 6.86f);
                float v = readPHRawVoltage();
                float ph = 7.0f + (nv - v) / s;
                if (ph < 0) ph = 0;
                if (ph > 14) ph = 14;
                pHValue = ph;
                return ph;
            }
        }
    }

    // --- Fall back to phcal7 / phcal4 (namespace "ph") ---
    float v = readPHRawVoltage();
    phBuf[phIdx++] = v;
    if (phIdx >= PH_BUF_SIZE) { phIdx = 0; phBufFilled = true; }
    size_t count = phBufFilled ? PH_BUF_SIZE : phIdx;
    float avg = 0;
    for (size_t i = 0; i < count; i++) avg += phBuf[i];
    avg /= count;
    pHValue = 7.0f + (phNeutralVoltage - avg) / phSlope;
    if (pHValue < 0.0f) pHValue = 0.0f;
    if (pHValue > 14.0f) pHValue = 14.0f;
    return pHValue;
}

float readPHRawVoltageFiltered() {
    float v = readPHRawVoltage();
    phBuf[phIdx++] = v;
    if (phIdx >= PH_BUF_SIZE) { phIdx = 0; phBufFilled = true; }
    size_t count = phBufFilled ? PH_BUF_SIZE : phIdx;
    float avg = 0;
    for (size_t i = 0; i < count; i++) avg += phBuf[i];
    return avg / count;
}

void calibratePH7() {
    float v = readPHRawVoltage();
    phNeutralVoltage = v;
    savePHCalibration();
    Serial.printf("[PH] Calibrated pH 7.0 → neutral voltage = %.3f V\n", v);
}

void calibratePH4() {
    float v = readPHRawVoltage();
    phSlope = fabs((phNeutralVoltage - v) / 3.0f);
    if (phSlope < 0.01f) phSlope = 0.18f;
    savePHCalibration();
    Serial.printf("[PH] Calibrated pH 4.0 → slope = %.4f V/pH (neutral=%.3fV, pH4=%.3fV)\n",
        phSlope, phNeutralVoltage, v);
}

void loadPHCalibration() {
    prefs.begin("ph", false);
    phNeutralVoltage = prefs.getFloat("neutralV", 2.5f);
    phSlope = prefs.getFloat("slope", 0.18f);
    prefs.end();
    Serial.printf("[PH] Loaded: neutral=%.3fV, slope=%.4f V/pH\n", phNeutralVoltage, phSlope);
}

void savePHCalibration() {
    prefs.begin("ph", false);
    prefs.putFloat("neutralV", phNeutralVoltage);
    prefs.putFloat("slope", phSlope);
    prefs.end();
    Serial.println("[PH] Calibration saved to NVS");
}

// =============================================================================
// 686 / 401 CALIBRATION — uses local Preferences, namespace "phcal"
// =============================================================================

static Preferences phcalPrefs;
static const char* PHCAL_NS = "phcal";

static float phcalV686 = 0.0f;
static float phcalV401 = 0.0f;
static float phcalSlope = 0.18f;
static float phcalNeutralV = 0.0f;
static bool phcalCalibrated = false;

static void loadPHCALFromNVS() {
    phcalPrefs.begin(PHCAL_NS, true);
    phcalV686 = phcalPrefs.getFloat("v686", 0.0f);
    phcalV401 = phcalPrefs.getFloat("v401", 0.0f);
    phcalSlope = phcalPrefs.getFloat("slope", 0.18f);
    phcalNeutralV = phcalPrefs.getFloat("neutralV", 0.0f);
    phcalCalibrated = phcalPrefs.getBool("cal", false);
    phcalPrefs.end();
}

static void savePHCALToNVS() {
    phcalPrefs.begin(PHCAL_NS, false);
    phcalPrefs.putFloat("v686", phcalV686);
    phcalPrefs.putFloat("v401", phcalV401);
    phcalPrefs.putFloat("slope", phcalSlope);
    phcalPrefs.putFloat("neutralV", phcalNeutralV);
    phcalPrefs.putBool("cal", phcalCalibrated);
    phcalPrefs.end();
}

// =============================================================================
// STABILITY DETECTION
// =============================================================================

#define STABLE_SAMPLES   15
#define STABLE_THRESH_V  0.008f
#define DIP_THRESHOLD    50

static bool waitForDip(unsigned long timeoutMs) {
    int baseline = analogRead(PH_PIN);
    unsigned long start = millis();
    Serial.println("  Watching for dip (ADC jump > 50)...");
    delay(2000);

    while (millis() - start < timeoutMs) {
        int adc = analogRead(PH_PIN);
        if (abs(adc - baseline) > DIP_THRESHOLD) {
            Serial.printf("  ⏺ Dip detected! (ADC %d → %d)\n", baseline, adc);
            delay(500);
            return true;
        }
        if ((millis() - start) % 1000 < 20) {
            Serial.printf("  Waiting... ADC=%d | ", adc);
        }
        delay(100);
    }
    Serial.println("  No dip detected, proceeding from current reading...");
    return false;
}

static float monitorUntilSave(unsigned long timeoutMs) {
    float ring[STABLE_SAMPLES];
    int ri = 0, rc = 0;
    unsigned long start = millis();
    unsigned long lastPrint = 0;
    bool wasStable = false;

    Serial.println("  Monitoring — type 'save' when stable, 'abort' to cancel");

    while (millis() - start < timeoutMs) {
        if (Serial.available()) {
            String line = Serial.readStringUntil('\n');
            line.trim();
            if (line == "save") {
                float v = readPHRawVoltage();
                Serial.printf("  → Manually saved: V=%.3f V\n", v);
                return v;
            }
            if (line == "abort") {
                Serial.println("  ⛔ Aborted by user");
                return -1;
            }
        }

        float v = readPHRawVoltage();
        ring[ri++] = v;
        if (ri >= STABLE_SAMPLES) ri = 0;
        if (rc < STABLE_SAMPLES) rc++;

        float drift = 0;
        if (rc >= 3) {
            float vmin = v, vmax = v;
            for (int i = 0; i < rc; i++) {
                if (ring[i] < vmin) vmin = ring[i];
                if (ring[i] > vmax) vmax = ring[i];
            }
            drift = vmax - vmin;
        }

        if (millis() - lastPrint >= 500) {
            lastPrint = millis();
            bool stable = (drift <= STABLE_THRESH_V && rc >= STABLE_SAMPLES);
            if (stable && !wasStable) {
                Serial.printf("  V=%.3f drift=%.0fmV ✅ STABLE — type 'save' to record\n", v, drift * 1000);
            } else if (stable) {
                Serial.printf("  V=%.3f drift=%.0fmV ✅ (still stable)\n", v, drift * 1000);
            } else {
                Serial.printf("  V=%.3f drift=%.0fmV ⏳\n", v, drift * 1000);
            }
            wasStable = stable;
        }
        delay(50);
    }

    float v = readPHRawVoltage();
    Serial.printf("  ⚠ Timeout — auto-using V=%.3f\n", v);
    return v;
}

// =============================================================================
// 686 / 401 COMMANDS
// =============================================================================

void calibratePH686() {
    loadPHCALFromNVS();
    Serial.println("\n=== pH 6.86 Calibration ===");
    Serial.println("  Dip probe in pH 6.86 buffer now...");
    waitForDip(300000);
    float v = monitorUntilSave(300000);
    if (v < 0) { Serial.println("  Calibration cancelled."); return; }

    phcalV686 = v;

    // If V401 already exists, compute slope now
    if (phcalV401 > 0.0f) {
        float m = (phcalV686 - phcalV401) / (6.86f - 4.01f);
        phcalSlope = fabs(m);
        if (phcalSlope < 0.001f || phcalSlope > 1.0f) phcalSlope = 0.18f;
        phcalNeutralV = phcalV686 + m * (7.0f - 6.86f);
        phcalCalibrated = true;
    }

    savePHCALToNVS();
    Serial.printf("  → V686 = %.3f V saved\n", phcalV686);
    if (phcalV401 > 0.0f) {
        Serial.printf("  → Slope = %.4f V/pH, NeutralV (pH7) = %.3f V\n", phcalSlope, phcalNeutralV);
        Serial.println("  ✅ Calibration COMPLETE!");
    } else {
        Serial.println("  Status: 1/2 (need pH 4.01)");
    }
}

void calibratePH401() {
    loadPHCALFromNVS();
    Serial.println("\n=== pH 4.01 Calibration ===");
    Serial.println("  Rinse probe, then dip in pH 4.01 buffer now...");
    waitForDip(300000);
    float v = monitorUntilSave(300000);
    if (v < 0) { Serial.println("  Calibration cancelled."); return; }

    phcalV401 = v;

    if (phcalV686 > 0.0f) {
        float m = (phcalV686 - phcalV401) / (6.86f - 4.01f);
        phcalSlope = fabs(m);
        if (phcalSlope < 0.001f || phcalSlope > 1.0f) phcalSlope = 0.18f;
        phcalNeutralV = phcalV686 + m * (7.0f - 6.86f);
        phcalCalibrated = true;
    }

    savePHCALToNVS();
    Serial.printf("  → V401 = %.3f V saved\n", phcalV401);
    if (phcalV686 > 0.0f) {
        Serial.printf("  → Slope = %.4f V/pH, NeutralV (pH7) = %.3f V\n", phcalSlope, phcalNeutralV);
        Serial.println("  ✅ Calibration COMPLETE!");
    } else {
        Serial.println("  Status: 1/2 (need pH 6.86)");
    }
}

void readPHVoltage() {
    loadPHCALFromNVS();
    float v = readPHRawVoltage();
    float ph = readPH();
    Serial.printf("[PH] Raw V=%.3f  pH=%.2f\n", v, ph);
}

void showPHCalibration() {
    loadPHCALFromNVS();

    Serial.println("\n--- pH Calibration ---");

    // Existing phcal7/phcal4
    Serial.printf("  [phcal7/4]  neutralV=%.3fV  slope=%.4f V/pH\n", phNeutralVoltage, phSlope);

    // 686/401
    Serial.printf("  [686/401]   V686=%.3fV  V401=%.3fV\n", phcalV686, phcalV401);
    if (phcalV686 > 0.0f && phcalV401 > 0.0f) {
        Serial.printf("             Slope=%.4f V/pH  NeutralV=%.3fV\n", phcalSlope, phcalNeutralV);
    }
    Serial.printf("  Calibrated: %s\n", phcalCalibrated ? "YES" : "NO");

    if (phcalCalibrated) {
        Serial.printf("  Formula: pH = 7.0 + (%.3f - V) / %.4f\n", phcalNeutralV, phcalSlope);
    } else if (phSlope > 0.01f) {
        Serial.printf("  Formula: pH = 7.0 + (%.3f - V) / %.4f\n", phNeutralVoltage, phSlope);
    }
    Serial.println("----------------------\n");
}

void resetPHCalibration() {
    Preferences tmp;
    tmp.begin("phcal", false);
    tmp.clear();
    tmp.end();
    phcalV686 = 0; phcalV401 = 0;
    phcalSlope = 0.18f; phcalNeutralV = 0; phcalCalibrated = false;
    Serial.println("[PH] Calibration (686/401) reset");
}