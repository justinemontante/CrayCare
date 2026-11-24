"use strict";

const forest = require("./wqc_random_forest.json");
const { SENSOR_THRESHOLDS, classifySensorValue } = require("./thresholds");

const FEATURE_NAMES = [
  "temperature",
  "ph_level",
  "dissolved_oxygen",
  "turbidity",
];
const CLASS_NAMES = { "-1": "Sensor Error", 0: "Critical", 1: "Poor", 2: "Optimal" };

function predictClass(values) {
  // values = [temperature, ph_level, dissolved_oxygen, turbidity]
  // The model includes the DO-to-temperature ratio as its fifth feature.
  const temperature = values[0];
  const dissolvedOxygen = values[2];
  const doTempRatio = dissolvedOxygen / Math.max(temperature, 1);
  const modelValues = [...values, doTempRatio];

  const classVotes = forest.classes.map(() => 0);
  for (const tree of forest.trees) {
    let node = 0;
    while (tree.left[node] !== -1) {
      const featureIndex = tree.feature[node];
      node = modelValues[featureIndex] <= tree.threshold[node]
        ? tree.left[node]
        : tree.right[node];
    }

    const leafValues = tree.value[node];
    const leafTotal = leafValues.reduce((sum, value) => sum + value, 0);
    if (leafTotal <= 0) continue;
    for (let index = 0; index < classVotes.length; index++) {
      classVotes[index] += leafValues[index] / leafTotal;
    }
  }

  let bestIndex = 0;
  for (let index = 1; index < classVotes.length; index++) {
    if (classVotes[index] > classVotes[bestIndex]) bestIndex = index;
  }
  return forest.classes[bestIndex];
}

function readingNote(feature, value, status) {
  const formatted = value.toFixed(2);
  const t = SENSOR_THRESHOLDS[feature];
  if (!t) return null;

  if (status === -1) {
    return `${t.label} reading ${formatted}${t.unit ? " " + t.unit : ""} is outside physical sensor bounds (${t.validLow}–${t.validHigh}${t.unit ? " " + t.unit : ""}) indicating sensor disconnect or hardware fault.`;
  }
  if (feature === "temperature") {
    if (status === 0) return `Temperature ${formatted}°C is in the Critical range.`;
    if (status === 1) return `Temperature ${formatted}°C is outside the Optimal range of ${t.goodLow}–${t.goodHigh}°C.`;
  }
  if (feature === "ph_level") {
    if (status === 0) return `pH ${formatted} is in the Critical range.`;
    if (status === 1) return `pH ${formatted} is outside the Optimal range of ${t.goodLow}–${t.goodHigh}.`;
  }
  if (feature === "dissolved_oxygen") {
    if (status === 0) return `DO ${formatted} mg/L is below the Critical limit of ${t.criticalLow.toFixed(1)} mg/L.`;
    if (status === 1) return `DO ${formatted} mg/L is below the ${t.goodLow.toFixed(1)} mg/L Optimal target.`;
  }
  if (feature === "turbidity") {
    if (status === 0) return `Turbidity ${formatted} NTU is in the Critical range.`;
    if (status === 1) return `Turbidity ${formatted} NTU is outside the Optimal range of ${t.goodLow}–${t.goodHigh} NTU.`;
  }
  return null;
}

function rangeAnalysis(values) {
  const perSensorClasses = FEATURE_NAMES.map((feature, index) =>
    classifySensorValue(feature, values[index]));
  
  const hasSensorError = perSensorClasses.some((code) => code === -1);
  const biologicalClasses = perSensorClasses.filter((code) => code >= 0);
  const overallClass = hasSensorError ? -1 : (biologicalClasses.length ? Math.min(...biologicalClasses) : 0);

  return {
    perSensorClasses,
    overallClass,
    notes: FEATURE_NAMES
      .map((feature, index) => readingNote(feature, values[index], perSensorClasses[index]))
      .filter(Boolean),
  };
}

module.exports = {
  CLASS_NAMES,
  FEATURE_NAMES,
  predictClass,
  rangeAnalysis,
};
