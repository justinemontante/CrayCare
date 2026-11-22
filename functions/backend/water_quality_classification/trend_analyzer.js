"use strict";

/**
 * Supplementary trend analysis for recent crayfish pond readings.
 * This does not change the Random Forest class; it describes direction,
 * recent range, and whether conditions are improving or worsening.
 */

const SENSOR_CONFIG = {
  temperature: {
    label: "Temperature",
    unit: "°C",
    minChange: 0.3,
    validLow: 0,
    validHigh: 50,
    goodLow: 26,
    goodHigh: 29,
    criticalLow: 23,
    criticalHigh: 34,
    criticalHighInclusive: true,
    proximity: 1.0,
  },
  ph_level: {
    label: "pH",
    unit: "",
    minChange: 0.15,
    validLow: 0,
    validHigh: 14,
    goodLow: 7.0,
    goodHigh: 8.5,
    criticalLow: 6.5,
    criticalHigh: 9.0,
    proximity: 0.3,
  },
  dissolved_oxygen: {
    label: "Dissolved Oxygen",
    unit: "mg/L",
    minChange: 0.3,
    validLow: 0,
    validHigh: 30,
    goodLow: 5.0,
    goodHigh: Infinity,
    criticalLow: 3.0,
    criticalHigh: Infinity,
    proximity: 0.8,
  },
  turbidity: {
    label: "Turbidity",
    unit: "NTU",
    minChange: 3.0,
    validLow: 0,
    validHigh: 5000,
    goodLow: 0,
    goodHigh: 25,
    criticalLow: -Infinity,
    criticalHigh: 50,
    proximity: 5,
  },
};

const FEATURE_NAMES = ["temperature", "ph_level", "dissolved_oxygen", "turbidity"];
const MIN_SAMPLES = 4;
const MAX_GAP_MINUTES = 30;
const BASELINE_WINDOW_MINUTES = (MIN_SAMPLES - 1) * 10;
const DIRECTION_CONSISTENCY_THRESHOLD = 0.60;

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") {
    if (!Number.isFinite(value)) return null;
    return Math.abs(value) < 100000000000 ? Math.round(value * 1000) : value;
  }
  if (typeof value === "string") {
    const numeric = Number(value);
    if (Number.isFinite(numeric)) return timestampMillis(numeric);
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function isValidSensorValue(sensor, value) {
  const cfg = SENSOR_CONFIG[sensor];
  return Boolean(cfg) && typeof value === "number" && Number.isFinite(value) &&
    value >= cfg.validLow && value <= cfg.validHigh;
}

/**
 * Detect direction using actual timestamp gaps. `minChange` is defined for the
 * baseline 30-minute window and is scaled to the observed window length.
 */
function detectDirection(points, cfg) {
  if (points.length < 2) {
    return { direction: "stable", change: 0, consistency: 0, rate: 0, windowMinutes: 0 };
  }

  const first = points[0];
  const last = points[points.length - 1];
  const elapsedMinutes = (last.timestampMs - first.timestampMs) / 60000;
  if (!Number.isFinite(elapsedMinutes) || elapsedMinutes <= 0) {
    return { direction: "stable", change: 0, consistency: 0, rate: 0, windowMinutes: 0 };
  }

  const totalChange = last.value - first.value;
  let risingMinutes = 0;
  let fallingMinutes = 0;
  for (let i = 1; i < points.length; i++) {
    const minutes = (points[i].timestampMs - points[i - 1].timestampMs) / 60000;
    const difference = points[i].value - points[i - 1].value;
    if (difference > 0) risingMinutes += minutes;
    else if (difference < 0) fallingMinutes += minutes;
  }

  const consistency = Math.max(risingMinutes, fallingMinutes) / elapsedMinutes;
  const rate = totalChange / (elapsedMinutes / 10);
  const requiredChange = cfg.minChange * (elapsedMinutes / BASELINE_WINDOW_MINUTES);
  const change = Number(totalChange.toFixed(3));
  const roundedConsistency = Number(consistency.toFixed(2));
  const roundedRate = Number(rate.toFixed(3));
  const windowMinutes = Math.round(elapsedMinutes);

  if (totalChange >= requiredChange && consistency >= DIRECTION_CONSISTENCY_THRESHOLD) {
    return { direction: "rising", change, consistency: roundedConsistency, rate: roundedRate, windowMinutes };
  }
  if (totalChange <= -requiredChange && consistency >= DIRECTION_CONSISTENCY_THRESHOLD) {
    return { direction: "falling", change, consistency: roundedConsistency, rate: roundedRate, windowMinutes };
  }
  return { direction: "stable", change, consistency: roundedConsistency, rate: roundedRate, windowMinutes };
}

function zoneInfo(value, cfg) {
  const criticalLow = value < cfg.criticalLow;
  const criticalHigh = cfg.criticalHighInclusive
    ? value >= cfg.criticalHigh
    : value > cfg.criticalHigh;

  let zone;
  if (criticalLow || criticalHigh) {
    zone = "critical";
  } else if (value < cfg.goodLow || value > cfg.goodHigh) {
    zone = "poor";
  } else {
    zone = "good";
  }

  let nearBoundary = null;
  if (zone === "good") {
    if (cfg.goodLow !== -Infinity && value - cfg.goodLow <= cfg.proximity) {
      nearBoundary = "lower";
    } else if (cfg.goodHigh !== Infinity && cfg.goodHigh - value <= cfg.proximity) {
      nearBoundary = "upper";
    }
  }

  return { zone, nearBoundary };
}

function insufficientTrend(latestValue = null) {
  return {
    direction: "unknown",
    change: 0,
    rate: 0,
    consistency: 0,
    zone: "unknown",
    nearBoundary: null,
    lifecycle: "insufficient_data",
    latestValue,
    samplesCount: 0,
    windowMinutes: null,
  };
}

function analyzeTrends(recentReadings, prevResult) {
  const trends = {};
  const prevTrends = (prevResult && prevResult.sensor_trends) || {};
  const orderedReadings = recentReadings
    .map((reading) => ({ reading, timestampMs: timestampMillis(reading.recorded_at) }))
    .filter((item) => item.timestampMs !== null)
    .sort((a, b) => a.timestampMs - b.timestampMs);

  for (const sensor of FEATURE_NAMES) {
    const cfg = SENSOR_CONFIG[sensor];
    const points = orderedReadings
      .filter(({ reading }) => isValidSensorValue(sensor, reading[sensor]))
      .map(({ reading, timestampMs: recordedAt }) => ({
        value: reading[sensor],
        timestampMs: recordedAt,
      }));

    const latestValue = points.length ? points[points.length - 1].value : null;
    if (points.length < MIN_SAMPLES) {
      trends[sensor] = insufficientTrend(latestValue);
      continue;
    }

    const gaps = points.slice(1).map((point, index) =>
      (point.timestampMs - points[index].timestampMs) / 60000);
    const elapsedMinutes = (points[points.length - 1].timestampMs - points[0].timestampMs) / 60000;
    if (
      !Number.isFinite(elapsedMinutes) || elapsedMinutes <= 0 ||
      gaps.some((gap) => !Number.isFinite(gap) || gap <= 0 || gap > MAX_GAP_MINUTES)
    ) {
      trends[sensor] = insufficientTrend(latestValue);
      continue;
    }

    const direction = detectDirection(points, cfg);
    const zone = zoneInfo(latestValue, cfg);
    const previous = prevTrends[sensor] || {};
    const lifecycle = computeLifecycle(direction, zone, previous, cfg, latestValue);

    trends[sensor] = {
      ...direction,
      zone: zone.zone,
      nearBoundary: zone.nearBoundary,
      lifecycle,
      latestValue,
      samplesCount: points.length,
    };
  }

  return { trends };
}

function computeLifecycle(direction, zone, previous, cfg, latestValue) {
  const previousLifecycle = previous.lifecycle || "normal";
  const previousZone = previous.zone || "good";

  if (zone.zone === "good" && direction.direction === "stable") {
    if (previousZone !== "good" ||
        (previousLifecycle !== "normal" && previousLifecycle !== "recovered")) {
      return "recovered";
    }
    return "normal";
  }

  if (zone.zone === "good" && zone.nearBoundary) {
    const towardBoundary =
      (zone.nearBoundary === "lower" && direction.direction === "falling") ||
      (zone.nearBoundary === "upper" && direction.direction === "rising");
    if (towardBoundary) {
      return previousLifecycle === "normal" || previousLifecycle === "recovered"
        ? "new"
        : "persistent";
    }
    if (previousLifecycle !== "normal" && previousLifecycle !== "recovered") {
      return "improving";
    }
    return "normal";
  }

  if (zone.zone === "good") {
    if (previousZone !== "good") return "recovered";
    if (previousLifecycle !== "normal" && previousLifecycle !== "recovered") return "improving";
    return "normal";
  }

  if (previousZone === "good" &&
      (previousLifecycle === "normal" || previousLifecycle === "recovered")) {
    return "new";
  }

  if (zone.zone === "critical" && previousZone === "poor") return "worsening";
  if (zone.zone === "poor" && previousZone === "critical") return "improving";

  const belowGoodRange = latestValue < cfg.goodLow;
  const aboveGoodRange = latestValue > cfg.goodHigh;
  const movingTowardGood =
    (belowGoodRange && direction.direction === "rising") ||
    (aboveGoodRange && direction.direction === "falling");
  const movingAwayFromGood =
    (belowGoodRange && direction.direction === "falling") ||
    (aboveGoodRange && direction.direction === "rising");

  if (movingTowardGood) return "improving";
  if (movingAwayFromGood) return "worsening";
  return "persistent";
}

module.exports = {
  SENSOR_CONFIG,
  analyzeTrends,
  detectDirection,
  zoneInfo,
  computeLifecycle,
  isValidSensorValue,
  timestampMillis,
  MIN_SAMPLES,
  MAX_GAP_MINUTES,
};
