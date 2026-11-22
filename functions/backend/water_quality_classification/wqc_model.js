"use strict";

const forest = require("./wqc_random_forest.json");

const FEATURE_NAMES = [
  "temperature",
  "ph_level",
  "dissolved_oxygen",
  "turbidity",
];
const CLASS_NAMES = { 0: "Critical", 1: "Poor", 2: "Good" };

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

function sensorClass(feature, value) {
  if (feature === "temperature") {
    if (value < 15 || value >= 34) return 0;
    if (value < 26 || value > 29) return 1;
    return 2;
  }
  if (feature === "ph_level") {
    if (value < 5.5 || value > 9.5) return 0;
    if (value < 6.5 || value > 8.5) return 1;
    return 2;
  }
  if (feature === "dissolved_oxygen") {
    if (value < 2) return 0;
    if (value < 5) return 1;
    return 2;
  }
  if (feature === "turbidity") {
    if (value > 50) return 0;
    if (value > 25) return 1;
    return 2;
  }
  throw new Error(`Unknown feature: ${feature}`);
}

function readingNote(feature, value, status) {
  const formatted = value.toFixed(2);
  if (feature === "temperature") {
    if (status === 0) return `Temperature ${formatted}°C is in the Critical range.`;
    if (status === 1) return `Temperature ${formatted}°C is outside the Good range of 26–29°C.`;
  }
  if (feature === "ph_level") {
    if (status === 0) return `pH ${formatted} is in the Critical range.`;
    if (status === 1) return `pH ${formatted} is outside the Good range of 6.5–8.5.`;
  }
  if (feature === "dissolved_oxygen") {
    if (status === 0) return `DO ${formatted} mg/L is below the Critical limit of 2.0 mg/L.`;
    if (status === 1) return `DO ${formatted} mg/L is below the 5.0 mg/L Good target.`;
  }
  if (feature === "turbidity") {
    if (status === 0) return `Turbidity ${formatted} NTU is in the Critical range.`;
    if (status === 1) return `Turbidity ${formatted} NTU is outside the Good range of 0–25 NTU.`;
  }
  return null;
}

function rangeAnalysis(values) {
  const perSensorClasses = FEATURE_NAMES.map((feature, index) =>
    sensorClass(feature, values[index]));
  return {
    perSensorClasses,
    overallClass: Math.min(...perSensorClasses),
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
