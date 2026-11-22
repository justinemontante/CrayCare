"use strict";

const { CLASS_NAMES, FEATURE_NAMES } = require("./wqc_model");
const { SENSOR_CONFIG } = require("./trend_analyzer");

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
    const detail = temperature < 15 ? "critically low" : "critically high";
    criticalIssues.push(`Temperature is ${detail} for crayfish (${temperature.toFixed(1)}°C)`);
  } else if (perSensorClasses[0] === 1) {
    const detail = temperature > 29 ? "slightly warm for crayfish" : "slightly cool for crayfish";
    poorIssues.push(`Temperature is ${detail} (${temperature.toFixed(1)}°C)`);
  } else {
    goodParams.push("Temperature");
  }

  // Priority 4: pH
  if (perSensorClasses[1] === 0) {
    const detail = ph < 6.5 ? "critically acidic" : "critically alkaline";
    criticalIssues.push(`pH is ${detail} (${ph.toFixed(2)})`);
  } else if (perSensorClasses[1] === 1) {
    const detail = ph > 8.5 ? "alkaline" : "acidic";
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
        text = `Safety Override Alert: Although majority parameters (${joinNatural(goodParams)}) are optimal and the ML statistical model scored overall as Good, ${critText}. Immediate corrective action is required.`;
      } else {
        text = `Safety Override Alert: Although the ML statistical model scored overall as Good, ${critText}. Immediate corrective action is required.`;
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
    const unit = SENSOR_CONFIG[sensor].unit;
    const unitStr = unit ? (unit === "°C" ? "°C" : ` ${unit}`) : "";
    const changeAbs = Math.abs(t.change).toFixed(sensor === "ph_level" ? 2 : 1);
    const windowStr = t.windowMinutes ? `over the past ${t.windowMinutes} minutes` : "over recent readings";

    if (t.direction === "falling" && t.zone !== "good") {
      notes.push(`${label} decreased by ${changeAbs}${unitStr} ${windowStr}.`);
    } else if (t.direction === "rising" && t.zone !== "good") {
      notes.push(`${label} increased by ${changeAbs}${unitStr} ${windowStr}.`);
    } else if (t.direction === "falling" && t.nearBoundary === "lower") {
      notes.push(`${label} is declining toward the lower threshold (-${changeAbs}${unitStr} ${windowStr}).`);
    } else if (t.direction === "rising" && t.nearBoundary === "upper") {
      notes.push(`${label} is rising toward the upper threshold (+${changeAbs}${unitStr} ${windowStr}).`);
    } else if (t.lifecycle === "recovering" || t.lifecycle === "improving") {
      notes.push(`${label} is actively recovering toward the optimal range (+${changeAbs}${unitStr} ${windowStr}).`);
    } else if (t.lifecycle === "recovered") {
      notes.push(`${label} has stabilized within the optimal range.`);
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

// ──────────────────────────────────────────────
// Contextual Recommendation Generator
// (Simple, Practical Phrasing for Trapond Management)
// ──────────────────────────────────────────────

function recommendationFor(prediction, rangeClass, values, perSensorClasses, sensorTrends, waterLevel = null, waterLevelTrend = null) {
  const [temperature, ph, doValue, turbidity] = values;
  const actions = [];

  // Flags to prevent duplicate / conflicting water-addition prompts
  let needsWaterChange = false;   // a water-change action was already added for pH
  let waterRefillHandled = false; // any water-addition action was already added
  let suspendFeeding = false;     // feeding should be suspended due to critical params

  // Water level context:
  // Value DECREASES as water evaporates/drops (bumababa = shallower tank).
  // "falling" trend = water level has been dropping = risk of shallow water.
  // "rising" trend = farmer refilled the tank.
  const wlFalling = waterLevelTrend !== null && waterLevelTrend.direction === "falling";
  const wlDropCm = wlFalling ? waterLevelTrend.absChangeCm.toFixed(1) : null;

  // ── Priority 1: Dissolved Oxygen (Most urgent for crayfish) ──
  // Science: DO < 3 mg/L = critical hypoxia. Crayfish surface-breathe and die rapidly.
  // Feeding during hypoxia worsens DO further (decomposing uneaten feed consumes 30–50% DO).
  if (doValue < 3) {
    actions.push(
      "Turn on all aerators immediately (keep airstones 2–3 inches off the trapond floor to avoid re-suspending bottom sludge). " +
      "Suspend feeding until DO recovers above 5 mg/L — uneaten feed accelerates oxygen depletion. " +
      "Monitor oxygen every 15–30 minutes."
    );
    suspendFeeding = true;
  } else if (doValue < 5) {
    actions.push("Turn on aerators and monitor oxygen levels closely until readings stabilize above 5 mg/L.");
  } else if (sensorTrends) {
    const doTrend = sensorTrends.dissolved_oxygen;
    if (doTrend && doTrend.direction === "falling" && doValue >= 5) {
      actions.push("Monitor oxygen closely and prepare to turn on aerators if the downward trend continues.");
    }
  }

  // ── Priority 2: Critical DO + Critical Turbidity (Compound risk) ──
  // Science: High turbidity = high organic load = additional oxygen sink.
  // Avoid stirring bottom sludge when DO is already critical.
  if (doValue < 3 && perSensorClasses[3] === 0) {
    actions.push(
      "Turbidity is also critically high — avoid deep siphoning or stirring the trapond bottom while DO is critical, " +
      "as this re-suspends oxygen-consuming organic matter. Resume bottom siphoning only after DO recovers."
    );
  }

  // ── Priority 3: pH ──
  // Science: Falling pH (acidic) = decomposing organic waste / CO₂ accumulation.
  //          Rising pH (alkaline) = algae photosynthesis or high-pH source water.
  //          High pH dramatically increases un-ionized ammonia toxicity to crayfish.
  if (perSensorClasses[1] === 0) {
    needsWaterChange = true;
    waterRefillHandled = true;
    if (ph < 6.5) {
      // Acidic critical: cause = organic waste decomposition / CO₂
      if (!suspendFeeding) {
        actions.push("Suspend feeding immediately to stop adding organic load.");
        suspendFeeding = true;
      }
      actions.push(
        "Siphon bottom sludge and uneaten feed accumulation (organic decomposition is driving pH down). " +
        "Perform a gradual 10%–20% water change using pre-aerated, pH-neutral aged water. " +
        "Avoid sudden chemical pH adjusters — abrupt pH swings cause molting shock in crayfish."
      );
    } else {
      // Alkaline critical: cause = algae bloom / source water
      if (!suspendFeeding) {
        actions.push("Suspend feeding (high pH significantly increases ammonia toxicity to crayfish).");
        suspendFeeding = true;
      }
      actions.push(
        "Provide shade over the trapond to slow algae photosynthesis (algae bloom is the primary cause of rising pH). " +
        "Maximize aeration to stabilize CO₂/pH balance. " +
        "Perform a gradual 10%–20% water change using pre-aerated neutral aged water. " +
        "Check the pH of your source water before refilling."
      );
    }
  } else if (perSensorClasses[1] === 1) {
    if (ph < 7) {
      // Mildly acidic: cause = organic buildup / excess CO₂
      actions.push(
        "Siphon uneaten feeds and decaying organic matter from the trapond bottom " +
        "(decomposition is producing CO₂ and organic acids that lower pH). " +
        "Avoid sudden chemical pH adjusters."
      );
    } else if (ph > 8.5) {
      // Mildly alkaline: cause = algae / source water
      actions.push(
        "Check for visible algae growth on trapond walls and water surface — algae photosynthesis is the most common cause of rising pH. " +
        "Reduce direct sunlight with shade netting and ensure strong aeration."
      );
    }
  } else if (sensorTrends) {
    const phTrend = sensorTrends.ph_level;
    if (phTrend && phTrend.nearBoundary === "lower" && phTrend.direction === "falling") {
      // pH declining toward acidic boundary: cause = organic decomposition
      actions.push(
        "pH is trending downward — inspect the trapond bottom for uneaten feed buildup or decaying matter, " +
        "and verify sensor probe cleanliness."
      );
    } else if (phTrend && phTrend.nearBoundary === "upper" && phTrend.direction === "rising") {
      // pH rising toward alkaline boundary: cause = algae / source water
      actions.push(
        "pH is trending upward — check for algae growth or excess sunlight exposure, " +
        "and verify the pH of your source water before the next refill."
      );
    }
  }

  // ── Priority 4: Temperature ──
  // Note: Water additions here always specify "aged/pre-aerated" to prevent pH/DO shock.
  // Consolidated: skip standalone refill if water change was already recommended for pH.
  if (perSensorClasses[0] === 0) {
    if (temperature >= 34) {
      if (!waterRefillHandled) {
        actions.push(
          "Maximize aeration and provide shade over the trapond. " +
          "Slowly add cooler pre-aerated aged water to bring temperature down gradually — sudden cold water causes thermal shock and mass molting stress."
        );
        waterRefillHandled = true;
      } else {
        actions.push("Maximize aeration and provide shade over the trapond to help reduce temperature.");
      }
    } else {
      if (!waterRefillHandled) {
        actions.push(
          "Maintain full water depth to retain heat. " +
          "Slowly add slightly warmer pre-aerated aged water to restore safe temperature — check source water pH before adding."
        );
        waterRefillHandled = true;
      } else {
        actions.push("Maintain full water depth to help retain heat in the trapond.");
      }
    }
  } else if (perSensorClasses[0] === 1) {
    if (temperature > 29) {
      actions.push("Provide shade over the trapond and increase surface aeration to cool the water.");
    } else if (temperature < 26) {
      if (wlFalling && !waterRefillHandled) {
        actions.push(
          `Water level is dropping (down ${wlDropCm} cm). Shallow water loses heat faster — ` +
          `slowly add clean pre-aerated aged water to restore depth and stabilize temperature. ` +
          `Check source water pH and temperature before adding.`
        );
        waterRefillHandled = true;
      } else if (!wlFalling) {
        actions.push("Maintain proper water depth to stabilize temperature, and avoid adding cold refill water.");
      }
    }
  } else if (sensorTrends) {
    const tempTrend = sensorTrends.temperature;
    if (tempTrend && tempTrend.nearBoundary === "upper" && tempTrend.direction === "rising") {
      actions.push("Improve air circulation, add shade, and increase surface aeration to prevent overheating.");
    } else if (tempTrend && tempTrend.nearBoundary === "lower" && tempTrend.direction === "falling") {
      if (wlFalling && !waterRefillHandled) {
        actions.push(
          `Water level is dropping (down ${wlDropCm} cm) while temperature is falling — ` +
          `slowly add clean pre-aerated aged water to restore depth and prevent rapid cooling. ` +
          `Check source water pH before adding.`
        );
        waterRefillHandled = true;
      } else if (!wlFalling) {
        actions.push("Maintain proper water depth to stabilize temperature.");
      }
    }
  }

  // ── Standalone Water Level Warning ──
  // Only fires if wlFalling was not already addressed by Temperature or pH sections.
  if (wlFalling && !waterRefillHandled) {
    const shallowNote = temperature > 29
      ? "Shallow water heats up faster — monitor temperature closely."
      : "Shallow water fluctuates in temperature faster — monitor readings closely.";
    actions.push(
      `Water level is gradually dropping (down ${wlDropCm} cm). ` +
      `Slowly add clean pre-aerated aged water to restore proper depth. ` +
      `Check source water pH before adding. ${shallowNote}`
    );
  }

  // ── Priority 5: Turbidity ──
  if (perSensorClasses[3] === 0) {
    // Only add siphon advice here if DO is NOT also critical (compound case handled in Priority 2 above)
    if (doValue >= 3) {
      actions.push(
        "Clean filter pads and siphon waste and uneaten feeds from the trapond bottom. " +
        "Reduce feeding frequency until turbidity improves."
      );
    }
  } else if (perSensorClasses[3] === 1) {
    actions.push("Siphon uneaten feeds and waste from the trapond bottom, and clean filter pads.");
  } else if (sensorTrends) {
    const turbTrend = sensorTrends.turbidity;
    if (turbTrend && turbTrend.direction === "rising" && turbTrend.zone === "good") {
      actions.push("Inspect filter pads and check the trapond bottom for uneaten feeds or waste buildup.");
    }
  }

  // ── Priority 6: Feeding Suspension Summary (if not already stated above) ──
  // Only add this if suspendFeeding was set by pH/DO but no explicit suspend message was pushed for turbidity.
  if (suspendFeeding && perSensorClasses[3] === 0 && doValue >= 3) {
    // Turbidity critical + suspended feeding already from pH, reinforce
    actions.push("Reduce or suspend feeding until water quality improves to prevent further organic load.");
  }

  // ── Priority 7: All Good / Routine ──
  if (actions.length === 0) {
    actions.push("Continue routine monitoring, regular feeding, and normal trapond care.");
  }

  return actions.join(" ");
}


module.exports = { insightFor, recommendationFor };
