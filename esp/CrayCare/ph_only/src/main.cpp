#include <Arduino.h>
#include <Preferences.h>
#include <math.h>
#include <string.h>

// Dedicated pH-only ESP32 firmware. Production src/main.cpp is untouched.
static constexpr uint8_t PH_PIN = 35;  // ESP32 ADC1 input
static constexpr uint8_t PH_LINK_TX_PIN = 26; // UART2 TX -> main no-pH ESP RX GPIO35
static constexpr uint32_t PH_LINK_BAUD = 115200;
static constexpr uint8_t ADC_SAMPLES = 50;
static constexpr uint8_t FILTER_N = 5;
static constexpr uint8_t STABLE_N = 60; // 60 one-second FIT_V blocks
static constexpr uint32_t SAMPLE_MS = 1000;
static constexpr uint32_t CLOUD_MS = 10000;
static constexpr uint32_t ASSIGNMENT_MS = 60000;
static constexpr float STABLE_SPREAD_V = 0.010f; // 10 mV

Preferences nvs;

String inputLine;
float v4 = NAN, v686 = NAN, v9 = NAN, ref9 = 9.18f;
float phSlope = 0.0f, phIntercept = 0.0f;
int fitMode = 2, pairMode = 9; // pairs: 9=4+9, 686=4+6.86, 6869=6.86+9
bool fitReady = false, showPH = true;

float filter[FILTER_N] = {}, stableWindow[STABLE_N] = {};
uint8_t filterCount = 0, filterNext = 0, stableCount = 0, stableNext = 0;
float rawV = NAN, fitV = NAN, phValue = NAN, stableSpan = NAN;
bool voltageValid = false, isStable = false;
uint32_t lastSample = 0;
uint32_t phLinkSequence = 0;

String lower(String s) { s.toLowerCase(); return s; }
bool validVoltage(float v) { return isfinite(v) && v > 0.05f && v < 3.25f; }

float median(const float *a, uint8_t n) {
  if (!n) return NAN;
  float b[FILTER_N];
  for (uint8_t i = 0; i < n; ++i) b[i] = a[i];
  for (uint8_t i = 1; i < n; ++i) {
    float x = b[i]; int j = i - 1;
    while (j >= 0 && b[j] > x) { b[j + 1] = b[j]; --j; }
    b[j + 1] = x;
  }
  return (n & 1) ? b[n / 2] : (b[n/2 - 1] + b[n/2]) * 0.5f;
}

float readPHVoltageBlock() {
  uint32_t mv = 0;
  for (uint8_t i = 0; i < ADC_SAMPLES; ++i) {
    mv += analogReadMilliVolts(PH_PIN);
    delay(5);
  }
  return (static_cast<float>(mv) / ADC_SAMPLES) / 1000.0f;
}

void updatePH() {
  rawV = readPHVoltageBlock();
  filter[filterNext] = rawV;
  filterNext = (filterNext + 1) % FILTER_N;
  if (filterCount < FILTER_N) ++filterCount;
  fitV = median(filter, filterCount);
  voltageValid = validVoltage(fitV);

  if (!voltageValid) {
    stableCount = stableNext = 0;
    isStable = false;
    stableSpan = NAN;
  } else {
    stableWindow[stableNext] = fitV;
    stableNext = (stableNext + 1) % STABLE_N;
    if (stableCount < STABLE_N) ++stableCount;
    float lo = fitV, hi = fitV;
    for (uint8_t i = 0; i < stableCount; ++i) {
      lo = min(lo, stableWindow[i]);
      hi = max(hi, stableWindow[i]);
    }
    stableSpan = hi - lo;
    isStable = stableCount == STABLE_N && stableSpan <= STABLE_SPREAD_V;
  }
  phValue = fitReady && voltageValid ? phSlope * fitV + phIntercept : NAN;

  if (showPH) {
    if (isfinite(phValue))
      Serial.printf("[PH] raw=%.4fV FIT_V=%.4fV pH=%.2f stable=%s span=%.1fmV blocks=%u/%u\n",
                    rawV, fitV, phValue, isStable ? "YES" : "NO",
                    isfinite(stableSpan) ? stableSpan * 1000.0f : 0.0f,
                    stableCount, STABLE_N);
    else
      Serial.printf("[PH] raw=%.4fV FIT_V=%.4fV pH=UNCALIBRATED stable=%s span=%.1fmV blocks=%u/%u\n",
                    rawV, fitV, isStable ? "YES" : "NO",
                    isfinite(stableSpan) ? stableSpan * 1000.0f : 0.0f,
                    stableCount, STABLE_N);
  }
}

void sendPHLinkFrame() {
  const bool valid = fitReady && voltageValid && isfinite(phValue) &&
                     phValue >= 0.0f && phValue <= 14.0f;
  ++phLinkSequence;
  // Stable is diagnostic metadata; valid filtered readings still flow so the
  // main ESP can continuously average them for its LCD/latest/history windows.
  Serial2.printf("PH1,%lu,%.4f,%.4f,%u,%u\r\n",
                 (unsigned long)phLinkSequence,
                 valid ? phValue : -1.0f,
                 voltageValid ? fitV : 0.0f,
                 valid ? 1U : 0U,
                 isStable ? 1U : 0U);
}

void loadNVS() {
  if (!nvs.begin("phonly", true)) return;
  v4 = nvs.getFloat("v4", NAN);
  v686 = nvs.getFloat("v686", NAN);
  v9 = nvs.getFloat("v9", NAN);
  ref9 = nvs.getFloat("ref9", 9.18f);
  phSlope = nvs.getFloat("slope", 0.0f);
  phIntercept = nvs.getFloat("intercept", 0.0f);
  fitMode = nvs.getInt("mode", 2);
  pairMode = nvs.getInt("pair", 9);
  nvs.end();
  if (fitMode != 3) fitMode = 2;
  if (pairMode != 9 && pairMode != 686 && pairMode != 6869) pairMode = 9;
  fitReady = isfinite(phSlope) && isfinite(phIntercept) && fabsf(phSlope) > 0.0001f;
}

bool applyFit(int reqMode = -1, int reqPair = -1) {
  int mode = (reqMode == 2 || reqMode == 3) ? reqMode : fitMode;
  int pair = (reqPair == 9 || reqPair == 686 || reqPair == 6869) ? reqPair : pairMode;
  float slope = 0, intercept = 0, span = 0;
  if (mode == 2) {
    float aV, bV, aPH, bPH;
    if (pair == 9) { aV = v4; aPH = 4.01f; bV = v9; bPH = ref9; }
    else if (pair == 686) { aV = v4; aPH = 4.01f; bV = v686; bPH = 6.86f; }
    else { aV = v686; aPH = 6.86f; bV = v9; bPH = ref9; }
    if (!validVoltage(aV) || !validVoltage(bV)) {
      Serial.println("[FIT] Selected pair is incomplete; save both points first.");
      return false;
    }
    float delta = bV - aV;
    span = fabsf(delta);
    if (span < 0.001f) { Serial.println("[FIT] Voltage points are too close."); return false; }
    slope = (bPH - aPH) / delta;
    intercept = aPH - slope * aV;
  } else {
    if (!validVoltage(v4) || !validVoltage(v686) || !validVoltage(v9)) {
      Serial.println("[FIT] 3-point fit needs pH 4.01, 6.86, and 9.18 points.");
      return false;
    }
    bool monotonic = (v4 < v686 && v686 < v9) || (v4 > v686 && v686 > v9);
    span = max(v4, max(v686, v9)) - min(v4, min(v686, v9));
    if (!monotonic || span <= 0.05f) {
      Serial.printf("[FIT] 3-point fit requires monotonic points spanning >50mV; span=%.1fmV.\n",
                    span * 1000.0f);
      return false;
    }
    float meanV = (v4 + v686 + v9) / 3.0f;
    float meanPH = (4.01f + 6.86f + ref9) / 3.0f;
    float num = (v4-meanV)*(4.01f-meanPH) +
                (v686-meanV)*(6.86f-meanPH) +
                (v9-meanV)*(ref9-meanPH);
    float den = sq(v4-meanV) + sq(v686-meanV) + sq(v9-meanV);
    if (den <= 0) return false;
    slope = num / den;
    intercept = meanPH - slope * meanV;
  }
  if (!isfinite(slope) || !isfinite(intercept) || !nvs.begin("phonly", false)) {
    Serial.println("[NVS] Could not save fit.");
    return false;
  }
  bool ok = nvs.putFloat("slope", slope) == sizeof(float);
  ok &= nvs.putFloat("intercept", intercept) == sizeof(float);
  ok &= nvs.putInt("mode", mode) == sizeof(int32_t);
  ok &= nvs.putInt("pair", pair) == sizeof(int32_t);
  nvs.end();
  if (!ok) { Serial.println("[NVS] Fit write failed."); return false; }

  phSlope = slope; phIntercept = intercept; fitMode = mode; pairMode = pair; fitReady = true;
  Serial.printf("[FIT] %d-point slope=%.5f intercept=%.5f span=%.1fmV\n",
                mode, slope, intercept, span * 1000.0f);
  if (mode == 2 && span < 0.05f)
    Serial.printf("[FIT WARNING] 10mV noise can shift pH by about %.2f.\n",
                  fabsf(slope) * 0.010f);
  return true;
}

void capturePoint(const String &name, bool force, float nineRef) {
  const char *key = name == "phcal4" ? "v4" :
                    name == "phcal686" ? "v686" : "v9";
  float ref = name == "phcal4" ? 4.01f :
              name == "phcal686" ? 6.86f : nineRef;
  if (!voltageValid || !isfinite(fitV)) { Serial.println("[CAL] Invalid voltage; not saved."); return; }
  if (force ? filterCount < FILTER_N : !isStable) {
    if (force) Serial.println("[CAL] Force capture needs at least five samples.");
    else Serial.printf("[CAL] Wait for 60 blocks/60s with <=10mV span. Current %u/%u, %.1fmV.\n",
                       stableCount, STABLE_N, isfinite(stableSpan) ? stableSpan*1000.0f : 0.0f);
    return;
  }
  if (!nvs.begin("phonly", false)) { Serial.println("[NVS] Storage open failed."); return; }
  bool ok = nvs.putFloat(key, fitV) == sizeof(float);
  if (strcmp(key, "v9") == 0) ok &= nvs.putFloat("ref9", ref) == sizeof(float);
  nvs.end();
  if (!ok) { Serial.println("[NVS] Point save failed."); return; }
  if (strcmp(key, "v4") == 0) v4 = fitV;
  else if (strcmp(key, "v686") == 0) v686 = fitV;
  else { v9 = fitV; ref9 = ref; }
  Serial.printf("[NVS] Saved %sFIT_V %.4fV at pH %.2f%s\n",
                force ? "FORCED " : "stable ", fitV, ref,
                force ? " (verify before trusting)" : "");
  applyFit();
}

void showCalibration() {
  Serial.printf("[NVS] pH4=%.4fV pH6.86=%.4fV pH9=%.4fV(ref %.2f)\n", v4, v686, v9, ref9);
  Serial.printf("[NVS] mode=%d pair=%s fit=%s slope=%.5f intercept=%.5f\n",
                fitMode, pairMode==9 ? "4.01+9.18" : pairMode==686 ? "4.01+6.86" : "6.86+9.18",
                fitReady ? "ready" : "missing", phSlope, phIntercept);
}

void help() {
  Serial.println("\npH ESP commands:");
  Serial.println("phdisplay on|off | phcal4 [force] | phcal686 [force] | phcal9 [9.18] [force]");
  Serial.println("phpair 9.18|6.86|6.86-9.18 | phmode 2|3 | phfit | phshow | phclear");
  Serial.println("help");
}

void command(String cmd) {
  cmd.trim();
  if (!cmd.length()) return;
  String c = lower(cmd);
  if (c == "help") { help(); return; }
  if (c == "phshow") { showCalibration(); return; }
  if (c == "phfit") { applyFit(); return; }
  if (c == "phdisplay on") { showPH = true; return; }
  if (c == "phdisplay off") { showPH = false; Serial.println("[PH] Display OFF"); return; }
  if (c == "phclear") {
    if (nvs.begin("phonly", false)) {
      nvs.remove("v4"); nvs.remove("v686"); nvs.remove("v9"); nvs.remove("ref9");
      nvs.remove("slope"); nvs.remove("intercept"); nvs.remove("mode"); nvs.remove("pair");
      nvs.end();
    }
    v4 = v686 = v9 = NAN; phSlope = phIntercept = 0; fitReady = false;
    Serial.println("[NVS] This ESP's pH calibration erased.");
    return;
  }

  if (c.startsWith("phcal4") || c.startsWith("phcal686") || c.startsWith("phcal9")) {
    bool force = c.endsWith(" force");
    if (force) { c.remove(c.length()-6); c.trim(); }
    float nineRef = 9.18f;
    if (c.startsWith("phcal9 ")) {
      String value = c.substring(7);
      char *end = nullptr;
      nineRef = strtof(value.c_str(), &end);
      if (end == value.c_str() || *end != '\0' || !isfinite(nineRef) || nineRef < 8 || nineRef > 10) {
        Serial.println("Usage: phcal9 [reference pH 8.00-10.00] [force]"); return;
      }
      c = "phcal9";
    } else if (c == "phcal9") nineRef = ref9;
    if (c != "phcal4" && c != "phcal686" && c != "phcal9") {
      Serial.println("Usage: phcal4 [force] | phcal686 [force] | phcal9 [9.18] [force]"); return;
    }

    capturePoint(c, force, nineRef);
    return;
  }
  if (c.startsWith("phmode ")) {
    String m = c.substring(7); m.trim();
    if (m == "2" || m == "3") applyFit(m.toInt());
    else Serial.println("Usage: phmode 2 | phmode 3");
    return;
  }
  if (c.startsWith("phpair ")) {
    String p = c.substring(7); p.trim();
    int selected = p == "9.18" ? 9 : p == "6.86" ? 686 :
        (p == "6.86-9.18" || p == "6.86 9.18") ? 6869 : 0;
    if (!selected) Serial.println("Usage: phpair 9.18 | phpair 6.86 | phpair 6.86-9.18");
    else applyFit(2, selected);
    return;
  }
  Serial.printf("[CMD] Unknown command: %s (type help)\n", cmd.c_str());
}

void serialInput() {
  while (Serial.available()) {
    char ch = static_cast<char>(Serial.read());
    // Serial terminals differ: some send LF, some CR, and some CRLF.
    // Treat either newline byte as the end of a command; ignore the second
    // byte in CRLF once the buffer has already been dispatched.
    if (ch == '\r' || ch == '\n') {
      if (inputLine.length()) {
        command(inputLine);
        inputLine = "";
      }
    }
    else if (inputLine.length() < 180) inputLine += ch;
  }
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(PH_LINK_BAUD, SERIAL_8N1, -1, PH_LINK_TX_PIN);
  delay(300);
  analogReadResolution(12);
  analogSetPinAttenuation(PH_PIN, ADC_11db);
  pinMode(PH_PIN, INPUT);
  loadNVS();
  Serial.println("\nStandalone CrayCare pH ESP32 — UART sensor node");
  Serial.printf("Analog input GPIO%d (ADC1); UART2 TX GPIO%d -> main ESP RX GPIO35 at %lu baud\n",
                PH_PIN, PH_LINK_TX_PIN, (unsigned long)PH_LINK_BAUD);
  Serial.println("pH calibration remains in this ESP's NVS; main ESP owns LCD/Firebase/history/SD.");
  help();
}

void loop() {
  serialInput();
  uint32_t now = millis();
  if (now - lastSample >= SAMPLE_MS) {
    lastSample = now;
    updatePH();
    sendPHLinkFrame();
  }
}


