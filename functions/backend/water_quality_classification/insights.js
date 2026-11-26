"use strict";

const { CLASS_NAMES, FEATURE_NAMES } = require("./wqc_model");
const { SENSOR_THRESHOLDS } = require("./thresholds");

const FRIENDLY = {
  temperature: "Temperature",
  ph_level: "pH",
  dissolved_oxygen: "DO",
  turbidity: "Turbidity",
};

// Default water level thresholds (used only if owner has not configured tank sensor thresholds)
const DEFAULT_CRITICAL_SHALLOW_DEPTH_CM = 3.0;
const DEFAULT_LOW_SHALLOW_DEPTH_CM = 5.0;

function getManilaHour(recordedAt) {
  if (!recordedAt) return null;
  let ms = null;
  if (typeof recordedAt.toMillis === "function") {
    ms = recordedAt.toMillis();
  } else if (recordedAt instanceof Date) {
    ms = recordedAt.getTime();
  } else if (typeof recordedAt === "number" && Number.isFinite(recordedAt)) {
    ms = Math.abs(recordedAt) < 100000000000 ? Math.round(recordedAt * 1000) : recordedAt;
  } else if (typeof recordedAt === "string") {
    const numeric = Number(recordedAt);
    ms = Number.isFinite(numeric)
      ? (Math.abs(numeric) < 100000000000 ? Math.round(numeric * 1000) : numeric)
      : Date.parse(recordedAt);
  }
  if (ms === null || !Number.isFinite(ms)) return null;
  return new Date(ms + 8 * 3600000).getUTCHours();
}

function resolveWaterLevelThresholds(waterLevelThresholds) {
  const low =
    waterLevelThresholds &&
    typeof waterLevelThresholds.low === "number" &&
    Number.isFinite(waterLevelThresholds.low) &&
    waterLevelThresholds.low > 0
      ? waterLevelThresholds.low
      : DEFAULT_LOW_SHALLOW_DEPTH_CM;
  const critical =
    waterLevelThresholds &&
    typeof waterLevelThresholds.critical === "number" &&
    Number.isFinite(waterLevelThresholds.critical) &&
    waterLevelThresholds.critical >= 0 &&
    waterLevelThresholds.critical < low
      ? waterLevelThresholds.critical
      : Math.min(DEFAULT_CRITICAL_SHALLOW_DEPTH_CM, Math.max(0, low - 2.0));
  return { low, critical };
}

function joinNatural(items) {
  if (items.length <= 1) return items[0] || "";
  if (items.length === 2) {
    if (items[0].includes(" and ") || items[0].length > 25) {
      return `${items[0]}, and ${items[1]}`;
    }
    return `${items[0]} and ${items[1]}`;
  }
  return `${items.slice(0, -1).join(", ")}, and ${items[items.length - 1]}`;
}

function capitalize(str) {
  return str ? str.charAt(0).toUpperCase() + str.slice(1) : "";
}

// Determines whether a sensor movement is drifting toward a threshold limit (true)
// or returning toward the optimal zone (false).
function isDriftingTowardLimit(sensor, value, direction) {
  const t = SENSOR_THRESHOLDS[sensor];
  if (!t || !direction || direction === "stable" || direction === "unknown") return false;

  if (sensor === "dissolved_oxygen") {
    return direction === "falling";
  }
  if (sensor === "turbidity") {
    return direction === "rising";
  }

  // Temperature and pH have both lower and upper optimal limits
  const distToLow = t.goodLow !== -Infinity ? value - t.goodLow : Infinity;
  const distToHigh = t.goodHigh !== Infinity ? t.goodHigh - value : Infinity;

  return distToLow <= distToHigh ? direction === "falling" : direction === "rising";
}

// Returns the specific threshold boundary value being approached during a drift warning
function getApproachedThresholdText(sensor, value, direction) {
  const t = SENSOR_THRESHOLDS[sensor];
  if (!t) return "its optimal threshold";

  if (sensor === "dissolved_oxygen") {
    return `its ${t.goodLow.toFixed(1)} mg/L lower limit`;
  }
  if (sensor === "turbidity") {
    return `its ${t.goodHigh.toFixed(1)} NTU upper limit`;
  }
  if (sensor === "temperature") {
    return direction === "falling"
      ? `its ${t.goodLow.toFixed(1)}°C lower limit`
      : `its ${t.goodHigh.toFixed(1)}°C upper limit`;
  }
  if (sensor === "ph_level") {
    return direction === "falling"
      ? `its ${t.goodLow.toFixed(1)} lower limit`
      : `its ${t.goodHigh.toFixed(1)} upper limit`;
  }
  return "its optimal threshold";
}

// Formats elapsed time from trend_analyzer.js windowMinutes
function getTimeframeLabel(activeTrends) {
  const validMinutes = activeTrends
    .map((t) => t.windowMinutes)
    .filter((m) => typeof m === "number" && Number.isFinite(m) && m > 0);

  if (validMinutes.length === 0) {
    return "across recent consecutive readings";
  }

  const maxMinutes = Math.max(...validMinutes);
  if (maxMinutes >= 60) {
    const hours = maxMinutes / 60;
    const rounded = Number.isInteger(hours) ? hours : Number(hours.toFixed(1));
    return `over the past ${rounded} ${rounded === 1 ? "hour" : "hours"}`;
  }

  const roundedMins = Math.round(maxMinutes);
  return `over the past ${roundedMins} ${roundedMins === 1 ? "minute" : "minutes"}`;
}

// Evaluates all 12 pairwise physicochemical and biological interactions across unfavorable parameters
function getCompoundBiologicalNotes(values, perSensorClasses) {
  const [temperature, ph, doValue, turbidity] = values;
  const notes = [];

  const tempClass = perSensorClasses[0];
  const phClass = perSensorClasses[1];
  const doClass = perSensorClasses[2];
  const turbClass = perSensorClasses[3];

  const doLow = doClass === 0 || doClass === 1;
  const turbHigh = turbClass === 0 || turbClass === 1;
  const tempCriticalHigh = tempClass === 0 && temperature >= SENSOR_THRESHOLDS.temperature.criticalHigh;
  const tempWarm = (tempClass === 0 || tempClass === 1) && temperature > SENSOR_THRESHOLDS.temperature.goodHigh;
  const tempCool = (tempClass === 0 || tempClass === 1) && temperature < SENSOR_THRESHOLDS.temperature.goodLow;
  const phHigh = (phClass === 0 || phClass === 1) && ph > SENSOR_THRESHOLDS.ph_level.goodHigh;
  const phLow = (phClass === 0 || phClass === 1) && ph < SENSOR_THRESHOLDS.ph_level.goodLow;

  // Pair 1: Critically High Temperature + Low DO
  if (tempCriticalHigh && doLow) {
    notes.push(
      "Extreme heat paired with low oxygen severely strains cardiac and respiratory capacity in redclaw crayfish"
    );
  } else if (tempWarm && doLow) {
    // Pair 2: Warm Temperature + Low DO
    notes.push(
      "Warm water holds less dissolved oxygen while raising crayfish metabolic oxygen demand, creating a combined oxygen squeeze"
    );
  }

  // Pair 3: Elevated/Critical Turbidity + Low DO
  if (turbHigh && doLow) {
    notes.push(
      "High suspended organic solids also consume oxygen during bacterial decomposition while coating gill filaments"
    );
  }

  // Pair 4: Alkaline pH + Warm Temperature
  if (phHigh && tempWarm) {
    notes.push(
      "Warm, alkaline water shifts ammonium toward its toxic un-ionized form, increasing physiological stress on crayfish"
    );
  }

  // Pair 5: Acidic pH + Elevated/Critical Turbidity
  if (phLow && turbHigh) {
    notes.push(
      "Elevated turbidity paired with acidic pH indicates decomposing organic waste releasing carbon dioxide and organic acids"
    );
  }

  // Pair 6: Alkaline pH + Elevated/Critical Turbidity (Algal photosynthesis signature)
  if (phHigh && turbHigh) {
    notes.push(
      "Elevated turbidity paired with alkaline pH suggests active algal growth consuming dissolved carbon dioxide during daylight"
    );
  }

  // Pair 7: Cool Temperature + Low DO
  if (tempCool && doLow) {
    notes.push(
      "Cool water slows metabolic activity while low oxygen further suppresses feeding, movement, and immune response"
    );
  }

  // Pair 8: Cool Temperature + Elevated/Critical Turbidity
  if (tempCool && turbHigh) {
    notes.push(
      "Cool water slows digestion and feed intake, allowing uneaten pellets to accumulate and increase suspended waste"
    );
  }

  // Pair 9: Acidic pH + Cool Temperature
  if (phLow && tempCool && !turbHigh && !doLow) {
    notes.push(
      "Cool, acidic water slows mineral uptake after molting and prolongs soft-shell vulnerability"
    );
  }

  // Pair 10: Acidic pH + Low DO (without high turbidity)
  if (phLow && doLow && !turbHigh) {
    notes.push(
      "Low oxygen alongside acidic pH reflects elevated respiration and carbon dioxide buildup in the water column"
    );
  }

  // Pair 11: Extreme pH (Acidic or Alkaline) + Low DO
  if ((phLow || phHigh) && doLow) {
    notes.push(
      "Simultaneous pH imbalance and low oxygen place extra strain on gill respiration and ion regulation"
    );
  }

  // Pair 12: Warm Temperature + Elevated/Critical Turbidity (while DO is still optimal)
  if (tempWarm && turbHigh && !doLow) {
    notes.push(
      "Warm water accelerates microbial breakdown of suspended waste, which can rapidly deplete oxygen if left unchecked"
    );
  }

  // Keep top 2 compound biological explanations so the insight card stays clear and readable
  return notes.slice(0, 2);
}

// Contextual hydrological note for ultrasonic water level (non-ML contextual modifier)
function getWaterLevelInsightNote(values, perSensorClasses, waterLevel, waterLevelTrend, waterLevelThresholds = null) {
  const [temperature] = values;
  const hasSubOptimal = perSensorClasses.some((c) => c === 0 || c === 1);
  const { low: lowCm, critical: criticalCm } = resolveWaterLevelThresholds(waterLevelThresholds);

  const hasValidLevel = typeof waterLevel === "number" && Number.isFinite(waterLevel) && waterLevel > 0;
  const isCriticallyShallow = hasValidLevel && waterLevel <= criticalCm;
  const isLowShallow = hasValidLevel && !isCriticallyShallow && waterLevel <= lowCm;

  const wlFalling = waterLevelTrend && typeof waterLevelTrend === "object" && waterLevelTrend.direction === "falling";
  const wlRising = waterLevelTrend && typeof waterLevelTrend === "object" && waterLevelTrend.direction === "rising";
  const dropCm =
    wlFalling && typeof waterLevelTrend.absChangeCm === "number"
      ? waterLevelTrend.absChangeCm.toFixed(1)
      : null;

  if (isCriticallyShallow) {
    const depthText = waterLevel.toFixed(1);
    if (temperature > SENSOR_THRESHOLDS.temperature.goodHigh) {
      return `In addition, water depth is critically shallow at ${depthText} cm, exposing shelters and causing the remaining water to heat up rapidly.`;
    }
    return `In addition, water depth is critically shallow at ${depthText} cm, which can expose hiding shelters, increase territorial stress, and amplify temperature swings.`;
  }

  if (isLowShallow) {
    const depthText = waterLevel.toFixed(1);
    return `In addition, water depth is low at ${depthText} cm. Top up with clean, pre-aerated aged water to maintain proper depth.`;
  }

  if (wlFalling && dropCm !== null) {
    if (temperature > SENSOR_THRESHOLDS.temperature.goodHigh) {
      return `In addition, water level has dropped by ${dropCm} cm, and shallower water heats up faster during warm conditions.`;
    }
    if (temperature < SENSOR_THRESHOLDS.temperature.goodLow) {
      return `In addition, water level has dropped by ${dropCm} cm, reducing thermal mass and allowing faster heat loss.`;
    }
    if (hasSubOptimal) {
      return `In addition, water level has dropped by ${dropCm} cm, concentrating dissolved compounds and waste in a smaller water volume.`;
    }
    return `Note that water level has dropped by ${dropCm} cm, which can reduce thermal stability if it continues to decline.`;
  }

  if (wlRising && hasSubOptimal) {
    return "Water level recently increased after a refill, which may temporarily shift temperature, pH, or dissolved oxygen while the tank equilibrates.";
  }

  return "";
}

function buildTrendNote(values, perSensorClasses, sensorTrends, isGoodResult) {
  if (!sensorTrends) return "";

  const activeTrends = FEATURE_NAMES.map((sensor) => sensorTrends[sensor]).filter(
    (t) => t && t.direction && t.direction !== "unknown" && t.lifecycle !== "insufficient_data"
  );

  // Do not generate a trend claim right after startup when history is still insufficient
  if (activeTrends.length === 0) return "";

  // CASE A: Overall Good Result (ML = Good and all sensors inside Good thresholds)
  if (isGoodResult) {
    const driftingSensors = [];
    const improvingSensors = [];
    const recoveredSensors = [];

    FEATURE_NAMES.forEach((sensor, idx) => {
      const trend = sensorTrends[sensor];
      if (!trend || !trend.direction || trend.direction === "unknown") return;

      const label = FRIENDLY[sensor];

      if (trend.direction === "stable") {
        if (trend.lifecycle === "recovered") {
          recoveredSensors.push(label);
        }
        return;
      }

      const worsening = isDriftingTowardLimit(sensor, values[idx], trend.direction);
      if (worsening && trend.nearBoundary) {
        const limitText = getApproachedThresholdText(sensor, values[idx], trend.direction);
        driftingSensors.push({ label, direction: trend.direction, limitText });
      } else if (!worsening) {
        improvingSensors.push(label);
      }
    });

    // Priority 1: Sensor drifting close to its optimal threshold boundary
    if (driftingSensors.length > 0) {
      const details = driftingSensors.map(
        (d) => `${d.label} has been gradually ${d.direction} toward ${d.limitText}`
      );
      return `While still within safe limits, ${joinNatural(details)} and should be monitored closely.`;
    }

    // Priority 2: Previously stressed parameter(s) recovered and stabilized
    if (recoveredSensors.length > 0) {
      return `${joinNatural(recoveredSensors)} ${recoveredSensors.length === 1 ? "has" : "have"} recovered and stabilized back within the optimal range.`;
    }

    // Priority 3: Water conditions are actively moving deeper into the ideal zone
    if (improvingSensors.length > 0) {
      return `Water conditions are steadily improving, with ${joinNatural(improvingSensors)} moving further into the optimal range.`;
    }

    // Priority 4: All parameters consistently optimal and stable
    const timeframe = getTimeframeLabel(activeTrends);
    return `All parameters have remained consistently optimal ${timeframe} with no sudden spikes or drops, showing strong thermal and chemical stability in the tank.`;
  }

  // CASE B: Overall Poor, Critical, or Mixed Result
  const worseningIssues = [];
  const recoveringIssues = [];
  const boundaryWarnings = [];
  const persistentIssues = [];

  FEATURE_NAMES.forEach((sensor, idx) => {
    const trend = sensorTrends[sensor];
    if (!trend || !trend.direction || trend.direction === "unknown") return;

    const label = FRIENDLY[sensor];
    const sensorClass = perSensorClasses[idx];

    if (trend.direction === "stable") {
      if ((sensorClass === 0 || sensorClass === 1) && trend.lifecycle === "persistent") {
        persistentIssues.push(label);
      }
      return;
    }

    const worsening = isDriftingTowardLimit(sensor, values[idx], trend.direction);

    if (sensorClass !== 2 && sensorClass !== -1) {
      if (worsening) {
        worseningIssues.push(`${label} continues to move further away from optimal levels (${trend.direction})`);
      } else {
        recoveringIssues.push(`${label} is starting to recover toward optimal levels (${trend.direction})`);
      }
    } else if (sensorClass === 2 && worsening && trend.nearBoundary) {
      const limitText = getApproachedThresholdText(sensor, values[idx], trend.direction);
      boundaryWarnings.push(`${label} is also ${trend.direction} toward ${limitText}`);
    }
  });

  const combined = [...worseningIssues, ...recoveringIssues, ...boundaryWarnings];
  if (combined.length > 0) {
    return `${capitalize(joinNatural(combined))}.`;
  }

  if (persistentIssues.length > 0) {
    return `${joinNatural(persistentIssues)} ${persistentIssues.length === 1 ? "has" : "have"} remained persistently outside optimal limits without improvement, so corrective action is needed.`;
  }

  return "All monitored parameters are currently holding steady without further rapid deterioration, though corrective action is still needed.";
}

function formatTrendLead(trendNote) {
  if (!trendNote) return "";
  const trimmed = trendNote.trim();
  if (trimmed.startsWith("In recent trends") || trimmed.startsWith("Recent trend")) {
    return trimmed.endsWith(".") ? trimmed : `${trimmed}.`;
  }
  let lower = trimmed;
  if (!trimmed.startsWith("DO") && !trimmed.startsWith("pH")) {
    lower = trimmed.charAt(0).toLowerCase() + trimmed.slice(1);
  }
  return `In recent trends, ${lower}${lower.endsWith(".") ? "" : "."}`;
}

// Fallback helper for legacy simple trend formatting if imported elsewhere
function buildSimpleTrendNote(sensorTrends) {
  if (!sensorTrends) return "";
  const notes = [];
  for (const sensor of FEATURE_NAMES) {
    const t = sensorTrends[sensor];
    if (!t || t.direction === "unknown" || t.direction === "stable") continue;
    const label = FRIENDLY[sensor] || sensor;
    const decimals = sensor === "ph_level" || sensor === "dissolved_oxygen" ? 2 : 1;
    const unit = sensor === "temperature" ? "°C" : sensor === "dissolved_oxygen" ? " mg/L" : sensor === "turbidity" ? " NTU" : "";
    const sign = t.change >= 0 ? "+" : "-";
    const deltaStr = `(${sign}${Math.abs(t.change).toFixed(decimals)}${unit})`;
    if (t.lifecycle === "improving") {
      notes.push(`${label} is improving ${deltaStr}`);
    } else if (t.lifecycle === "recovered") {
      notes.push(`${label} has recovered`);
    } else if (t.direction === "rising") {
      notes.push(`${label} is rising ${deltaStr}`);
    } else if (t.direction === "falling") {
      notes.push(`${label} is falling ${deltaStr}`);
    }
  }
  return notes.length > 0 ? notes.join(", ") : "";
}

function insightFor(
  prediction,
  rangeClass,
  values,
  perSensorClasses,
  sensorTrends,
  waterLevel = null,
  waterLevelTrend = null,
  waterLevelThresholds = null,
  recordedAt = null,
  longTermTrend = null
) {
  const [temperature, ph, doValue, turbidity] = values;
  const mlLabel = CLASS_NAMES[prediction];

  const hardwareFaults = [];
  const criticalLabels = [];
  const criticalImpacts = [];
  const poorLabels = [];
  const poorImpacts = [];
  const mildGoodWarnings = [];
  const optimalBenefits = [];
  const optimalShortNames = [];

  // 1. Dissolved Oxygen (index 2)
  if (perSensorClasses[2] === -1) {
    hardwareFaults.push(`DO (${doValue.toFixed(2)} mg/L)`);
  } else if (perSensorClasses[2] === 0) {
    criticalLabels.push(`Dissolved Oxygen is critically low (${doValue.toFixed(2)} mg/L)`);
    criticalImpacts.push("critically low oxygen poses an immediate risk of hypoxia");
  } else if (perSensorClasses[2] === 1) {
    poorLabels.push(`Dissolved Oxygen is slightly low (${doValue.toFixed(2)} mg/L)`);
    poorImpacts.push("low oxygen can reduce feeding activity and slow respiration");
    mildGoodWarnings.push(
      `Dissolved Oxygen is slightly low at ${doValue.toFixed(2)} mg/L and should be monitored to prevent oxygen stress`
    );
  } else {
    optimalBenefits.push(
      `high Dissolved Oxygen (${doValue.toFixed(2)} mg/L) supports efficient respiration and active feeding`
    );
    optimalShortNames.push(`DO (${doValue.toFixed(2)} mg/L)`);
  }

  // 2. Turbidity (index 3)
  if (perSensorClasses[3] === -1) {
    hardwareFaults.push(`Turbidity (${turbidity.toFixed(1)} NTU)`);
  } else if (perSensorClasses[3] === 0) {
    criticalLabels.push(`Turbidity is critically high (${turbidity.toFixed(1)} NTU)`);
    criticalImpacts.push("heavy suspended solids risk severe gill fouling and respiratory distress");
  } else if (perSensorClasses[3] === 1) {
    poorLabels.push(`Turbidity is slightly elevated (${turbidity.toFixed(1)} NTU)`);
    poorImpacts.push("elevated suspended solids can cause mild gill fouling and respiratory stress");
    mildGoodWarnings.push(
      `Turbidity is slightly elevated at ${turbidity.toFixed(1)} NTU and should be monitored to avoid mild gill fouling`
    );
  } else {
    optimalBenefits.push(
      `low turbidity (${turbidity.toFixed(1)} NTU) prevents gill fouling and respiratory stress`
    );
    optimalShortNames.push(`Turbidity (${turbidity.toFixed(1)} NTU)`);
  }

  // 3. Temperature (index 0)
  let tempTimeNote = null;
  if (perSensorClasses[0] === -1) {
    hardwareFaults.push(`Temperature (${temperature.toFixed(1)}°C)`);
  } else if (perSensorClasses[0] === 0) {
    const isCold = temperature < SENSOR_THRESHOLDS.temperature.criticalLow;
    criticalLabels.push(`Temperature is critically ${isCold ? "low" : "high"} (${temperature.toFixed(1)}°C)`);
    criticalImpacts.push(
      isCold
        ? "extreme cold risks cold shock and severe metabolic slowdown"
        : "extreme heat risks acute thermal stress"
    );
  } else if (perSensorClasses[0] === 1) {
    const isWarm = temperature > SENSOR_THRESHOLDS.temperature.goodHigh;
    poorLabels.push(`Temperature is slightly ${isWarm ? "warm" : "cool"} (${temperature.toFixed(1)}°C)`);
    poorImpacts.push(
      isWarm
        ? "warm water increases metabolic oxygen demand"
        : "cool water slows down metabolism and feeding"
    );
    mildGoodWarnings.push(
      isWarm
        ? `Temperature is slightly warm at ${temperature.toFixed(1)}°C and should be monitored to avoid thermal stress`
        : `Temperature is slightly cool at ${temperature.toFixed(1)}°C and should be monitored to prevent slowed metabolism`
    );
    if (!isWarm) {
      const manilaHour = getManilaHour(recordedAt);
      if (manilaHour !== null && manilaHour >= 0 && manilaHour < 7) {
        tempTimeNote =
          "This is consistent with expected nocturnal cooling during early morning hours (Boyd & Tucker, 1998). Temperature typically recovers after sunrise.";
      } else if (manilaHour !== null && manilaHour >= 7 && manilaHour < 19) {
        tempTimeNote =
          "Water temperature is below the optimal range during daytime, which may indicate inadequate heating or unusual weather conditions.";
      }
    }
  } else {
    optimalBenefits.push(
      `optimal Temperature (${temperature.toFixed(1)}°C) maintains steady metabolic activity`
    );
    optimalShortNames.push(`Temperature (${temperature.toFixed(1)}°C)`);
  }

  // 4. pH Level (index 1)
  if (perSensorClasses[1] === -1) {
    hardwareFaults.push(`pH (${ph.toFixed(2)})`);
  } else if (perSensorClasses[1] === 0) {
    const isAcidic = ph < SENSOR_THRESHOLDS.ph_level.criticalLow;
    criticalLabels.push(`pH is critically ${isAcidic ? "acidic" : "alkaline"} (${ph.toFixed(2)})`);
    criticalImpacts.push(
      isAcidic
        ? "strongly acidic water causes severe osmoregulatory stress and shell softening"
        : "strongly alkaline water causes acute osmoregulatory stress"
    );
  } else if (perSensorClasses[1] === 1) {
    const isAlkaline = ph > SENSOR_THRESHOLDS.ph_level.goodHigh;
    poorLabels.push(`pH is slightly ${isAlkaline ? "alkaline" : "acidic"} (${ph.toFixed(2)})`);
    poorImpacts.push(
      isAlkaline
        ? "alkaline water can strain osmoregulation"
        : "acidic water can hinder proper shell hardening after molting"
    );
    mildGoodWarnings.push(
      isAlkaline
        ? `pH is slightly alkaline at ${ph.toFixed(2)} and should be monitored to prevent osmoregulatory stress`
        : `pH is slightly acidic at ${ph.toFixed(2)} and should be monitored to support proper shell hardening`
    );
  } else {
    optimalBenefits.push(
      `balanced pH (${ph.toFixed(2)}) promotes proper shell hardening after molting`
    );
    optimalShortNames.push(`pH (${ph.toFixed(2)})`);
  }

  // INSTANCE A: Hardware Fault (-1 on 1 to 4 sensors)
  if (hardwareFaults.length > 0) {
    let faultMsg = `Hardware Alert: Sensor readings are out of physical bounds on ${joinNatural(
      hardwareFaults
    )}. Please inspect sensor wiring, probe immersion, and power supply.`;
    const otherIssues = [...criticalLabels, ...poorLabels];
    if (otherIssues.length > 0) {
      faultMsg += ` Among the remaining valid sensors, ${joinNatural(otherIssues)}.`;
    } else if (optimalShortNames.length > 0) {
      faultMsg += ` Meanwhile, ${joinNatural(optimalShortNames)} remain within optimal levels.`;
    }
    return faultMsg;
  }

  const sentences = [];
  const compoundNotes = getCompoundBiologicalNotes(values, perSensorClasses);
  const totalUnfavorable = criticalLabels.length + poorLabels.length;

  // INSTANCE B: All 4 parameters are within Optimal thresholds
  if (totalUnfavorable === 0) {
    if (prediction === 2) {
      sentences.push(
        `The ML model classified the water quality as Optimal across all monitored parameters. ${capitalize(
          joinNatural(optimalBenefits)
        )}. These conditions keep physiological stress low for steady redclaw crayfish growth.`
      );
    } else {
      // Borderline multivariate ML classification even though individual thresholds are still Good
      sentences.push(
        `The ML model classified the water quality as ${mlLabel} based on combined borderline sensor patterns, even though individual readings on ${joinNatural(
          optimalShortNames
        )} are still within threshold limits. Close monitoring is advised.`
      );
    }

  // INSTANCE C: At least one Critical parameter (1 to 4 Critical, with 0 to 3 Poor)
  } else if (criticalLabels.length > 0) {
    if (prediction === 2) {
      const basis =
        optimalShortNames.length > 0
          ? `optimal readings on ${joinNatural(optimalShortNames)}`
          : "overall feature patterns";
      sentences.push(
        `Parameter Threshold Warning: While the ML model classified overall water quality as Optimal based on ${basis}, ${joinNatural(
          criticalLabels
        )}.`
      );
      sentences.push(`${capitalize(joinNatural(criticalImpacts))}, so immediate corrective action is required.`);
    } else {
      sentences.push(
        `The ML model classified the water quality as ${mlLabel} primarily because ${joinNatural(criticalLabels)}.`
      );
      sentences.push(`${capitalize(joinNatural(criticalImpacts))}.`);
    }

    if (poorLabels.length > 0) {
      sentences.push(`In addition, ${joinNatural(poorLabels)}, where ${joinNatural(poorImpacts)}.`);
    }
    if (compoundNotes.length > 0) {
      sentences.push(`${compoundNotes.join(". ")}.`);
    }
    if (totalUnfavorable >= 3) {
      sentences.push(
        "Multiple simultaneous deviations create severe cumulative stress, requiring immediate and coordinated intervention."
      );
    }
    if (optimalShortNames.length > 0 && prediction !== 2) {
      sentences.push(`Meanwhile, ${joinNatural(optimalShortNames)} remain within optimal levels.`);
    }

  // INSTANCE D: No Critical parameters, 1 to 4 Poor parameters
  } else {
    if (prediction === 2) {
      // ML = Optimal, offsetting 1 or 2 slightly Poor parameters
      if (optimalBenefits.length > 0) {
        sentences.push(`The ML model classified the water quality as Optimal.`);
        sentences.push(`${capitalize(joinNatural(optimalBenefits))}.`);
        sentences.push(`However, ${joinNatural(mildGoodWarnings)}.`);
      } else {
        sentences.push(`The ML model classified the water quality as Optimal, though ${joinNatural(mildGoodWarnings)}.`);
      }
    } else {
      // ML = Poor or Critical driven by multiple Poor readings
      sentences.push(`The ML model classified the water quality as ${mlLabel} because ${joinNatural(poorLabels)}.`);
      sentences.push(`${capitalize(joinNatural(poorImpacts))}.`);
      if (compoundNotes.length > 0) {
        sentences.push(`${compoundNotes.join(". ")}.`);
      }
      if (totalUnfavorable >= 3) {
        sentences.push(
          "Multiple simultaneous deviations create cumulative physiological stress, requiring coordinated water quality management."
        );
      }
      if (optimalShortNames.length > 0) {
        sentences.push(`Meanwhile, ${joinNatural(optimalShortNames)} remain within optimal levels.`);
      }
    }
  }

  if (tempTimeNote) {
    sentences.push(tempTimeNote);
  }

  const waterLevelNote = getWaterLevelInsightNote(
    values,
    perSensorClasses,
    waterLevel,
    waterLevelTrend,
    waterLevelThresholds
  );
  if (waterLevelNote) {
    sentences.push(waterLevelNote);
  }

  if (prediction === 2 && longTermTrend) {
    if (
      longTermTrend.temperature &&
      longTermTrend.temperature.direction === "falling" &&
      Math.abs(longTermTrend.temperature.change) > 1.0
    ) {
      const dropC = Math.abs(longTermTrend.temperature.change).toFixed(1);
      sentences.push(
        `Note: Water temperature has declined by ${dropC}°C over the past 6 hours. While currently within optimal range, sustained cooling may push it below the 26.0°C optimal threshold. Monitor closely (Boyd & Tucker, 1998).`
      );
    }
    if (
      longTermTrend.dissolved_oxygen &&
      longTermTrend.dissolved_oxygen.direction === "falling" &&
      Math.abs(longTermTrend.dissolved_oxygen.change) > 1.0
    ) {
      const dropDo = Math.abs(longTermTrend.dissolved_oxygen.change).toFixed(2);
      sentences.push(
        `Note: Dissolved Oxygen has declined by ${dropDo} mg/L over the past 6 hours. While still within optimal range, sustained oxygen loss can lead to hypoxia stress if aeration is insufficient (Boyd & Tucker, 1998).`
      );
    }
    if (
      longTermTrend.turbidity &&
      longTermTrend.turbidity.direction === "rising" &&
      longTermTrend.turbidity.change > 10.0
    ) {
      const riseTurb = longTermTrend.turbidity.change.toFixed(1);
      sentences.push(
        `Note: Turbidity has increased by ${riseTurb} NTU over the past 6 hours. While still within optimal limits, rising suspended solids may indicate accumulating waste or uneaten feed.`
      );
    }
  }

  const isGoodResult = prediction === 2 && rangeClass === 2;
  const trendNote = buildTrendNote(values, perSensorClasses, sensorTrends, isGoodResult);

  let text = "";
  if (trendNote) {
    const trendLead = formatTrendLead(trendNote);
    text = `${trendLead}\n\n${sentences.join(" ")}`;
  } else {
    text = sentences.join(" ");
  }

  return text.trim();
}

module.exports = {
  insightFor,
  buildSimpleTrendNote,
  resolveWaterLevelThresholds,
  getManilaHour,
};
