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

void initServo();
void setServoAngle(int angle); // 0‑180 degrees
void executeServoCycle(); // open → pause → close (once)
