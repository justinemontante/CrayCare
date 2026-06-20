#include <Arduino.h>
#include <Preferences.h>

// =============================================================================
// pH CALIBRATOR — Standalone
// Buffers: pH 6.86 & pH 4.01 @ 25°C
// Hardware: 10k+10k voltage divider (ratio 0.5), GPIO 35
// =============================================================================

#define PH_PIN 35
#define PH_DIVIDER_RATIO 0.5f

// NVS
static Preferences prefs;
static const char* NVS_NS = "phcal";

// Calibration values
static float v686 = 0.0f;
static float v401 = 0.0f;
static float neutralV = 0.0f;
static float slope = 0.18f;
static bool calibrated = false;

// Moving average filter
#define BUF_SIZE 20
static float buf[BUF_SIZE];
static int bufIdx = 0;
static int bufCount = 0;

// Stability detection
#define STABLE_SAMPLES   15
#define STABLE_WINDOW_MS 3000
#define STABLE_THRESH_V  0.008f
#define DIP_THRESHOLD    50

// =============================================================================
// HELPERS
// =============================================================================

static float readRawVoltage() {
    uint32_t sum = 0;
    for (int i = 0; i < 10; i++) {
        sum += analogRead(PH_PIN);
        delay(1);
    }
    return (sum / 10.0f) * (3.3f / 4095.0f) / PH_DIVIDER_RATIO;
}

static float readFiltered() {
    float v = readRawVoltage();
    buf[bufIdx++] = v;
    if (bufIdx >= BUF_SIZE) bufIdx = 0;
    if (bufCount < BUF_SIZE) bufCount++;
    float sum = 0;
    for (int i = 0; i < bufCount; i++) sum += buf[i];
    return sum / bufCount;
}

static float calcPH(float v) {
    if (!calibrated || slope < 0.001f) return -1;
    float ph = 7.0f + (neutralV - v) / slope;
    if (ph < 0) ph = 0;
    if (ph > 14) ph = 14;
    return ph;
}

// =============================================================================
// NVS
// =============================================================================

static void loadCal() {
    prefs.begin(NVS_NS, false);
    v686 = prefs.getFloat("v686", 0.0f);
    v401 = prefs.getFloat("v401", 0.0f);
    slope = prefs.getFloat("slope", 0.18f);
    neutralV = prefs.getFloat("neutralV", 0.0f);
    calibrated = prefs.getBool("cal", false);
    prefs.end();
}

static void saveCal() {
    prefs.begin(NVS_NS, false);
    prefs.putFloat("v686", v686);
    prefs.putFloat("v401", v401);
    prefs.putFloat("slope", slope);
    prefs.putFloat("neutralV", neutralV);
    prefs.putBool("cal", calibrated);
    prefs.end();
}

// =============================================================================
// AUTO-DETECT + MANUAL SAVE
// =============================================================================

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
                float v = readFiltered();
                Serial.printf("  → Manually saved: V=%.3f V\n", v);
                return v;
            }
            if (line == "abort") {
                Serial.println("  ⛔ Aborted by user");
                return -1;
            }
        }

        float v = readFiltered();
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
            char tag[6] = "⏳";
            if (stable && !wasStable) {
                strcpy(tag, "✅");
                Serial.printf("  V=%.3f drift=%.0fmV %s STABLE — type 'save' to record\n", v, drift * 1000, tag);
            } else if (stable) {
                strcpy(tag, "✅");
                Serial.printf("  V=%.3f drift=%.0fmV %s (still stable)\n", v, drift * 1000, tag);
            } else {
                Serial.printf("  V=%.3f drift=%.0fmV %s\n", v, drift * 1000, tag);
            }
            wasStable = stable;
        }
        delay(50);
    }

    float v = readFiltered();
    Serial.printf("  ⚠ Timeout (%lums) — auto-using V=%.3f\n", timeoutMs, v);
    return v;
}

static float waitDipAndMonitorUntilSave(unsigned long timeoutMs) {
    waitForDip(timeoutMs);
    return monitorUntilSave(timeoutMs);
}

// =============================================================================
// CALIBRATION ACTIONS
// =============================================================================

static void showCal();

static void calibrate686() {
    Serial.println("\n=== pH 6.86 Calibration ===");
    Serial.println("  Dip probe in pH 6.86 buffer now...");
    float v = waitDipAndMonitorUntilSave(300000);
    if (v < 0) { Serial.println("  Calibration cancelled."); return; }
    v686 = v;

    if (v401 > 0) {
        float m = (v686 - v401) / (6.86f - 4.01f);
        slope = fabs(m);
        if (slope < 0.001f || slope > 1.0f) slope = 0.18f;
        neutralV = v686 + m * (7.0f - 6.86f);
        calibrated = true;
    }

    saveCal();
    Serial.println("  → V686 = " + String(v686, 3) + " V saved");
    if (v401 > 0) {
        Serial.printf("  → Slope = %.4f V/pH, NeutralV (pH7) = %.3f V\n", slope, neutralV);
        Serial.println("  ✅ Calibration COMPLETE!");
    } else {
        Serial.println("  Status: 1/2 (need pH 4.01)");
    }
    showCal();
}

static void calibrate401() {
    Serial.println("\n=== pH 4.01 Calibration ===");
    Serial.println("  Rinse probe, then dip in pH 4.01 buffer now...");
    float v = waitDipAndMonitorUntilSave(300000);
    if (v < 0) { Serial.println("  Calibration cancelled."); return; }
    v401 = v;

    if (v686 > 0) {
        float m = (v686 - v401) / (6.86f - 4.01f);
        slope = fabs(m);
        if (slope < 0.001f || slope > 1.0f) slope = 0.18f;
        neutralV = v686 + m * (7.0f - 6.86f);
        calibrated = true;
    }

    saveCal();
    Serial.println("  → V401 = " + String(v401, 3) + " V saved");
    if (v686 > 0) {
        Serial.printf("  → Slope = %.4f V/pH, NeutralV (pH7) = %.3f V\n", slope, neutralV);
        Serial.println("  ✅ Calibration COMPLETE!");
    } else {
        Serial.println("  Status: 1/2 (need pH 6.86)");
    }
    showCal();
}

static void runVerify() {
    if (!calibrated) {
        Serial.println("⚠ Calibrate first (type 686 then 401)");
        return;
    }

    Serial.println("\n=== Verify pH 6.86 ===");
    Serial.println("  Dip probe in pH 6.86 buffer, type 'save' when stable...");
    float v1 = waitDipAndMonitorUntilSave(300000);
    if (v1 < 0) { Serial.println("  Verify cancelled."); return; }
    float ph1 = calcPH(v1);
    Serial.printf("  V=%.3f  pH=%.2f  (expected 6.86, error=%.2f)\n", v1, ph1, ph1 - 6.86);

    Serial.println("\n  Press any key to continue to pH 4.01...");
    while (!Serial.available()) { delay(50); }
    while (Serial.available()) Serial.read();

    Serial.println("\n=== Verify pH 4.01 ===");
    Serial.println("  Rinse probe, then dip in pH 4.01 buffer, type 'save' when stable...");
    float v2 = waitDipAndMonitorUntilSave(300000);
    float ph2 = calcPH(v2);
    Serial.printf("  V=%.3f  pH=%.2f  (expected 4.01, error=%.2f)\n", v2, ph2, ph2 - 4.01);

    Serial.println("\n=== Verification Results ===");
    Serial.printf("  pH 6.86: measured=%.2f  error=%.2f  %s\n",
        ph1, ph1 - 6.86, fabs(ph1 - 6.86) < 0.15 ? "✅ PASS" : "⚠ FAIL");
    Serial.printf("  pH 4.01: measured=%.2f  error=%.2f  %s\n",
        ph2, ph2 - 4.01, fabs(ph2 - 4.01) < 0.15 ? "✅ PASS" : "⚠ FAIL");
}

static void showCal() {
    Serial.println("\n--- pH Calibration Status ---");
    Serial.printf("  V686 (pH 6.86): %.3f V\n", v686);
    Serial.printf("  V401 (pH 4.01): %.3f V\n", v401);
    if (v686 > 0 && v401 > 0) {
        Serial.printf("  Slope: %.4f V/pH\n", slope);
        Serial.printf("  NeutralV (pH7): %.3f V\n", neutralV);
    }
    Serial.printf("  Calibrated: %s\n", calibrated ? "YES" : "NO");
    if (calibrated) {
        Serial.printf("  Formula: pH = 7.0 + (%.3f - V) / %.4f\n", neutralV, slope);
    }
    Serial.println("-----------------------------\n");
}

static void resetCal() {
    v686 = 0; v401 = 0;
    slope = 0.18f; neutralV = 0; calibrated = false;
    saveCal();
    Serial.println("[CAL] Reset to defaults");
}

static void printHelp() {
    Serial.println();
    Serial.println("========== pH Sensor Calibrator ==========");
    Serial.println("  Buffer: pH 6.86 & pH 4.01 @ 25°C");
    Serial.println("  Divider: 10k+10k (ratio 0.5), GPIO 35");
    Serial.println("------------------------------------------");
    Serial.println("  686     Auto-calibrate at pH 6.86");
    Serial.println("  401     Auto-calibrate at pH 4.01");
    Serial.println("  read    One-shot pH reading");
    Serial.println("  raw     Toggle live voltage stream");
    Serial.println("  verify  Test calibration on both buffers");
    Serial.println("  show    Display saved calibration values");
    Serial.println("  reset   Reset calibration to defaults");
    Serial.println("  help/?  This list");
    Serial.println("=========================================");
    Serial.println();
}

// =============================================================================
// SETUP / LOOP
// =============================================================================

void setup() {
    Serial.begin(115200);
    delay(1500);

    Serial.println();
    Serial.println("======================================");
    Serial.println("  pH Sensor Calibrator");
    Serial.println("  Buffers: pH 6.86 & pH 4.01 @ 25°C");
    Serial.println("  Divider: 10k+10k (ratio 0.5)");
    Serial.println("======================================");

    pinMode(PH_PIN, INPUT);
    analogSetAttenuation(ADC_11db);
    analogSetWidth(12);
    analogSetPinAttenuation(PH_PIN, ADC_11db);

    loadCal();
    showCal();
    printHelp();
}

void loop() {
    static bool rawMode = false;
    static unsigned long lastRaw = 0;

    if (Serial.available()) {
        String line = Serial.readStringUntil('\n');
        line.trim();

        if (line == "686") {
            calibrate686();
        } else if (line == "401") {
            calibrate401();
        } else if (line == "read") {
            float v = readFiltered();
            float ph = calcPH(v);
            Serial.printf("V=%.3f  pH=", v);
            if (ph < 0) Serial.println("-- (not calibrated)");
            else Serial.printf("%.2f\n", ph);
        } else if (line == "raw") {
            rawMode = !rawMode;
            Serial.printf("Raw mode: %s\n", rawMode ? "ON" : "OFF");
        } else if (line == "verify") {
            runVerify();
        } else if (line == "show") {
            showCal();
        } else if (line == "reset") {
            resetCal();
        } else if (line == "help" || line == "?") {
            printHelp();
        } else if (line.length() > 0) {
            Serial.println("Unknown — type 'help'");
        }
    }

    if (rawMode) {
        unsigned long now = millis();
        if (now - lastRaw >= 500) {
            lastRaw = now;
            float v = readFiltered();
            int adc = analogRead(PH_PIN);
            float ph = calcPH(v);
            Serial.printf("ADC=%4d  V=%.3f  pH=", adc, v);
            if (ph < 0) Serial.println("--");
            else Serial.printf("%.2f\n", ph);
        }
    }
}
