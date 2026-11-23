"use strict";

/**
 * Single source of truth for CrayCare water quality sensor thresholds.
 * Class codes:
 *  -1 = Sensor Error / Out of physical hardware bounds
 *   0 = Critical (Life-threatening emergency)
 *   1 = Poor (Sub-optimal / Warning)
 *   2 = Good (Optimal range for Cherax quadricarinatus)
 */

const SENSOR_THRESHOLDS = {
  temperature: {
    label: "Temperature",
    unit: "°C",
    validLow: 0,
    validHigh: 50,
    goodLow: 26.0,
    goodHigh: 29.0,
    criticalLow: 15.0,
    criticalHigh: 34.0,
    criticalHighInclusive: true, // >= 34.0 is Critical
    proximity: 1.0,
    minChange: 0.3,
  },
  ph_level: {
    label: "pH",
    unit: "",
    validLow: 0,
    validHigh: 14,
    goodLow: 6.5,
    goodHigh: 8.5,
    criticalLow: 5.5,
    criticalHigh: 9.5,
    criticalHighInclusive: false, // > 9.5 is Critical
    proximity: 0.3,
    minChange: 0.15,
  },
  dissolved_oxygen: {
    label: "Dissolved Oxygen",
    unit: "mg/L",
    validLow: 0,
    validHigh: 30,
    goodLow: 5.0,
    goodHigh: Infinity,
    criticalLow: 2.0,
    criticalHigh: Infinity,
    criticalHighInclusive: false,
    proximity: 0.8,
    minChange: 0.3,
  },
  turbidity: {
    label: "Turbidity",
    unit: "NTU",
    validLow: 0,
    validHigh: 5000,
    goodLow: 0.0,
    goodHigh: 25.0,
    criticalLow: -Infinity,
    criticalHigh: 50.0,
    criticalHighInclusive: false, // > 50.0 is Critical
    proximity: 5.0,
    minChange: 3.0,
  },
};

/**
 * Classifies a single sensor reading into:
 *  -1 (Sensor Error / Out-of-bounds),
 *   0 (Critical),
 *   1 (Poor),
 *   2 (Good).
 */
function classifySensorValue(sensor, value) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`Invalid sensor value for ${sensor}: ${value}`);
  }
  const t = SENSOR_THRESHOLDS[sensor];
  if (!t) {
    throw new Error(`Unknown sensor: ${sensor}`);
  }

  // 1. Floating-point precision normalization (eliminates 29.000000000000004 boundary jitter)
  const normalizedValue = Number(value.toFixed(2));

  // 2. Hardware sanity check / physical sensor boundaries
  if (normalizedValue < t.validLow || normalizedValue > t.validHigh) {
    return -1; // Out-of-bounds / disconnected probe fault
  }

  // 3. Critical checks (0)
  const isCriticalLow = normalizedValue < t.criticalLow;
  const isCriticalHigh = t.criticalHighInclusive
    ? normalizedValue >= t.criticalHigh
    : normalizedValue > t.criticalHigh;

  if (isCriticalLow || isCriticalHigh) {
    return 0;
  }

  // 4. Good checks (2)
  if (normalizedValue >= t.goodLow && normalizedValue <= t.goodHigh) {
    return 2;
  }

  // 5. Otherwise Poor (1)
  return 1;
}

/**
 * Maps numeric class code to descriptive zone string.
 */
function classCodeToZone(code) {
  switch (code) {
    case -1:
      return "sensor_error";
    case 0:
      return "critical";
    case 1:
      return "poor";
    case 2:
      return "good";
    default:
      return "unknown";
  }
}

module.exports = {
  SENSOR_THRESHOLDS,
  classifySensorValue,
  classCodeToZone,
};
