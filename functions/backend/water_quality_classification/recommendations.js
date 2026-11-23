"use strict";

const { SENSOR_THRESHOLDS } = require("./thresholds");
const { insightFor } = require("./insights");

// ──────────────────────────────────────────────────────────────────────────────
// Comprehensive 9-Tier Contextual Recommendation Engine for Cherax quadricarinatus
// Covers all 81 threshold combinations, all 12 pairwise/multi-sensor interactions,
// probe-specific hardware diagnostics, proactive boundary trends, ultrasonic
// water-level depth & refill hydrology, borderline ML alerts, and recovery states.
// Zero em dashes or en dashes.
// ──────────────────────────────────────────────────────────────────────────────

const CRITICAL_SHALLOW_DEPTH_CM = 16.0;

function isSensorRecovering(sensor, value, sensorTrends) {
  if (!sensorTrends || !sensorTrends[sensor]) return false;
  const dir = sensorTrends[sensor].direction;
  if (!dir || dir === "stable" || dir === "unknown") return false;

  const t = SENSOR_THRESHOLDS[sensor];
  if (value < t.goodLow) return dir === "rising";
  if (value > t.goodHigh) return dir === "falling";
  return false;
}

function recommendationFor(
  prediction,
  rangeClass,
  values,
  perSensorClasses,
  sensorTrends,
  waterLevel = null,
  waterLevelTrend = null
) {
  const [temperature, ph, doValue, turbidity] = values;
  const actions = [];

  const tempClass = perSensorClasses[0];
  const phClass = perSensorClasses[1];
  const doClass = perSensorClasses[2];
  const turbClass = perSensorClasses[3];

  // ── Tier 0: Probe-Specific Hardware & Electrical Diagnostics (-1) ──
  const hwDiagnostics = [];
  if (doClass === -1) {
    hwDiagnostics.push("inspect the Dissolved Oxygen probe cable, membrane cap, and submerged placement");
  }
  if (turbClass === -1) {
    hwDiagnostics.push("clean the Turbidity optical lens and check for air bubbles or loose wiring");
  }
  if (tempClass === -1) {
    hwDiagnostics.push("verify that the waterproof Temperature probe is fully submerged and properly connected");
  }
  if (phClass === -1) {
    hwDiagnostics.push("check the pH probe BNC connector, isolator board, and bulb hydration");
  }
  if (hwDiagnostics.length > 0) {
    const joined =
      hwDiagnostics.length === 1
        ? hwDiagnostics[0]
        : `${hwDiagnostics.slice(0, -1).join(", ")}, and ${hwDiagnostics[hwDiagnostics.length - 1]}`;
    actions.push(
      `Hardware Fault Detected: One or more readings are outside valid physical sensor limits. Please ${joined} immediately, and avoid making water chemistry adjustments based on faulty readings.`
    );
  }

  // Deduplication flags so multi-parameter combinations produce clear, non-conflicting actions
  let waterRefillHandled = false;
  let suspendFeeding = false;
  let reduceFeeding = false;
  let bottomSiphonHandled = false;
  let aerationHandled = false;
  let shadeHandled = false;

  const doCritical = doClass === 0;
  const doPoor = doClass === 1;
  const doLow = doCritical || doPoor;

  const tempCriticalHigh = tempClass === 0 && temperature >= SENSOR_THRESHOLDS.temperature.criticalHigh;
  const tempCriticalLow = tempClass === 0 && temperature < SENSOR_THRESHOLDS.temperature.criticalLow;
  const tempWarmPoor = tempClass === 1 && temperature > SENSOR_THRESHOLDS.temperature.goodHigh;
  const tempCoolPoor = tempClass === 1 && temperature < SENSOR_THRESHOLDS.temperature.goodLow;
  const tempWarm = tempCriticalHigh || tempWarmPoor;
  const tempCool = tempCriticalLow || tempCoolPoor;

  const phCriticalLow = phClass === 0 && ph < SENSOR_THRESHOLDS.ph_level.criticalLow;
  const phCriticalHigh = phClass === 0 && ph > SENSOR_THRESHOLDS.ph_level.criticalHigh;
  const phAcidicPoor = phClass === 1 && ph < SENSOR_THRESHOLDS.ph_level.goodLow;
  const phAlkalinePoor = phClass === 1 && ph > SENSOR_THRESHOLDS.ph_level.goodHigh;
  const phAcidic = phCriticalLow || phAcidicPoor;
  const phAlkaline = phCriticalHigh || phAlkalinePoor;

  const turbCritical = turbClass === 0;
  const turbPoor = turbClass === 1;
  const turbElevated = turbCritical || turbPoor;

  // Ultrasonic water level context (value decreases as water evaporates/drops)
  const hasValidLevel = typeof waterLevel === "number" && Number.isFinite(waterLevel) && waterLevel > 0;
  const isCriticallyShallow = hasValidLevel && waterLevel < CRITICAL_SHALLOW_DEPTH_CM;
  const wlFalling = waterLevelTrend !== null && waterLevelTrend.direction === "falling";
  const wlRising = waterLevelTrend !== null && waterLevelTrend.direction === "rising";
  const wlDropCm =
    wlFalling && typeof waterLevelTrend.absChangeCm === "number"
      ? waterLevelTrend.absChangeCm.toFixed(1)
      : null;

  // ── Tier 1: Dissolved Oxygen (Primary Life-Safety & Pre-Hypoxia Prevention) ──
  if (doCritical) {
    actions.push(
      "Turn on all aerators immediately, keeping airstones 2 to 3 inches off the trapond floor so bottom sludge is not stirred up."
    );
    actions.push(
      "Suspend feeding until Dissolved Oxygen recovers above 5.0 mg/L because uneaten feed accelerates oxygen depletion, and check oxygen every 15 to 30 minutes."
    );
    aerationHandled = true;
    suspendFeeding = true;
  } else if (doPoor) {
    const recovering = isSensorRecovering("dissolved_oxygen", doValue, sensorTrends);
    if (tempWarm) {
      actions.push(
        "Run aerators continuously and install shade netting because warm water holds less oxygen while raising crayfish metabolic oxygen demand."
      );
      aerationHandled = true;
      shadeHandled = true;
    } else if (recovering) {
      actions.push(
        "Keep aerators running as Dissolved Oxygen is starting to recover, and continue monitoring until readings stabilize above 5.0 mg/L."
      );
      aerationHandled = true;
    } else {
      actions.push(
        "Turn on aerators and monitor oxygen levels closely until readings stabilize above 5.0 mg/L."
      );
      aerationHandled = true;
    }
    if (!suspendFeeding && !reduceFeeding) {
      actions.push(
        "Feed lightly until Dissolved Oxygen returns above 5.0 mg/L so uneaten pellets do not consume extra oxygen."
      );
      reduceFeeding = true;
    }
  } else if (doClass === 2 && sensorTrends && sensorTrends.dissolved_oxygen) {
    const doTrend = sensorTrends.dissolved_oxygen;
    if (doTrend.direction === "falling") {
      if (doTrend.nearBoundary === "lower") {
        actions.push(
          "Dissolved Oxygen is trending downward toward its 5.0 mg/L limit. Turn on aerators early and avoid overfeeding if the drop continues."
        );
        aerationHandled = true;
      } else {
        actions.push(
          "Monitor Dissolved Oxygen closely and prepare to turn on aerators if the downward trend continues."
        );
      }
    }
  }

  // ── Tier 2: Compound Critical DO + Elevated/Critical Turbidity Anti-Sludge Protection ──
  if (doCritical && turbElevated) {
    actions.push(
      "Turbidity is also elevated while Dissolved Oxygen is critical. Avoid deep siphoning or stirring the trapond bottom right now because disturbing settled organic matter consumes more oxygen. Clean filter pads gently and resume bottom siphoning only after oxygen recovers above 5.0 mg/L."
    );
    bottomSiphonHandled = true;
  }

  // ── Tier 3: pH Balance, Ammonia Detoxification & Organic Acid Control ──
  if (phCriticalLow) {
    waterRefillHandled = true;
    if (!suspendFeeding) {
      actions.push("Suspend feeding immediately to stop adding organic waste to the tank.");
      suspendFeeding = true;
    }
    if (!doCritical && !bottomSiphonHandled) {
      actions.push(
        "Siphon bottom sludge and uneaten feed because decomposing waste releases carbon dioxide and acids that drive pH down."
      );
      bottomSiphonHandled = true;
    }
    actions.push(
      "Perform a gradual 10% to 20% water change using pre-aerated, pH-neutral aged water. Avoid sudden chemical pH adjusters because abrupt pH swings cause molting shock."
    );
  } else if (phCriticalHigh) {
    waterRefillHandled = true;
    if (!suspendFeeding) {
      actions.push(
        "Suspend feeding immediately because high pH converts harmless ammonium into toxic un-ionized ammonia."
      );
      suspendFeeding = true;
    }
    if (!shadeHandled) {
      actions.push(
        "Provide shade over the trapond to slow algae photosynthesis and maximize aeration to stabilize pH."
      );
      shadeHandled = true;
      aerationHandled = true;
    }
    actions.push(
      "Perform a gradual 10% to 20% water change using pre-aerated neutral aged water after checking your source water pH."
    );
  } else if (phAcidicPoor) {
    if (turbElevated && !doCritical && !bottomSiphonHandled) {
      actions.push(
        "Both slightly acidic pH and elevated turbidity point to decomposing organic waste. Clean filter pads and siphon uneaten feed from the trapond bottom, and avoid sudden chemical pH adjusters."
      );
      bottomSiphonHandled = true;
    } else if (!bottomSiphonHandled && !doCritical) {
      actions.push(
        "Siphon uneaten feed and decaying organic matter from the trapond bottom because decomposition produces acids that lower pH. Avoid sudden chemical pH adjusters."
      );
      bottomSiphonHandled = true;
    }
    if (doLow && !aerationHandled) {
      actions.push("Maintain strong aeration to strip excess dissolved carbon dioxide and support oxygen recovery.");
      aerationHandled = true;
    }
  } else if (phAlkalinePoor) {
    if (!shadeHandled) {
      actions.push(
        "Check for algae growth on trapond walls and water surface, add shade netting to reduce direct sunlight, and maintain strong aeration."
      );
      shadeHandled = true;
      aerationHandled = true;
    }
    if (tempWarm && !suspendFeeding && !reduceFeeding) {
      actions.push(
        "Warm water combined with high pH increases ammonia toxicity, so feed sparingly and remove any uneaten pellets promptly."
      );
      reduceFeeding = true;
    }
  } else if (phClass === 2 && sensorTrends && sensorTrends.ph_level) {
    const phTrend = sensorTrends.ph_level;
    if (phTrend.nearBoundary === "lower" && phTrend.direction === "falling") {
      actions.push(
        "pH is trending downward toward its 6.5 limit. Inspect the trapond bottom for uneaten feed buildup and verify that the pH probe is clean."
      );
    } else if (phTrend.nearBoundary === "upper" && phTrend.direction === "rising") {
      actions.push(
        "pH is trending upward toward its 8.5 limit. Check for excess algae growth or strong sunlight exposure, and verify source water pH before the next refill."
      );
    }
  }

  // ── Tier 4: Temperature Control & Thermal Shock Prevention ──
  if (tempCriticalHigh) {
    if (!waterRefillHandled) {
      actions.push(
        "Maximize aeration and provide shade over the trapond immediately. Slowly add cooler, pre-aerated aged water to bring temperature down gradually because sudden cold water causes thermal shock and mass molting stress."
      );
      waterRefillHandled = true;
      aerationHandled = true;
      shadeHandled = true;
    } else if (!shadeHandled) {
      actions.push("Maximize aeration and provide shade over the trapond to help reduce water temperature.");
      aerationHandled = true;
      shadeHandled = true;
    }
  } else if (tempCriticalLow) {
    if (!suspendFeeding && !reduceFeeding) {
      actions.push("Reduce feeding significantly because crayfish metabolism slows sharply in cold water.");
      reduceFeeding = true;
    }
    if (!waterRefillHandled) {
      actions.push(
        "Maintain full water depth to retain heat, and slowly add slightly warmer pre-aerated aged water after checking source water pH."
      );
      waterRefillHandled = true;
    } else {
      actions.push("Maintain full water depth to help retain heat in the trapond.");
    }
  } else if (tempWarmPoor) {
    if (!shadeHandled) {
      actions.push("Provide shade over the trapond and increase surface aeration to cool the water.");
      shadeHandled = true;
      aerationHandled = true;
    }
    if (turbElevated && !suspendFeeding && !reduceFeeding) {
      actions.push("Feed lightly while water is warm and turbid so decomposing pellets do not trigger an oxygen drop.");
      reduceFeeding = true;
    }
  } else if (tempCoolPoor) {
    if (!suspendFeeding && !reduceFeeding) {
      actions.push(
        "Reduce feeding rations slightly because crayfish digest food more slowly in cool water and uneaten pellets can foul the tank."
      );
      reduceFeeding = true;
    }
    if ((wlFalling || isCriticallyShallow) && !waterRefillHandled) {
      actions.push(
        "Water depth is low, and shallow water loses heat faster. Slowly add clean, pre-aerated aged water to restore depth and stabilize temperature after checking source water pH."
      );
      waterRefillHandled = true;
    } else if (!wlFalling && !isCriticallyShallow) {
      actions.push("Maintain proper water depth to stabilize temperature, and avoid adding cold refill water.");
    }
  } else if (tempClass === 2 && sensorTrends && sensorTrends.temperature) {
    const tempTrend = sensorTrends.temperature;
    if (tempTrend.nearBoundary === "upper" && tempTrend.direction === "rising" && !shadeHandled) {
      actions.push("Improve air circulation, add shade, and increase surface aeration to prevent overheating.");
      shadeHandled = true;
      aerationHandled = true;
    } else if (tempTrend.nearBoundary === "lower" && tempTrend.direction === "falling") {
      if ((wlFalling || isCriticallyShallow) && !waterRefillHandled) {
        actions.push(
          "Water depth is dropping while temperature is falling. Slowly add clean, pre-aerated aged water to restore depth and prevent rapid cooling after checking source water pH."
        );
        waterRefillHandled = true;
      } else if (!wlFalling && !isCriticallyShallow) {
        actions.push("Maintain proper water depth to keep water temperature stable.");
      }
    }
  }

  // ── Tier 5: Ultrasonic Water Level Depth & Refill Equilibration ──
  if (isCriticallyShallow && !waterRefillHandled) {
    actions.push(
      `Water depth is critically shallow at ${waterLevel.toFixed(1)} cm, which can expose hiding shelters and cause rapid temperature swings. Slowly top up with clean, pre-aerated aged water after checking source water pH.`
    );
    waterRefillHandled = true;
  } else if (wlFalling && !waterRefillHandled && wlDropCm !== null) {
    if (temperature > SENSOR_THRESHOLDS.temperature.goodHigh) {
      actions.push(
        `Water level is gradually dropping (down ${wlDropCm} cm), and shallow water heats up faster. Slowly add clean, pre-aerated aged water to restore proper depth after checking source water pH.`
      );
    } else if (turbElevated || phAcidic || phAlkaline) {
      actions.push(
        `Water level is gradually dropping (down ${wlDropCm} cm), concentrating waste and dissolved compounds in less water. Slowly add clean, pre-aerated aged water to restore depth after checking source water pH.`
      );
    } else {
      actions.push(
        `Water level is gradually dropping (down ${wlDropCm} cm). Slowly add clean, pre-aerated aged water to restore proper depth, and check source water pH before refilling.`
      );
    }
    waterRefillHandled = true;
  } else if (wlRising && rangeClass !== 0) {
    actions.push(
      "Water level recently increased after a refill. Monitor pH, temperature, and dissolved oxygen over the next few hours to confirm the added water stays well balanced."
    );
  }

  // ── Tier 6: Turbidity & Organic Solids Management ──
  if (turbCritical && !doCritical) {
    if (!bottomSiphonHandled) {
      actions.push("Clean filter pads and siphon waste and uneaten feed from the trapond bottom.");
      bottomSiphonHandled = true;
    }
    if (!suspendFeeding) {
      actions.push("Suspend feeding until turbidity and organic waste stabilize.");
      suspendFeeding = true;
    }
  } else if (turbPoor && !doCritical && !bottomSiphonHandled) {
    actions.push("Siphon uneaten feed and waste from the trapond bottom, and clean filter pads.");
    bottomSiphonHandled = true;
  } else if (turbClass === 2 && sensorTrends && sensorTrends.turbidity) {
    const turbTrend = sensorTrends.turbidity;
    if (turbTrend.direction === "rising") {
      actions.push("Inspect filter pads and check the trapond bottom for uneaten feed or waste buildup.");
    }
  }

  // ── Tier 7: Multi-Parameter Systemic Coordination (3 or 4 Unfavorable Sensors) ──
  const unfavorableCount = perSensorClasses.filter((c) => c === 0 || c === 1).length;
  if (unfavorableCount >= 3 && !waterRefillHandled && !doCritical) {
    actions.push(
      "Because multiple parameters are outside optimal range at the same time, perform a gradual 10% to 15% partial water change with pre-aerated aged water after cleaning the filter pads to reset overall water balance safely."
    );
    waterRefillHandled = true;
  }

  // ── Tier 8 & 9: Borderline ML Watch, Recovery Confirmation, or Routine Care ──
  if (actions.length === 0) {
    if (prediction !== 2 && rangeClass === 2) {
      actions.push(
        "Individual readings are still within safe limits, but the ML model detected a borderline pattern. Check aerator airflow, inspect filter pads, and monitor readings closely."
      );
    } else {
      const hasRecovery =
        sensorTrends &&
        ["temperature", "ph_level", "dissolved_oxygen", "turbidity"].some(
          (s) =>
            sensorTrends[s] &&
            (sensorTrends[s].lifecycle === "improving" || sensorTrends[s].lifecycle === "recovered")
        );
      if (hasRecovery) {
        actions.push(
          "Water quality has stabilized back within optimal levels. Maintain current aeration and filtration settings, and continue routine feeding and monitoring."
        );
      } else {
        actions.push("Continue routine monitoring, regular feeding, and normal trapond care.");
      }
    }
  }

  return actions.join(" ");
}

module.exports = {
  recommendationFor,
  insightFor, // Re-exported for seamless backward compatibility
};
