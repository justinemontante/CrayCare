"use strict";

const SENSOR_MAP = {
  temperature: "temp",
  ph_level: "ph",
  dissolved_oxygen: "do",
  turbidity: "turb",
  water_level: "waterlevel",
  feed_level: "feedlevel",
};

// Hysteresis recovery buffers — literature-backed (Boyd & Tucker 1998, FAO).
// A sensor in alert must exceed this recovery margin before returning to normal.
// Prevents threshold-bouncing spam when readings hover near the alert boundary.
//
// Sensor      | Enter alert at | Recover to normal at
// ------------|----------------|---------------------
// Temperature | < 26 °C        | > 26.5 °C  (±0.5 °C buffer)
//             | > 29 °C        | < 28.5 °C
// pH          | < 6.5          | > 6.8      (±0.3 pH units)
//             | > 8.5          | < 8.2
// DO          | < 5.0 mg/L     | > 5.5 mg/L (+0.5 mg/L buffer)
// Turbidity   | > 25 NTU       | < 22 NTU   (–3 NTU buffer)
// Water Level | ≤ low cm       | > low + 0.5 cm
// Feed Level  | ≤ low %        | > low + 2 %

const WARNING_MARGIN_FRACTION = 0.1;

function finiteNumber(raw) {
  if (typeof raw !== "number" &&
      !(typeof raw === "string" && raw.trim() !== "")) return null;
  const value = Number(raw);
  return Number.isFinite(value) ? value : null;
}

function sensorValue(sensorName, reading) {
  if (!reading) return null;
  if (sensorName === "turbidity" &&
      (reading.turbidity_air === true || reading.turbidityAir === true)) return null;
  const value = finiteNumber(reading[sensorName]);
  // The firmware publishes negative sentinels for unavailable sensors. Zero is
  // still a real reading (including an empty hopper or zero dissolved oxygen).
  if (value === null || value < 0) return null;
  if (sensorName === "feed_level" && value > 100) return null;
  return value;
}

/**
 * Compute the alert state for a single sensor reading.
 *
 * @param {string} sensorName  - Firestore field name (e.g. "dissolved_oxygen")
 * @param {number|null} value  - Current reading value
 * @param {object} range       - Threshold config { min, max, low, critical }
 * @param {string} prevState   - Last *alerted* state: "normal"|"warning"|"critical"|"unknown"
 *                               Used to apply hysteresis on the recovery path.
 */
function stateForSensor(sensorName, value, range, prevState = "normal") {
  if (value === null || !range) return {state: "unknown"};

  // inAlert = sensor was previously in a degraded state; apply hysteresis buffer
  // so the reading must recover past the buffer before we report "normal".
  const inAlert = prevState === "warning" || prevState === "critical";

  // ── Water Level ──────────────────────────────────────────────────────────
  if (sensorName === "water_level") {
    const critical = finiteNumber(range.critical);
    const low      = finiteNumber(range.low);
    if (critical === null || low === null || critical < 0 || critical >= low)
      return {state: "unknown"};
    if (value === 0) return {state: "critical", dir: "empty", threshold: 0};
    if (value <= critical) return {state: "critical", dir: "low", threshold: critical};
    // Hysteresis: stay in alert until value > low + 0.5 cm
    if (value <= low || (inAlert && value <= low + 0.5))
      return {state: "warning", dir: "low", threshold: low};
    return {state: "normal"};
  }

  // ── Feed Level ───────────────────────────────────────────────────────────
  if (sensorName === "feed_level") {
    const critical = finiteNumber(range.critical);
    const low      = finiteNumber(range.low ?? range.min);
    if (low === null || critical === null || critical < 0 ||
        critical >= low || low > 100) return {state: "unknown"};
    if (value === 0) return {state: "critical", dir: "empty", threshold: 0};
    if (value <= critical) return {state: "critical", dir: "low", threshold: critical};
    // Hysteresis: stay in alert until value > low + 2 %
    if (value <= low || (inAlert && value <= low + 2))
      return {state: "warning", dir: "low", threshold: low};
    return {state: "normal"};
  }

  // ── Temperature  (Boyd & Tucker 1998 — Redclaw optimal 26–29 °C) ─────────
  if (sensorName === "temperature") {
    const critLow  = 15.0;
    const critHigh = 34.0;
    const optMin   = finiteNumber(range.min) ?? 26.0;
    const optMax   = finiteNumber(range.max) ?? 29.0;
    if (value < critLow)  return {state: "critical", dir: "low",  threshold: critLow};
    if (value >= critHigh) return {state: "critical", dir: "high", threshold: critHigh};
    // Hysteresis: ±0.5 °C recovery buffer
    if (value < optMin || (inAlert && value < optMin + 0.5))
      return {state: "warning", dir: "low",  threshold: optMin};
    if (value > optMax || (inAlert && value > optMax - 0.5))
      return {state: "warning", dir: "high", threshold: optMax};
    return {state: "normal"};
  }

  // ── pH  (Boyd & Tucker 1998 — optimal 6.5–8.5) ───────────────────────────
  if (sensorName === "ph_level") {
    const critLow  = 5.5;
    const critHigh = 9.5;
    const optMin   = finiteNumber(range.min) ?? 6.5;
    const optMax   = finiteNumber(range.max) ?? 8.5;
    if (value < critLow)  return {state: "critical", dir: "low",  threshold: critLow};
    if (value > critHigh) return {state: "critical", dir: "high", threshold: critHigh};
    // Hysteresis: ±0.3 pH units
    if (value < optMin || (inAlert && value < optMin + 0.3))
      return {state: "warning", dir: "low",  threshold: optMin};
    if (value > optMax || (inAlert && value > optMax - 0.3))
      return {state: "warning", dir: "high", threshold: optMax};
    return {state: "normal"};
  }

  // ── Dissolved Oxygen  (Meade et al. 2002, FAO — ≥ 5.0 mg/L optimal) ─────
  if (sensorName === "dissolved_oxygen") {
    const critLow = 2.0;
    const optMin  = finiteNumber(range.min) ?? 5.0;
    if (value < critLow) return {state: "critical", dir: "low", threshold: critLow};
    // Hysteresis: +0.5 mg/L recovery buffer
    if (value < optMin || (inAlert && value < optMin + 0.5))
      return {state: "warning", dir: "low", threshold: optMin};
    return {state: "normal"};
  }

  // ── Turbidity  (Boyd & Tucker 1998 — ≤ 25 NTU optimal) ──────────────────
  if (sensorName === "turbidity") {
    const critHigh = 50.0;
    const optMax   = finiteNumber(range.max) ?? 25.0;
    if (value > critHigh) return {state: "critical", dir: "high", threshold: critHigh};
    // Hysteresis: –3 NTU recovery buffer (must drop to < 22 NTU to clear)
    if (value > optMax || (inAlert && value > optMax - 3.0))
      return {state: "warning", dir: "high", threshold: optMax};
    return {state: "normal"};
  }

  // ── Generic fallback (any other sensor with min/max config) ───────────────
  const min = finiteNumber(range.min);
  const max = finiteNumber(range.max);
  if (min === null || max === null || min >= max) return {state: "unknown"};
  const buffer = (max - min) * 0.05; // 5% hysteresis buffer
  if (value < min || (inAlert && value < min + buffer))
    return {state: "warning", dir: "low",  threshold: min};
  if (value > max || (inAlert && value > max - buffer))
    return {state: "warning", dir: "high", threshold: max};
  return {state: "normal"};
}

function stateChange(sensorName, value, previous, current) {
  if (current.state === previous.state && current.dir === previous.dir) return [];
  const svcKey = SENSOR_MAP[sensorName];
  if (svcKey === "turb") {
    const highAlert = ["critical", "warning"].includes(current.state) &&
      current.dir === "high";
    const highAlertResolved = current.state === "normal" &&
      previous.dir === "high" &&
      ["critical", "warning"].includes(previous.state);
    // Zero/low turbidity is clear water. Only the upper limit (and its
    // recovery) may create turbidity push or inbox notifications.
    if (!highAlert && !highAlertResolved) return [];
  }
  if (current.state === "critical" || current.state === "warning") {
    return [{svcKey, val: value, threshold: current.threshold,
      dir: current.dir, state: current.state}];
  }
  if (current.state === "normal" && ["critical", "warning"].includes(previous.state)) {
    return [{svcKey, val: value, state: "resolved"}];
  }
  return [];
}

function sensorStateChanges(before, after, thresholds) {
  return Object.keys(SENSOR_MAP).flatMap(sensorName => {
    const value = sensorValue(sensorName, after);
    if (value === null) return [];
    return stateChange(sensorName, value,
      stateForSensor(sensorName, sensorValue(sensorName, before), thresholds[sensorName]),
      stateForSensor(sensorName, value, thresholds[sensorName]));
  });
}

function thresholdStateChanges(sensorName, reading, beforeRange, afterRange) {
  const value = sensorValue(sensorName, reading);
  if (!SENSOR_MAP[sensorName] || value === null) return [];
  return stateChange(sensorName, value,
    stateForSensor(sensorName, value, beforeRange),
    stateForSensor(sensorName, value, afterRange));
}

module.exports = {SENSOR_MAP, sensorValue, stateForSensor, sensorStateChanges, thresholdStateChanges};
