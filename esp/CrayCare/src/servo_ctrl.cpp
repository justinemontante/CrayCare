#include "servo_ctrl.h"
#include <Preferences.h>

// ----- Pin / PWM configuration -----
const int SERVO_PIN = 13;
const int SERVO_CHANNEL = 0;
const int SERVO_FREQ = 50;
const int SERVO_RESOLUTION = 16;

// ----- Runtime configuration -----
uint32_t servoPauseMs = 2000;
uint32_t servoCycleMs = 0;
int servoOpenAngle = 180;   // Angle for open position
int servoCloseAngle = 0;    // Angle for close position

// ----- Calibration table -----
CalRecord calTable[CAL_MAX_RECORDS];
int calCount = 0;

static Preferences servoPrefs;
static const char* SERVO_NS = "servo";

static const int SERVO_MIN_US = 500;
static const int SERVO_MAX_US = 2500;

void initServo() {
    servoPrefs.begin(SERVO_NS, false);
    servoPauseMs = servoPrefs.getUInt("pause", 2000);
    servoOpenAngle = servoPrefs.getInt("openAng", 180);
    servoCloseAngle = servoPrefs.getInt("closeAng", 0);
    servoPrefs.end();
    Serial.printf("[SERVO] Pause: %ums, Open: %d°, Close: %d°\n",
        servoPauseMs, servoOpenAngle, servoCloseAngle);

    loadCalTable();
    Serial.printf("[SERVO] Calibration table: %d records\n", calCount);

    ledcSetup(SERVO_CHANNEL, SERVO_FREQ, SERVO_RESOLUTION);
    ledcAttachPin(SERVO_PIN, SERVO_CHANNEL);
    setServoAngle(servoCloseAngle);
    Serial.printf("[SERVO] Initialized on GPIO%d\n", SERVO_PIN);
}

void saveServoPause(uint32_t v) {
    servoPrefs.begin(SERVO_NS, false);
    servoPrefs.putUInt("pause", v);
    servoPrefs.end();
    Serial.printf("[SERVO] Pause saved: %u ms\n", v);
}

void saveServoAngles(int openAng, int closeAng) {
    servoOpenAngle = openAng;
    servoCloseAngle = closeAng;
    servoPrefs.begin(SERVO_NS, false);
    servoPrefs.putInt("openAng", servoOpenAngle);
    servoPrefs.putInt("closeAng", servoCloseAngle);
    servoPrefs.end();
    Serial.printf("[SERVO] Angles saved: Open=%d°, Close=%d°\n", servoOpenAngle, servoCloseAngle);
}

static int usFromAngle(int angle) {
    // Linear mapping between min and max microseconds
    return map(angle, 0, 180, SERVO_MIN_US, SERVO_MAX_US);
}

void setServoAngle(int angle) {
    int us = usFromAngle(angle);
    // Convert microseconds to duty cycle based on resolution
    uint32_t period_us = 1000000UL / SERVO_FREQ; // period in µs (e.g., 20 000 µs for 50 Hz)
    uint32_t duty = (uint32_t)(( (uint64_t)us * (1UL << SERVO_RESOLUTION) ) / period_us);
    ledcWrite(SERVO_CHANNEL, duty);
    Serial.printf("[SERVO] Angle %d° (pulse %dus) → duty %u\n", angle, us, duty);
}

void executeServoCycle() {
    setServoAngle(servoOpenAngle);
    Serial.printf("[SERVO] Open (%d°) – waiting pause\n", servoOpenAngle);
    delay(servoPauseMs);
    setServoAngle(servoCloseAngle);
    Serial.printf("[SERVO] Closed (%d°)\n", servoCloseAngle);
    // If a full cycle interval is defined, wait the remaining time.
    if (servoCycleMs > 0) {
        uint32_t elapsed = servoPauseMs; // open + pause (close is immediate)
        if (servoCycleMs > elapsed) {
            uint32_t remaining = servoCycleMs - elapsed;
            Serial.printf("[SERVO] Waiting remaining %ums for next cycle\n", remaining);
            delay(remaining);
        }
    }
    Serial.println("[SERVO] Feeding cycle complete");
}

// ----- Calibration table -----

void loadCalTable() {
    servoPrefs.begin(SERVO_NS, true);
    calCount = servoPrefs.getInt("calCount", 0);
    if (calCount > CAL_MAX_RECORDS) calCount = CAL_MAX_RECORDS;
    for (int i = 0; i < calCount; i++) {
        String gk = "cr_g_" + String(i);
        String ak = "cr_a_" + String(i);
        String pk = "cr_p_" + String(i);
        calTable[i].grams = servoPrefs.getFloat(gk.c_str(), 0.0f);
        calTable[i].angle = servoPrefs.getInt(ak.c_str(), 0);
        calTable[i].pauseMs = servoPrefs.getUInt(pk.c_str(), 0);
    }
    servoPrefs.end();
}

void saveCalTable() {
    servoPrefs.begin(SERVO_NS, false);
    servoPrefs.putInt("calCount", calCount);
    for (int i = 0; i < calCount; i++) {
        String gk = "cr_g_" + String(i);
        String ak = "cr_a_" + String(i);
        String pk = "cr_p_" + String(i);
        servoPrefs.putFloat(gk.c_str(), (float)calTable[i].grams);
        servoPrefs.putInt(ak.c_str(), calTable[i].angle);
        servoPrefs.putUInt(pk.c_str(), calTable[i].pauseMs);
    }
    servoPrefs.end();
}

void executeServoCycleFromTable(double grams) {
    if (calCount == 0 || grams <= 0) {
        Serial.println("[CAL] No calibration table or invalid grams — using default cycle");
        executeServoCycle();
        return;
    }

    int bestIdx = 0;
    double bestDiff = fabs(grams - calTable[0].grams);
    for (int i = 1; i < calCount; i++) {
        double diff = fabs(grams - calTable[i].grams);
        if (diff < bestDiff) {
            bestDiff = diff;
            bestIdx = i;
        }
    }

    int angle = calTable[bestIdx].angle;
    uint32_t pause = calTable[bestIdx].pauseMs;

    setServoAngle(angle);
    Serial.printf("[CAL] %.1fg → nearest: %.1fg → angle=%d° pause=%ums\n",
        grams, calTable[bestIdx].grams, angle, pause);
    delay(pause);
    setServoAngle(servoCloseAngle);

    if (servoCycleMs > 0) {
        uint32_t elapsed = pause;
        if (servoCycleMs > elapsed) {
            uint32_t remaining = servoCycleMs - elapsed;
            Serial.printf("[SERVO] Waiting remaining %ums for next cycle\n", remaining);
            delay(remaining);
        }
    }
    Serial.println("[CAL] Feeding cycle complete");
}
