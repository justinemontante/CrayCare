#include "common.h"
#include "servo_ctrl.h"

// Simple wrapper that runs only the servo feeding logic.

void setup() {
    Serial.begin(115200);
    Serial.println("=== CrayCare – Servo‑Only Firmware ===");
    if (!ensureFirebaseReady()) {
        Serial.println("[WARN] Firebase not ready – servo will run anyway");
    }
    initServo();
}

void loop() {
    // Execute a single feeding cycle, then wait the configured interval.
    executeServoCycle();
    // If a full cycle interval is set, that delay is handled inside executeServoCycle.
    // Otherwise we simply delay a default of 20 s between cycles.
    if (servoCycleMs == 0) {
        delay(20000);
    }
}
