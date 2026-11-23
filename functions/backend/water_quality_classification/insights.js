"use strict";

const { CLASS_NAMES, FEATURE_NAMES } = require("./wqc_model");
const { SENSOR_THRESHOLDS } = require("./thresholds");

// ──────────────────────────────────────────────
// Friendly sensor labels
// ──────────────────────────────────────────────
const FRIENDLY = {
  temperature: "Temperature",
  ph_level: "pH",
  dissolved_oxygen: "DO",
  turbidity: "Turbidity",
};

function joinNatural(items) {
  if (items.length <= 1) return items[0] || "";
  if (items.length === 2) return `${items[0]} and ${items[1]}`;
  return `${items.slice(0, -1).join(", ")}, and ${items[items.length - 1]}`;
}

// ──────────────────────────────────────────────
// Dynamic Insight Generator (Direct, Reading-Based Explanation)
// ──────────────────────────────────────────────

function insightFor(prediction, rangeClass, values, perSensorClasses, sensorTrends) {
  const [temperature, ph, doValue, turbidity] = values;
  const mlLabel = CLASS_NAMES[prediction];

  const criticalIssues = [];
  const poorIssues = [];
  const goodParams = [];

  // Priority 1: Dissolved Oxygen (Most critical for decapod crustaceans)
  if (perSensorClasses[2] === 0) {
    criticalIssues.push(`Dissolved Oxygen is critically low (${doValue.toFixed(2)} mg/L)`);
  } else if (perSensorClasses[2] === 1) {
    poorIssues.push(`Dissolved Oxygen is low (${doValue.toFixed(2)} mg/L)`);
  } else {
    goodParams.push("DO");
  }

  // Priority 2: Turbidity
  if (perSensorClasses[3] === 0) {
    criticalIssues.push(`Turbidity is critically high (${turbidity.toFixed(1)} NTU)`);
  } else if (perSensorClasses[3] === 1) {
    poorIssues.push(`Turbidity is elevated (${turbidity.toFixed(1)} NTU)`);
  } else {
    goodParams.push("Turbidity");
  }

  // Priority 3: Temperature
  if (perSensorClasses[0] === 0) {
    const detail = temperature < SENSOR_THRESHOLDS.temperature.criticalLow ? "critically low" : "critically high";
    criticalIssues.push(`Temperature is ${detail} for crayfish (${temperature.toFixed(1)}°C)`);
  } else if (perSensorClasses[0] === 1) {
    const detail = temperature > SENSOR_THRESHOLDS.temperature.goodHigh ? "slightly warm for crayfish" : "slightly cool for crayfish";
    poorIssues.push(`Temperature is ${detail} (${temperature.toFixed(1)}°C)`);
  } else {
    goodParams.push("Temperature");
  }

  // Priority 4: pH
  if (perSensorClasses[1] === 0) {
    const detail = ph < SENSOR_THRESHOLDS.ph_level.criticalLow ? "critically acidic" : "critically alkaline";
    criticalIssues.push(`pH is ${detail} (${ph.toFixed(2)})`);
  } else if (perSensorClasses[1] === 1) {
    const detail = ph > SENSOR_THRESHOLDS.ph_level.goodHigh ? "alkaline" : "acidic";
    poorIssues.push(`pH is slightly ${detail} (${ph.toFixed(2)})`);
  } else {
    goodParams.push("pH");
  }

  let text = "";

  if (criticalIssues.length === 0 && poorIssues.length === 0) {
    text = "The ML model classified the water quality as Good. All monitored parameters are within optimal range.";
  } else if (criticalIssues.length > 0) {
    const critText = criticalIssues.join(" and ");
    if (prediction === 2) {
      if (goodParams.length > 0) {
        text = `Parameter Threshold Warning: While the ML model classified overall water quality as Good based on majority parameters (${joinNatural(goodParams)}), ${critText}. Immediate corrective action is required.`;
      } else {
        text = `Parameter Threshold Warning: While the ML model classified overall water quality as Good based on multivariate patterns, ${critText}. Immediate corrective action is required.`;
      }
    } else if (poorIssues.length > 0 && goodParams.length > 0) {
      text = `The ML model classified the water quality as ${mlLabel} primarily because ${critText}, while ${poorIssues.join(" and ")}, and ${joinNatural(goodParams)} remain within optimal range.`;
    } else if (poorIssues.length > 0) {
      text = `The ML model classified the water quality as ${mlLabel} primarily because ${critText}, while ${poorIssues.join(" and ")}.`;
    } else if (goodParams.length > 0) {
      text = `The ML model classified the water quality as ${mlLabel} because ${critText}, while ${joinNatural(goodParams)} remain within optimal range.`;
    } else {
      text = `The ML model classified the water quality as ${mlLabel} because ${critText}.`;
    }
  } else {
    const poorText = poorIssues.join(" and ");
    if (prediction === 2) {
      if (goodParams.length > 0) {
        text = `The ML model classified the water quality as Good because ${joinNatural(goodParams)} remain within optimal range, although ${poorText}.`;
      } else {
        text = `The ML model classified the water quality as Good, although ${poorText}.`;
      }
    } else if (goodParams.length > 0) {
      text = `The ML model classified the water quality as ${mlLabel} because ${poorText}, while ${joinNatural(goodParams)} remain within optimal range.`;
    } else {
      text = `The ML model classified the water quality as ${mlLabel} because ${poorText}.`;
    }
  }

  const isGoodResult = prediction === 2 && rangeClass === 2;
  const trendNote = buildSimpleTrendNote(sensorTrends, isGoodResult);
  if (trendNote) {
    text += `\n\nRecent Trend: ${trendNote}`;
  }

  return text;
}

function buildSimpleTrendNote(sensorTrends, isGoodResult) {
  if (!sensorTrends) return null;
  const notes = [];
  let maxWindow = 0;

  for (const sensor of FEATURE_NAMES) {
    const t = sensorTrends[sensor];
    if (!t) continue;
    if (t.windowMinutes && t.windowMinutes > maxWindow) {
      maxWindow = t.windowMinutes;
    }

    if (t.lifecycle === "insufficient_data" || t.lifecycle === "normal" || t.direction === "stable") continue;

    const label = FRIENDLY[sensor];
    const unit = SENSOR_THRESHOLDS[sensor] ? SENSOR_THRESHOLDS[sensor].unit : "";
    const unitStr = unit ? (unit === "°C" ? "°C" : ` ${unit}`) : "";
    const decimals = sensor === "ph_level" ? 2 : 1;
    const sign = t.change >= 0 ? "+" : "-";
    const changeFormatted = `${sign}${Math.abs(t.change).toFixed(decimals)}`;
    const changeAbs = Math.abs(t.change).toFixed(decimals);
    const windowStr = t.windowMinutes ? `over the past ${t.windowMinutes} minutes` : "over recent readings";

    // Evaluate improving / recovered states BEFORE general directional states to avoid shadowing
    if (t.lifecycle === "improving") {
      notes.push(`${label} is actively recovering toward the optimal range (${changeFormatted}${unitStr} ${windowStr}).`);
    } else if (t.lifecycle === "recovered") {
      notes.push(`${label} has stabilized within the optimal range.`);
    } else if (t.direction === "falling" && t.zone !== "good") {
      notes.push(`${label} decreased by ${changeAbs}${unitStr} ${windowStr}.`);
    } else if (t.direction === "rising" && t.zone !== "good") {
      notes.push(`${label} increased by ${changeAbs}${unitStr} ${windowStr}.`);
    } else if (t.direction === "falling" && t.nearBoundary === "lower") {
      notes.push(`${label} is declining toward the lower threshold (${changeFormatted}${unitStr} ${windowStr}).`);
    } else if (t.direction === "rising" && t.nearBoundary === "upper") {
      notes.push(`${label} is rising toward the upper threshold (${changeFormatted}${unitStr} ${windowStr}).`);
    }
  }

  if (notes.length > 0) {
    return notes.join(" ");
  }

  if (isGoodResult && maxWindow > 0) {
    return `Sensor readings have remained stable over the past ${maxWindow} minutes.`;
  }

  return null;
}

module.exports = { insightFor, buildSimpleTrendNote };
