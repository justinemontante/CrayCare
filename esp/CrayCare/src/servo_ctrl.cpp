#include "servo_ctrl.h"

// ----- Pin / PWM configuration -----
const int SERVO_PIN = 13;        // GPIO13 (chosen by the original sketch)
const int SERVO_CHANNEL = 0;     // First LEDC channel
const int SERVO_FREQ = 50;       // 50 Hz – typical servo frequency
const int SERVO_RESOLUTION = 16; // 16‑bit resolution gives fine granularity

// ----- Runtime configuration (RAM only) -----
uint32_t servoPauseMs = 2000; // default 2 s open pause
uint32_t servoCycleMs = 0;     // 0 = use pause + fixed close duration (20 s total default)

static const int SERVO_MIN_US = 500; // 0° pulse width in µs
static const int SERVO_MAX_US = 2500; // 180° pulse width in µs

void initServo() {
    // Configure LEDC channel for the servo pin
    ledcSetup(SERVO_CHANNEL, SERVO_FREQ, SERVO_RESOLUTION);
    ledcAttachPin(SERVO_PIN, SERVO_CHANNEL);
    // Start at closed position (0°)
    setServoAngle(0);
    Serial.println("[SERVO] Initialized on GPIO" + String(SERVO_PIN));
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
    // Open (90°)
    setServoAngle(180);
    Serial.println("[SERVO] Open (90°) – waiting pause");
    delay(servoPauseMs);
    // Close (0°)
    setServoAngle(0);
    Serial.println("[SERVO] Closed (0°)");
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
