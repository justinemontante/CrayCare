#include "do_ctrl.h"
#include <Preferences.h>

extern Preferences prefs;

const int DO_PIN = 36; // SVP, ADC1_CH0

#define DO_DIVIDER_RATIO 0.5f
static const size_t DO_BUF_SIZE = 10;
static float doBuf[DO_BUF_SIZE];
static size_t doIdx = 0;
static bool doBufFilled = false;

float DOValue = 5.0f;
float doAirVoltage = 2.0f;

void initDOSensor() {
    pinMode(DO_PIN, INPUT);
    loadDOCalibration();
}

float saturationDO(float tempC);

float readDORaw() {
    uint32_t sum = 0;
    for (size_t i = 0; i < 10; i++) {
        sum += analogRead(DO_PIN);
        delay(1);
    }
    return (sum / 10.0f) * (3.3f / 4095.0f) / DO_DIVIDER_RATIO;
}

static float readDORawVoltage() {
    uint32_t sum = 0;
    for (size_t i = 0; i < 10; i++) {
        sum += analogRead(DO_PIN);
        delay(1);
    }
    return (sum / 10.0f) * (3.3f / 4095.0f) / DO_DIVIDER_RATIO;
}

float saturationDO(float tempC) {
    return 14.65f - 0.41022f * tempC + 0.007991f * tempC * tempC - 0.000077774f * tempC * tempC * tempC;
}

float readDO(float temperatureC) {
    float v = readDORawVoltage();
    doBuf[doIdx++] = v;
    if (doIdx >= DO_BUF_SIZE) { doIdx = 0; doBufFilled = true; }
    size_t count = doBufFilled ? DO_BUF_SIZE : doIdx;
    float avg = 0;
    for (size_t i = 0; i < count; i++) avg += doBuf[i];
    avg /= count;
    if (doAirVoltage > 0.1f) {
        DOValue = (avg / doAirVoltage) * saturationDO(temperatureC);
    } else {
        DOValue = avg * 5.0f;
    }
    if (DOValue < 0.0f) DOValue = 0.0f;
    if (DOValue > 20.0f) DOValue = 20.0f;
    return DOValue;
}

void calibrateDOInAir() {
    float v = readDORawVoltage();
    doAirVoltage = v;
    saveDOCalibration();
    Serial.printf("[DO] Calibrated in air → air voltage = %.3f V\n", v);
}

void loadDOCalibration() {
    prefs.begin("do", false);
    doAirVoltage = prefs.getFloat("airV", 2.0f);
    prefs.end();
    Serial.printf("[DO] Loaded: airVoltage=%.3fV\n", doAirVoltage);
}

void saveDOCalibration() {
    prefs.begin("do", false);
    prefs.putFloat("airV", doAirVoltage);
    prefs.end();
    Serial.println("[DO] Calibration saved to NVS");
}
