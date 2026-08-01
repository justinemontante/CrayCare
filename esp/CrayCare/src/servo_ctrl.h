#pragma once

#include <Arduino.h>

// LEDC (PWM) configuration for ESP32 – using the LED‑C peripheral
extern const int SERVO_PIN;      // GPIO (e.g., 13) wired to LED‑C channel
extern const int SERVO_CHANNEL; // LEDC channel (0‑15)
extern const int SERVO_FREQ;    // PWM frequency (Hz), 50 Hz for typical servo timing
extern const int SERVO_RESOLUTION; // bits of resolution (e.g., 16)

// Runtime configuration (in‑RAM only)
extern uint32_t servoPauseMs;   // How long the servo stays open (ms)
extern uint32_t servoCycleMs;   // Full period between cycles (ms). 0 = use pause + fixed close time.
extern int servoOpenAngle;      // Servo angle for open position (0-180)
extern int servoCloseAngle;     // Servo angle for close position (0-180)

// Calibration table (stored in NVS under "servo" namespace)
#define CAL_MAX_RECORDS 16
struct CalRecord {
    double grams;      // target dispense amount
    int angle;         // servo open angle (0-180)
    uint32_t pauseMs;  // servo open duration (ms)
};
extern CalRecord calTable[CAL_MAX_RECORDS];
extern int calCount;

void initServo();
void setServoAngle(int angle);
void executeServoCycle();
void executeServoCycleFromTable(double grams);
void saveServoPause(uint32_t v);
void saveServoAngles(int openAng, int closeAng);
void loadCalTable();
void saveCalTable();
