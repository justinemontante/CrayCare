#include "ph_ctrl.h"
#include <Preferences.h>

extern Preferences prefs;

const int PH_PIN = 35;

// Voltage divider: adjust based on your resistors
// 10k+10k → 0.5, 2k+5.1k → 0.718
#define PH_DIVIDER_RATIO 0.5f

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

static float readPHRawVoltage() {
    uint32_t sum = 0;
    for (size_t i = 0; i < 10; i++) {
        sum += analogRead(PH_PIN);
        delay(1);
    }
    return (sum / 10.0f) * (3.3f / 4095.0f) / PH_DIVIDER_RATIO;
}

float readPH() {
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

void calibratePH7() {
    float v = readPHRawVoltage();
    phNeutralVoltage = v;
    savePHCalibration();
    Serial.printf("[PH] Calibrated pH 7.0 → neutral voltage = %.3f V\n", v);
}

void calibratePH4() {
    float v = readPHRawVoltage();
    // At pH 4.0: slope = (neutralV - V_at_pH4) / (7.0 - 4.0)
    phSlope = (phNeutralVoltage - v) / 3.0f;
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
