/*
 * CrayCare standalone pH calibration utility
 * Board: ESP32 Dev Module / ESP32-S
 * Sensor: DFRobot Gravity Analog pH SEN0161 V1.1
 *
 * Offline only: no Wi-Fi, Firebase, LCD, or other sensors.
 * Upload with: pio run -e esp32dev_ph_calibrator -t upload
 *
 * Wiring for this standalone test:
 *   pH board VCC -> regulated 5V
 *   pH board GND -> ESP32 GND (common ground)
 *   pH board A/O -> ESP32 GPIO35, only if A/O is <= 3.3V
 * GPIO35 is not 5V tolerant. Check A/O to ESP32 GND with a meter first.
 *
 * Calibration points are saved in the same NVS namespace/keys consumed by
 * CrayCare main firmware: sensorcal / phV4, phV7, phV9, phSlope,
 * phIntercept, phFitN, phPair, and buffer reference keys.
 * Reflashing the normal firmware does not erase these NVS values.
 *
 * Serial Monitor: 115200 baud, line ending = Newline.
 *   phread      read ADC voltage; show pH if a fit exists
 *   phcal4      capture pH 4.01 buffer point
 *   phcal9 9.18 capture pH 9.18 buffer point
 *   phfit       fit pH 4.01 and 9.18 points and save the formula
 *   phshow      show saved buffer points and fit
 *   raw on      stream raw voltage and stability status
 *   raw off     stop live voltage stream
 *   phdisplay   stream calibrated pH values only
 *   phdisplay off stop calibrated pH display
 *   help        list commands
 */

#include <Arduino.h>
#include <Preferences.h>
#include <math.h>

static constexpr uint8_t PH_PIN = 35;
static constexpr uint16_t SAMPLE_COUNT = 120;
static constexpr uint16_t SAMPLE_DELAY_MS = 20;
static constexpr float MAX_ADC_V = 3.25f;  // Match main firmware's accepted pH range.
static constexpr float MAX_CAPTURE_SPREAD_V = 0.080f;
static constexpr float WARN_CAPTURE_SPREAD_V = 0.010f;
static constexpr float MIN_TWO_POINT_SPAN_V = 0.001f;
static constexpr uint8_t RAW_BLOCK_SAMPLE_COUNT = 8;
static constexpr uint8_t STABILITY_WINDOW_BLOCKS = 12;
static constexpr uint16_t RAW_BLOCK_SAMPLE_DELAY_MS = 10;
static constexpr uint32_t RAW_PRINT_INTERVAL_MS = 200;
static constexpr uint32_t PH_DISPLAY_INTERVAL_MS = 500;
static constexpr float LIVE_STABLE_SPREAD_V = 0.010f;

static Preferences prefs;
static float activeSlope = NAN;
static float activeIntercept = NAN;
static int activeFitCount = 2;
static bool rawStreamEnabled = false;
static bool phDisplayEnabled = false;
static float rawVoltageBlocks[STABILITY_WINDOW_BLOCKS] = {};
static uint8_t rawVoltageBlockCount = 0;
static uint8_t rawVoltageBlockNext = 0;
static uint32_t lastRawPrintMs = 0;
static uint32_t lastPHDisplayMs = 0;

struct ReadingWindow {
  float trimmedMeanV;
  float minV;
  float maxV;
  float spreadV;
};

static void sortSamples(uint16_t *samples, size_t count) {
  for (size_t i = 1; i < count; ++i) {
    const uint16_t value = samples[i];
    size_t j = i;
    while (j > 0 && samples[j - 1] > value) {
      samples[j] = samples[j - 1];
      --j;
    }
    samples[j] = value;
  }
}

static ReadingWindow readVoltageWindow() {
  uint16_t samples[SAMPLE_COUNT];
  uint16_t minMv = UINT16_MAX;
  uint16_t maxMv = 0;

  for (uint16_t i = 0; i < SAMPLE_COUNT; ++i) {
    const uint16_t mv = analogReadMilliVolts(PH_PIN);
    samples[i] = mv;
    if (mv < minMv) minMv = mv;
    if (mv > maxMv) maxMv = mv;
    delay(SAMPLE_DELAY_MS);
  }

  sortSamples(samples, SAMPLE_COUNT);
  // Trim the lowest/highest 10% to reject occasional ADC spikes.
  constexpr uint16_t TRIM = SAMPLE_COUNT / 10;
  uint32_t sumMv = 0;
  for (uint16_t i = TRIM; i < SAMPLE_COUNT - TRIM; ++i) sumMv += samples[i];

  ReadingWindow result;
  result.trimmedMeanV = (sumMv / float(SAMPLE_COUNT - 2 * TRIM)) / 1000.0f;
  result.minV = minMv / 1000.0f;
  result.maxV = maxMv / 1000.0f;
  result.spreadV = result.maxV - result.minV;
  return result;
}

static float readQuickVoltageBlock() {
  uint32_t sumMilliVolts = 0;
  for (uint8_t i = 0; i < RAW_BLOCK_SAMPLE_COUNT; ++i) {
    sumMilliVolts += analogReadMilliVolts(PH_PIN);
    delay(RAW_BLOCK_SAMPLE_DELAY_MS);
  }
  return (sumMilliVolts / float(RAW_BLOCK_SAMPLE_COUNT)) / 1000.0f;
}

static void resetRawStabilityWindow() {
  rawVoltageBlockCount = 0;
  rawVoltageBlockNext = 0;
  lastRawPrintMs = 0;
}

static void printRawBlock() {
  const float blockVoltage = readQuickVoltageBlock();
  rawVoltageBlocks[rawVoltageBlockNext] = blockVoltage;
  rawVoltageBlockNext = (rawVoltageBlockNext + 1) % STABILITY_WINDOW_BLOCKS;
  if (rawVoltageBlockCount < STABILITY_WINDOW_BLOCKS) ++rawVoltageBlockCount;

  float minV = rawVoltageBlocks[0];
  float maxV = rawVoltageBlocks[0];
  float sumV = 0.0f;
  for (uint8_t i = 0; i < rawVoltageBlockCount; ++i) {
    const float v = rawVoltageBlocks[i];
    if (v < minV) minV = v;
    if (v > maxV) maxV = v;
    sumV += v;
  }
  const float averageV = sumV / rawVoltageBlockCount;
  const float spreadMv = (maxV - minV) * 1000.0f;
  const bool stable = rawVoltageBlockCount == STABILITY_WINDOW_BLOCKS &&
      (maxV - minV) <= LIVE_STABLE_SPREAD_V;

  Serial.printf("[RAW] block=%.4fV avg=%.4fV min=%.4fV max=%.4fV spread=%.1fmV n=%u %s\n",
                blockVoltage, averageV, minV, maxV, spreadMv,
                rawVoltageBlockCount, stable ? "STABLE" : "SETTLING");
  if (averageV > MAX_ADC_V) {
    Serial.println(F("[SAFETY] A/O reading is above the ESP32 GPIO limit; disconnect GPIO35 and check signal voltage."));
  }
  lastRawPrintMs = millis();
}

static void printCalibratedPH() {
  const float blockVoltage = readQuickVoltageBlock();
  rawVoltageBlocks[rawVoltageBlockNext] = blockVoltage;
  rawVoltageBlockNext = (rawVoltageBlockNext + 1) % STABILITY_WINDOW_BLOCKS;
  if (rawVoltageBlockCount < STABILITY_WINDOW_BLOCKS) ++rawVoltageBlockCount;

  float sumV = 0.0f;
  for (uint8_t i = 0; i < rawVoltageBlockCount; ++i) sumV += rawVoltageBlocks[i];
  const float averageV = sumV / rawVoltageBlockCount;

  if (!isfinite(activeSlope) || !isfinite(activeIntercept)) {
    Serial.println(F("[PH] --"));
  } else if (averageV <= 0.05f || averageV > MAX_ADC_V) {
    Serial.println(F("[PH] --"));
  } else {
    const float ph = activeSlope * averageV + activeIntercept;
    if (ph >= 0.0f && ph <= 14.0f) Serial.printf("[PH] %.2f\n", ph);
    else Serial.println(F("[PH] --"));
  }
  lastPHDisplayMs = millis();
}

static bool beginCalNvs(bool readOnly) {
  if (!prefs.begin("sensorcal", readOnly)) {
    Serial.println(F("[NVS] Could not open the 'sensorcal' namespace."));
    return false;
  }
  return true;
}

static void showSavedCalibration() {
  if (!beginCalNvs(true)) return;
  const float v4 = prefs.getFloat("phV4", NAN);
  const float v686 = prefs.getFloat("phV7", NAN);
  const float v918 = prefs.getFloat("phV9", NAN);
  const float ref4 = prefs.getFloat("phV4Ref", 4.01f);
  const float ref686 = prefs.getFloat("phV7Ref", 7.00f);
  const float ref918 = prefs.getFloat("phV9Ref", 9.00f);
  activeSlope = prefs.getFloat("phSlope", NAN);
  activeIntercept = prefs.getFloat("phIntercept", NAN);
  activeFitCount = prefs.getInt("phFitN", 2);
  prefs.end();

  Serial.printf("[NVS] pH4 %.4fV (ref %.2f), legacy pH6.86 %.4fV (ref %.2f), pH9 %.4fV (ref %.2f)\n",
                v4, ref4, v686, ref686, v918, ref918);
  Serial.printf("[NVS] active fit=%d-point, slope=%.5f, intercept=%.5f\n",
                activeFitCount, activeSlope, activeIntercept);
  if (isfinite(v4) && isfinite(v686) && isfinite(v918) &&
      isfinite(activeSlope) && isfinite(activeIntercept)) {
    Serial.printf("[NVS] Fit predictions at pH4/pH9 captured voltages: %.2f / %.2f\n",
                  activeSlope * v4 + activeIntercept,
                  activeSlope * v918 + activeIntercept);
  }
}

static bool captureBuffer(const String &command) {
  const char *voltageKey = nullptr;
  const char *referenceKey = nullptr;
  float referencePH = 0.0f;

  if (command == "phcal4") {
    voltageKey = "phV4";
    referenceKey = "phV4Ref";
    referencePH = 4.01f;
  } else if (command == "phcal9" || command.startsWith("phcal9 ")) {
    voltageKey = "phV9";
    referenceKey = "phV9Ref";
    referencePH = 9.18f;
    if (command.startsWith("phcal9 ")) {
      String valueText = command.substring(7);
      valueText.trim();
      char *end = nullptr;
      const float enteredPH = strtof(valueText.c_str(), &end);
      if (end == valueText.c_str() || *end != '\0' || !isfinite(enteredPH) ||
          fabsf(enteredPH - 9.18f) > 0.02f) {
        Serial.println(F("[CMD] This 2-point calibrator expects the pH 9.18 buffer: use phcal9 or phcal9 9.18."));
        return true;
      }
    }
  } else {
    return false;
  }

  Serial.printf("[CAPTURE] Probe in pH %.2f buffer; taking 120 ADC samples (~2.4 seconds)...\n",
                referencePH);
  const ReadingWindow reading = readVoltageWindow();
  Serial.printf("[CAPTURE] mean=%.4fV min=%.4fV max=%.4fV spread=%.1fmV\n",
                reading.trimmedMeanV, reading.minV, reading.maxV,
                reading.spreadV * 1000.0f);

  if (reading.trimmedMeanV <= 0.05f || reading.trimmedMeanV > MAX_ADC_V) {
    Serial.println(F("[REJECTED] Voltage is invalid or above 3.25V. Check A/O wiring and protect GPIO35."));
    return true;
  }
  if (reading.spreadV > MAX_CAPTURE_SPREAD_V) {
    Serial.println(F("[REJECTED] More than 80mV variation during capture. Wait for the probe to settle and check connections."));
    return true;
  }
  if (reading.spreadV > WARN_CAPTURE_SPREAD_V) {
    Serial.println(F("[WARNING] Spread is above 10mV. Robust average will be saved, but repeat after readings settle for better accuracy."));
  }

  if (!beginCalNvs(false)) return true;
  const size_t savedVoltage = prefs.putFloat(voltageKey, reading.trimmedMeanV);
  const size_t savedReference = prefs.putFloat(referenceKey, referencePH);
  prefs.end();
  if (savedVoltage != sizeof(float) || savedReference != sizeof(float)) {
    Serial.println(F("[NVS] Save failed; repeat this calibration point."));
  } else {
    Serial.printf("[NVS] Saved pH %.2f point = %.4fV. Rinse the probe before moving to another buffer.\n",
                  referencePH, reading.trimmedMeanV);
  }
  return true;
}

static bool fitAndSave() {
  if (!beginCalNvs(false)) return false;
  const float v4 = prefs.getFloat("phV4", NAN);
  const float v9 = prefs.getFloat("phV9", NAN);
  const float ph4 = prefs.getFloat("phV4Ref", 4.01f);
  const float ph9 = prefs.getFloat("phV9Ref", 9.18f);
  if (!isfinite(v4) || !isfinite(v9)) {
    prefs.end();
    Serial.println(F("[FIT] Missing endpoint(s). Capture pH 4.01 with phcal4 and pH 9.18 with phcal9."));
    return false;
  }
  const float span = v9 - v4;
  if (fabsf(span) < MIN_TWO_POINT_SPAN_V) {
    prefs.end();
    Serial.printf("[FIT] pH4 and pH9 voltages are too close to calculate safely: %.4fmV apart.\n", span * 1000.0f);
    return false;
  }
  const float newSlope = (ph9 - ph4) / span;
  const float newIntercept = ph4 - newSlope * v4;

  const bool saved =
      prefs.putFloat("phSlope", newSlope) == sizeof(float) &&
      prefs.putFloat("phIntercept", newIntercept) == sizeof(float) &&
      prefs.putInt("phFitN", 2) == sizeof(int32_t) &&
      prefs.putInt("phPair", 9) == sizeof(int32_t);
  prefs.end();
  if (!saved) {
    Serial.println(F("[FIT] Could not save calibration to NVS."));
    return false;
  }

  activeSlope = newSlope;
  activeIntercept = newIntercept;
  activeFitCount = 2;
  Serial.printf("[FIT] Saved 2-point fit (pH 4.01 + 9.18): pH = %.5f * V + %.5f\n",
                activeSlope, activeIntercept);
  Serial.printf("[FIT] Checkpoints: pH4=%.2f, pH9=%.2f; voltage span=%.1fmV\n",
                activeSlope * v4 + activeIntercept,
                activeSlope * v9 + activeIntercept,
                fabsf(span) * 1000.0f);
  if (fabsf(span) < 0.050f) {
    Serial.printf("[WARNING] Small %.1fmV span: 10mV of voltage noise can shift the pH by about %.2f. Fit was saved as requested, but verify readings carefully.\n",
                  fabsf(span) * 1000.0f, fabsf(activeSlope) * 0.010f);
  }
  Serial.println(F("[FIT] Run phshow and verify both buffers. Re-upload normal CrayCare firmware; NVS calibration persists."));
  return true;
}

static void printHelp() {
  Serial.println(F("\n=== CrayCare offline pH calibrator ==="));
  Serial.println(F("phread      Read voltage and current fitted pH"));
  Serial.println(F("phcal4      Capture pH 4.01 buffer"));
  Serial.println(F("phcal9 9.18 Capture pH 9.18 buffer point"));
  Serial.println(F("phfit       Fit only pH 4.01 and 9.18, then save to NVS"));
  Serial.println(F("phshow      Show saved buffer points and active formula"));
  Serial.println(F("raw on      Stream raw voltage blocks and STABLE/SETTLING status"));
  Serial.println(F("raw off     Stop the voltage stream"));
  Serial.println(F("phdisplay   Stream calibrated pH values only"));
  Serial.println(F("phdisplay off  Stop calibrated pH display"));
  Serial.println(F("help        Show commands"));
  Serial.println(F("Serial: 115200 baud, line ending Newline"));
}

void setup() {
  Serial.begin(115200);
  delay(800);
  analogReadResolution(12);
  analogSetPinAttenuation(PH_PIN, ADC_11db);
  pinMode(PH_PIN, INPUT);

  Serial.println(F("\n[BOOT] Standalone ESP32 pH calibration; Wi-Fi/Firebase are not included."));
  Serial.println(F("[BOOT] SEN0161 V1.1 A/O -> GPIO35; board powered from regulated 5V."));
  Serial.println(F("[SAFETY] Common GND required; confirm A/O <=3.3V before connecting to GPIO35."));
  if (beginCalNvs(true)) {
    activeSlope = prefs.getFloat("phSlope", NAN);
    activeIntercept = prefs.getFloat("phIntercept", NAN);
    activeFitCount = prefs.getInt("phFitN", 2);
    prefs.end();
  }
  printHelp();
  showSavedCalibration();
}

void loop() {
  if (Serial.available()) {
    String command = Serial.readStringUntil('\n');
    command.trim();
    command.toLowerCase();

    if (command == "help") printHelp();
    else if (command == "raw on" || command == "raw") {
      phDisplayEnabled = false;
      rawStreamEnabled = true;
      resetRawStabilityWindow();
      Serial.println(F("[RAW] Stream ON: one voltage block about every 200ms; STABLE requires a full rolling window with <=10mV spread. Type 'raw off' to stop."));
    } else if (command == "raw off") {
      rawStreamEnabled = false;
      resetRawStabilityWindow();
      Serial.println(F("[RAW] Stream OFF."));
    } else if (command == "phdisplay" || command == "phdisplay on") {
      rawStreamEnabled = false;
      phDisplayEnabled = true;
      resetRawStabilityWindow();
      lastPHDisplayMs = 0;
      if (isfinite(activeSlope) && isfinite(activeIntercept)) {
        Serial.println(F("[PHDISPLAY] ON — calibrated pH values only; type 'phdisplay off' to stop."));
      } else {
        Serial.println(F("[PHDISPLAY] No calibration fit saved yet; output will show -- until phfit succeeds."));
      }
    } else if (command == "phdisplay off") {
      phDisplayEnabled = false;
      resetRawStabilityWindow();
      Serial.println(F("[PHDISPLAY] OFF."));
    } else if (command == "phread") {
      Serial.println(F("[READ] Sampling (~2.4 seconds)..."));
      const ReadingWindow reading = readVoltageWindow();
      Serial.printf("[READ] V=%.4fV min=%.4fV max=%.4fV spread=%.1fmV",
                    reading.trimmedMeanV, reading.minV, reading.maxV,
                    reading.spreadV * 1000.0f);
      if (reading.trimmedMeanV > MAX_ADC_V) {
        Serial.println(F(" [OVER ESP32 INPUT LIMIT]"));
      } else {
        Serial.println();
        if (isfinite(activeSlope) && isfinite(activeIntercept)) {
          Serial.printf("[READ] pH=%.2f using saved %d-point fit\n",
                        activeSlope * reading.trimmedMeanV + activeIntercept,
                        activeFitCount);
        } else {
          Serial.println(F("[READ] No saved pH fit yet; capture all buffers and run phfit."));
        }
      }
      resetRawStabilityWindow();
    } else if (command == "phshow") {
      showSavedCalibration();
    } else if (command == "phfit") {
      fitAndSave();
    } else if (!captureBuffer(command) && command.length() > 0) {
      Serial.println(F("[CMD] Unknown command. Type help."));
    }
    if (rawStreamEnabled || phDisplayEnabled) resetRawStabilityWindow();
  }

  if (rawStreamEnabled && millis() - lastRawPrintMs >= RAW_PRINT_INTERVAL_MS) {
    printRawBlock();
  } else if (phDisplayEnabled && millis() - lastPHDisplayMs >= PH_DISPLAY_INTERVAL_MS) {
    printCalibratedPH();
  }
}
