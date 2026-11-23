"use strict";

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const forest = require("./wqc_random_forest.json");
const {
  CLASS_NAMES,
  FEATURE_NAMES,
  predictClass,
  rangeAnalysis,
} = require("./wqc_model");
const {
  analyzeTrends,
  MIN_SAMPLES,
} = require("./trend_analyzer");
const { insightFor } = require("./insights");
const { recommendationFor } = require("./recommendations");
const { fetchRecentReadings, saveResult } = require("./firestore_records");

const db = admin.firestore();
const MODEL_VERSION = forest.model_version;

// ──────────────────────────────────────────────
// Feature extraction & validation
// ──────────────────────────────────────────────

function readFeatures(data) {
  const values = FEATURE_NAMES.map((feature) => data[feature]);
  if (!values.every((value) => typeof value === "number" && Number.isFinite(value))) {
    return null;
  }
  const [temperature, ph, dissolvedOxygen, turbidity] = values;
  if (
    temperature < 0 || temperature > 50 ||
    ph < 0 || ph > 14 ||
    dissolvedOxygen < 0 || dissolvedOxygen > 30 ||
    turbidity < 0 || turbidity > 5000
  ) {
    return null;
  }
  return values;
}

// ──────────────────────────────────────────────
// Build prediction (with trend awareness)
// ──────────────────────────────────────────────

function buildPrediction(data, values, range, prediction, sourcePath, sensorTrends, prevResult, waterLevelTrend = null) {
  const timestamp = data.recorded_at || null;

  const { perSensorClasses } = range;
  const rangeClass = range.overallClass;

  // Build the sensor_trends summary to save in Firestore
  const trendsToStore = {};
  if (sensorTrends) {
    for (const sensor of FEATURE_NAMES) {
      const t = sensorTrends[sensor];
      if (t) {
        trendsToStore[sensor] = {
          direction: t.direction,
          zone: t.zone,
          lifecycle: t.lifecycle,
          nearBoundary: t.nearBoundary || null,
          rate: t.rate,
          change: t.change,
          latestValue: t.latestValue,
          windowMinutes: t.windowMinutes || null,
        };
      }
    }
  }

  return {
    prediction_status: "classified",
    class_code: prediction,
    class_label: CLASS_NAMES[prediction],
    threshold_status: CLASS_NAMES[rangeClass],
    insight: insightFor(prediction, rangeClass, values, perSensorClasses, sensorTrends),
    recommendation: recommendationFor(prediction, rangeClass, values, perSensorClasses, sensorTrends, typeof data.water_level === "number" ? data.water_level : null, waterLevelTrend),
    sensor_trends: trendsToStore,
    source_recorded_at: timestamp,
    source_reading_path: sourcePath,
    model_version: MODEL_VERSION,
  };
}

function buildInsufficientDataResult(data, sourcePath) {
  return {
    prediction_status: "insufficient_data",
    class_code: null,
    class_label: null,
    threshold_status: null,
    insight: "A complete, valid set of four water-quality readings was not available; no classification was generated.",
    recommendation: "Wait for the next complete sensor-history record. Check the sensor connection if readings continue to be missing.",
    sensor_trends: null,
    source_recorded_at: data.recorded_at || null,
    source_reading_path: sourcePath,
    model_version: MODEL_VERSION,
  };
}

// ──────────────────────────────────────────────
// Cloud Function trigger
// ──────────────────────────────────────────────

exports.classifyWaterQuality = functions
  .region("asia-southeast1")
  .firestore.document(
    "tanks/{tankId}/sensor_readings_history/{dateKey}/entries/{entryId}",
  )
  .onCreate(async (snapshot, context) => {
    const { tankId, dateKey, entryId } = context.params;
    const data = snapshot.data() || {};
    const sourcePath = snapshot.ref.path;

    // 1. Fetch recent readings for trend analysis and forward-fill recovery
    const tankRef = db.collection("tanks").doc(tankId);
    const latestRef = tankRef.collection("water_quality_classification").doc("latest");

    const [recentReadings, latestSnapshot] = await Promise.all([
      fetchRecentReadings(tankId, dateKey, entryId, data.recorded_at),
      latestRef.get(),
    ]);

    // Graceful forward-fill for transient missing DO if other 3 sensors are valid
    if (typeof data.dissolved_oxygen !== "number" || !Number.isFinite(data.dissolved_oxygen)) {
      const lastWithDO = [...recentReadings].reverse().find(
        (r) => typeof r.dissolved_oxygen === "number" && Number.isFinite(r.dissolved_oxygen),
      );
      if (
        lastWithDO &&
        typeof data.temperature === "number" &&
        typeof data.ph_level === "number" &&
        typeof data.turbidity === "number"
      ) {
        data.dissolved_oxygen = lastWithDO.dissolved_oxygen;
      }
    }

    // 2. Validate sensor data
    const values = readFeatures(data);
    if (!values) {
      const result = buildInsufficientDataResult(data, sourcePath);
      await saveResult(tankId, dateKey, entryId, result);
      functions.logger.info("Water-quality classification: insufficient data", { tankId, dateKey, entryId });
      return null;
    }

    // 3. 100% Machine Learning prediction: Random Forest classifies Critical, Poor, and Good directly
    const range = rangeAnalysis(values);
    const prediction = predictClass(values);

    // Include current reading at the end for trend analysis
    const allReadings = [...recentReadings, data];
    const prevResult = latestSnapshot.exists ? (latestSnapshot.data() || null) : null;

    // 4. Run trend analysis
    let sensorTrends = null;
    if (allReadings.length >= MIN_SAMPLES) {
      const trendResult = analyzeTrends(allReadings, prevResult);
      sensorTrends = trendResult.trends;
    }

    // 4b. Water level mini-trend (bumababa = shallow na, pataas = narefill)
    // Water_level value DECREASES as water evaporates/drops → "falling" = water getting shallower
    let waterLevelTrend = null;
    const wlSamples = allReadings
      .filter((r) => typeof r.water_level === "number" && Number.isFinite(r.water_level))
      .map((r) => r.water_level);
    if (wlSamples.length >= 3) {
      const first = wlSamples[0];
      const last = wlSamples[wlSamples.length - 1];
      const change = last - first; // negative = falling = shallower; positive = rising = refilled
      const absChange = Math.abs(change);
      waterLevelTrend = {
        current: last,
        change: change,
        // Threshold: flag if dropped more than 0.3 cm across the sample window
        direction: change < -0.3 ? "falling" : change > 0.3 ? "rising" : "stable",
        sampleCount: wlSamples.length,
        absChangeCm: absChange,
      };
    }

    // 5. Build full prediction with trends
    const result = buildPrediction(data, values, range, prediction, sourcePath, sensorTrends, prevResult, waterLevelTrend);

    // 6. Save to Firestore
    await saveResult(tankId, dateKey, entryId, result, latestSnapshot);

    functions.logger.info("Water-quality classification saved", {
      tankId,
      dateKey,
      entryId,
      predictionStatus: result.prediction_status,
      classLabel: result.class_label,
      hasTrends: sensorTrends !== null,
      modelVersion: MODEL_VERSION,
    });
    return null;
  });
