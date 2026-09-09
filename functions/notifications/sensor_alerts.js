"use strict";

const SENSOR_MAP = {
  temperature: "temp",
  ph_level: "ph",
  dissolved_oxygen: "do",
  turbidity: "turb",
  water_level: "waterlevel",
  feed_level: "feedlevel",
};
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

function stateForSensor(sensorName, value, range) {
  if (value === null || !range) return {state: "unknown"};
  const min = finiteNumber(range.min);
  const max = finiteNumber(range.max);
  if (sensorName === "feed_level") {
    const critical = finiteNumber(range.critical);
    if (min === null || critical === null || critical < 0 ||
        critical >= min || min > 100) return {state: "unknown"};
    if (value === 0) return {state: "critical", dir: "empty", threshold: 0};
    if (value <= critical) return {state: "critical", dir: "low", threshold: critical};
    if (value <= min) return {state: "warning", dir: "low", threshold: min};
    return {state: "normal"};
  }
  if (min === null || max === null || min >= max) return {state: "unknown"};
  if (value < min) return {state: "critical", dir: "low", threshold: min};
  if (value > max) return {state: "critical", dir: "high", threshold: max};
  const margin = (max - min) * WARNING_MARGIN_FRACTION;
  if (value < min + margin) return {state: "warning", dir: "low", threshold: min};
  if (value > max - margin) return {state: "warning", dir: "high", threshold: max};
  return {state: "normal"};
}

function stateChange(sensorName, value, previous, current) {
  if (current.state === previous.state && current.dir === previous.dir) return [];
  const svcKey = SENSOR_MAP[sensorName];
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

module.exports = {SENSOR_MAP, sensorValue, sensorStateChanges, thresholdStateChanges};
