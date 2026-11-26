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
  timestampMillis,
  MIN_SAMPLES,
} = require("./trend_analyzer");
const { insightFor } = require("./insights");
const { recommendationFor } = require("./recommendations");
const { fetchRecentReadings, fetchExtendedReadings, saveResult } = require("./firestore_records");
const { notificationEventId, deliverNotificationOnce } = require("../notifications/notification_delivery");

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

async function notifyMlClassificationChange(tankId, entryId, prevResult, result) {
  if (!result || result.prediction_status !== "classified") return;

  const prevLabel =
    prevResult && prevResult.prediction_status === "classified"
      ? prevResult.class_label
      : null;
  const newLabel = result.class_label;

  const isAlert =
    prevLabel !== newLabel && (newLabel === "Poor" || newLabel === "Critical");
  const isRecovery =
    prevLabel !== newLabel &&
    (prevLabel === "Poor" || prevLabel === "Critical") &&
    newLabel === "Optimal";

  if (!isAlert && !isRecovery) return;

  // Alert Hysteresis / Notification Fatigue Mitigation:
  // Critical alerts always fire immediately; non-Critical transitions (Poor / Optimal recovery)
  // respect a 30-minute cooldown to avoid boundary-oscillation spam.
  if (newLabel !== "Critical" && prevResult && prevResult.source_recorded_at) {
    const prevMs = timestampMillis(prevResult.source_recorded_at);
    const currMs = timestampMillis(result.source_recorded_at);
    if (prevMs !== null && currMs !== null && Math.abs(currMs - prevMs) < 30 * 60 * 1000) {
      return;
    }
  }

  const tankSnap = await db.collection("tanks").doc(tankId).get();
  const ownerUid = tankSnap.exists ? (tankSnap.data() || {}).owner_uid : null;
  if (!ownerUid) return;

  const alertType =
    newLabel === "Critical"
      ? "critical"
      : newLabel === "Poor"
        ? "warning"
        : "operational";

  const title =
    newLabel === "Critical"
      ? "ML Water Quality: Critical"
      : newLabel === "Poor"
        ? "ML Water Quality: Poor"
        : "ML Water Quality: Optimal";

  const insightSummary = String(result.insight || "").replace(/\s+/g, " ").trim();
  const recSummary = String(result.recommendation || "").replace(/\s+/g, " ").trim();
  const body = recSummary ? `${insightSummary} Action: ${recSummary}` : insightSummary;
  const pushBody = body.length > 220 ? `${body.slice(0, 217)}...` : body;

  await deliverNotificationOnce({
    db,
    id: notificationEventId("wqc_ml", tankId, entryId),
    uid: ownerUid,
    type: alertType,
    title,
    body,
    timestamp: () => admin.firestore.FieldValue.serverTimestamp(),
    send: async () => {
      const userSnap = await db.collection("users").doc(ownerUid).get();
      const tokens = userSnap.exists && Array.isArray((userSnap.data() || {}).fcm_tokens)
        ? userSnap.data().fcm_tokens.filter(Boolean)
        : [];
      if (tokens.length === 0) return;

      const channelId = alertType === "critical" ? "craycare_alerts_critical" : "craycare_alerts";
      await admin.messaging().sendEachForMulticast({
        tokens,
        notification: { title, body: pushBody },
        android: {
          priority: "high",
          notification: { channelId, priority: "high" },
        },
        data: {
          title,
          body: pushBody,
          alertType,
          critical: String(alertType === "critical"),
          warning: String(alertType === "warning"),
          operational: String(alertType === "operational"),
        },
      });
    },
  });
}

// ──────────────────────────────────────────────
// Long-term (6-hour) trend summary
// ──────────────────────────────────────────────

const LONG_TERM_MIN_CHANGE = {
  temperature: 0.5,
  ph_level: 0.2,
  dissolved_oxygen: 0.5,
  turbidity: 3.0,
};

function buildLongTermTrend(readings) {
  if (!Array.isArray(readings) || readings.length < 6) return null;

  const result = {};
  let hasAny = false;

  for (const sensor of FEATURE_NAMES) {
    const valid = readings.filter(
      (r) => r && typeof r[sensor] === "number" && Number.isFinite(r[sensor])
    );
    if (valid.length < 6) continue;

    const first = valid[0][sensor];
    const last = valid[valid.length - 1][sensor];
    const change = Number((last - first).toFixed(3));
    const minChange = LONG_TERM_MIN_CHANGE[sensor] ?? 0.5;
    const direction =
      change <= -minChange ? "falling" : change >= minChange ? "rising" : "stable";

    const firstMs = timestampMillis(valid[0].recorded_at);
    const lastMs = timestampMillis(valid[valid.length - 1].recorded_at);
    const windowMinutes =
      firstMs !== null && lastMs !== null && lastMs >= firstMs
        ? Math.round((lastMs - firstMs) / 60000)
        : null;

    result[sensor] = {
      direction,
      change,
      firstValue: first,
      latestValue: last,
      sampleCount: valid.length,
      windowMinutes,
    };
    hasAny = true;
  }

  return hasAny ? result : null;
}

// ──────────────────────────────────────────────
// Build prediction (with trend awareness)
// ──────────────────────────────────────────────

function buildPrediction(data, values, range, prediction, sourcePath, sensorTrends, prevResult, waterLevelTrend = null, waterLevelThresholds = null, longTermTrend = null) {
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
    insight: insightFor(
      prediction,
      rangeClass,
      values,
      perSensorClasses,
      sensorTrends,
      typeof data.water_level === "number" ? data.water_level : null,
      waterLevelTrend,
      waterLevelThresholds,
      timestamp,
      longTermTrend
    ),
    recommendation: recommendationFor(
      prediction,
      rangeClass,
      values,
      perSensorClasses,
      sensorTrends,
      typeof data.water_level === "number" ? data.water_level : null,
      waterLevelTrend,
      waterLevelThresholds,
      timestamp,
      longTermTrend
    ),
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

    const [recentReadings, extendedReadings, latestSnapshot, waterLevelDoc] = await Promise.all([
      fetchRecentReadings(tankId, dateKey, entryId, data.recorded_at),
      fetchExtendedReadings(tankId, dateKey, entryId, data.recorded_at),
      latestRef.get(),
      tankRef.collection("sensors").doc("waterlevel").get(),
    ]);

    let waterLevelThresholds = null;
    if (waterLevelDoc.exists) {
      const wlData = waterLevelDoc.data() || {};
      const low = Number(wlData.low_value ?? wlData.min_value);
      const critical = Number(wlData.critical_value);
      waterLevelThresholds = {
        low: Number.isFinite(low) && low > 0 ? low : 5.0,
        critical: Number.isFinite(critical) && critical >= 0 ? critical : 3.0,
      };
    }

    // Graceful forward-fill for transient missing DO if other 3 sensors are valid and DO is fresh (<= 60 min)
    if (typeof data.dissolved_oxygen !== "number" || !Number.isFinite(data.dissolved_oxygen)) {
      const currentMs = timestampMillis(data.recorded_at);
      const lastWithDO = [...recentReadings].reverse().find((r) => {
        if (typeof r.dissolved_oxygen !== "number" || !Number.isFinite(r.dissolved_oxygen)) {
          return false;
        }
        if (currentMs !== null) {
          const rMs = timestampMillis(r.recorded_at);
          if (rMs !== null) {
            const ageMinutes = Math.abs(currentMs - rMs) / 60000;
            return ageMinutes <= 60;
          }
        }
        return false;
      });

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

    // 4c. Extended 6-hour long-term trend layer
    const allExtendedReadings = [...extendedReadings, data];
    const longTermTrend = buildLongTermTrend(allExtendedReadings);

    // 5. Build full prediction with trends
    const result = buildPrediction(data, values, range, prediction, sourcePath, sensorTrends, prevResult, waterLevelTrend, waterLevelThresholds, longTermTrend);

    // 6. Save to Firestore
    await saveResult(tankId, dateKey, entryId, result, latestSnapshot);

    // 7. Notify farmer on ML classification state transitions (Poor/Critical/Recovery)
    try {
      await notifyMlClassificationChange(tankId, entryId, prevResult, result);
    } catch (notifyErr) {
      functions.logger.warn("ML classification notification failed", {
        tankId,
        entryId,
        error: notifyErr && notifyErr.message ? notifyErr.message : String(notifyErr),
      });
    }

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
