const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

// main.js loads index.js first, so the shared Admin app is already initialized.
const firestoreDb = admin.firestore();
const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

const DAILY_SENSORS = [
  { avg: "temp_avg", min: "temp_min", max: "temp_max", sum: "temp_sum", count: "temp_count" },
  { avg: "pH_avg", min: "pH_min", max: "pH_max", sum: "pH_sum", count: "pH_count" },
  { avg: "DO_avg", min: "DO_min", max: "DO_max", sum: "DO_sum", count: "DO_count" },
  { avg: "turbidity_avg", min: "turbidity_min", max: "turbidity_max", sum: "turbidity_sum", count: "turbidity_count" },
  { avg: "waterLevel_avg", min: "waterLevel_min", max: "waterLevel_max", sum: "waterLevel_sum", count: "waterLevel_count" },
];

function finiteNumber(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function manilaDateKey(date) {
  const manila = new Date(date.getTime() + MANILA_OFFSET_MS);
  return [
    manila.getUTCFullYear(),
    String(manila.getUTCMonth() + 1).padStart(2, "0"),
    String(manila.getUTCDate()).padStart(2, "0"),
  ].join("-");
}

function previousManilaDateKey(daysAgo) {
  return manilaDateKey(new Date(Date.now() - daysAgo * 24 * 60 * 60 * 1000));
}

function addReadingToSummary(current, reading, entryId, dateKey) {
  const processed = Array.isArray(current.processed_entry_ids)
    ? current.processed_entry_ids
    : [];
  if (processed.includes(entryId)) return null;

  const update = {
    summary_version: 1,
    summary_complete: false,
    date_key: dateKey,
    sample_count: (finiteNumber(current.sample_count) || 0) + 1,
    processed_entry_ids: [...processed, entryId],
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  for (const sensor of DAILY_SENSORS) {
    const avg = finiteNumber(reading[sensor.avg]);
    if (avg === null) continue;

    const oldSum = finiteNumber(current[sensor.sum]) || 0;
    const oldCount = finiteNumber(current[sensor.count]) || 0;
    const nextSum = oldSum + avg;
    const nextCount = oldCount + 1;
    update[sensor.sum] = nextSum;
    update[sensor.count] = nextCount;
    update[sensor.avg] = nextSum / nextCount;

    const entryMin = finiteNumber(reading[sensor.min]) ?? avg;
    const entryMax = finiteNumber(reading[sensor.max]) ?? avg;
    const oldMin = finiteNumber(current[sensor.min]);
    const oldMax = finiteNumber(current[sensor.max]);
    update[sensor.min] = oldMin === null ? entryMin : Math.min(oldMin, entryMin);
    update[sensor.max] = oldMax === null ? entryMax : Math.max(oldMax, entryMax);
  }

  return update;
}

function buildCompleteSummary(entryDocs, dateKey) {
  const summary = {
    summary_version: 1,
    summary_complete: true,
    date_key: dateKey,
    sample_count: entryDocs.length,
    processed_entry_ids: entryDocs.map((doc) => doc.id),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  for (const sensor of DAILY_SENSORS) {
    let sum = 0;
    let count = 0;
    let minValue = null;
    let maxValue = null;

    for (const doc of entryDocs) {
      const reading = doc.data() || {};
      const avg = finiteNumber(reading[sensor.avg]);
      if (avg === null) continue;

      const entryMin = finiteNumber(reading[sensor.min]) ?? avg;
      const entryMax = finiteNumber(reading[sensor.max]) ?? avg;
      sum += avg;
      count += 1;
      minValue = minValue === null ? entryMin : Math.min(minValue, entryMin);
      maxValue = maxValue === null ? entryMax : Math.max(maxValue, entryMax);
    }

    if (count > 0) {
      summary[sensor.sum] = sum;
      summary[sensor.count] = count;
      summary[sensor.avg] = sum / count;
      summary[sensor.min] = minValue;
      summary[sensor.max] = maxValue;
    }
  }

  return summary;
}

async function rebuildCompletedDay(tankId, dateKey) {
  const dayRef = firestoreDb.collection("tanks").doc(tankId)
    .collection("sensor_readings_history").doc(dateKey);

  const daySnap = await dayRef.get();
  if (daySnap.exists && (daySnap.data() || {}).summary_complete === true) {
    return false;
  }

  const entries = await dayRef.collection("entries").get();
  if (entries.empty) return false;

  await dayRef.set(buildCompleteSummary(entries.docs, dateKey), { merge: true });
  return true;
}

// Every canonical 10-minute history entry incrementally maintains its parent
// day document. The processed-entry list makes retries idempotent.
exports.onSensorHistoryDailySummary = functions.region("asia-southeast1").firestore
  .document("tanks/{tankId}/sensor_readings_history/{dateKey}/entries/{entryId}")
  .onCreate(async (snap, context) => {
    const { tankId, dateKey, entryId } = context.params;
    const dayRef = firestoreDb.collection("tanks").doc(tankId)
      .collection("sensor_readings_history").doc(dateKey);

    await firestoreDb.runTransaction(async (transaction) => {
      const daySnap = await transaction.get(dayRef);
      const current = daySnap.exists ? (daySnap.data() || {}) : {};
      const update = addReadingToSummary(current, snap.data() || {}, entryId, dateKey);
      if (update) transaction.set(dayRef, update, { merge: true });
    });
    return null;
  });

// Backfill the last 30 completed Manila calendar days. This runs hourly, but
// completed summaries are skipped, so after the one-time catch-up it normally
// costs only the lightweight parent-document checks. Today is intentionally
// excluded; its live summary stays incremental and Analytics can use raw
// 10-minute entries for the current partial day.
exports.backfillRecentSensorDailySummaries = functions.region("asia-southeast1").pubsub
  .schedule("every 1 hours")
  .onRun(async () => {
    try {
      const ownerSnap = await firestoreDb.collection("hardware_system").doc("currentOwner").get();
      if (!ownerSnap.exists) return null;
      const owner = ownerSnap.data() || {};
      const tankId = typeof owner.tank_id === "string" ? owner.tank_id : "";
      if (!tankId) return null;

      const dateKeys = Array.from({ length: 30 }, (_, i) => previousManilaDateKey(i + 1));
      let rebuilt = 0;
      const chunkSize = 6;
      for (let i = 0; i < dateKeys.length; i += chunkSize) {
        const chunk = dateKeys.slice(i, i + chunkSize);
        const results = await Promise.all(chunk.map((dateKey) => rebuildCompletedDay(tankId, dateKey)));
        rebuilt += results.filter(Boolean).length;
      }

      if (rebuilt > 0) {
        functions.logger.log(`[DailySummary] Backfilled ${rebuilt} completed day(s) for tank ${tankId}`);
      }
      return null;
    } catch (error) {
      functions.logger.error("[DailySummary] Backfill failed:", error.message);
      return null;
    }
  });
