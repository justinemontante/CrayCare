"use strict";

const admin = require("firebase-admin");
const db = admin.firestore();

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.abs(value) < 100000000000 ? Math.round(value * 1000) : value;
  }
  if (typeof value === "string") {
    const numeric = Number(value);
    if (Number.isFinite(numeric)) return timestampMillis(numeric);
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function previousDateKey(dateKey, daysBefore) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey);
  if (!match) return null;
  const date = new Date(Date.UTC(
    Number(match[1]), Number(match[2]) - 1, Number(match[3]) - daysBefore,
  ));
  return [date.getUTCFullYear(), String(date.getUTCMonth() + 1).padStart(2, "0"),
    String(date.getUTCDate()).padStart(2, "0")].join("-");
}

// ──────────────────────────────────────────────
// Fetch recent readings for trend analysis
// ──────────────────────────────────────────────

async function fetchRecentReadings(tankId, dateKey, currentEntryId, currentRecordedAt) {
  const cutoffMillis = timestampMillis(currentRecordedAt);
  if (cutoffMillis === null) return [];

  const readings = [];
  const maxPreviousReadings = 9;
  const maxDaysToSearch = 4;
  const tankRef = db.collection("tanks").doc(tankId);

  // Search backward by the date folders used by sensor_readings_history. The
  // current reading is supplied separately by the classifier, so collect only
  // earlier records and allow the history window to cross midnight.
  for (let dayOffset = 0; dayOffset < maxDaysToSearch &&
      readings.length < maxPreviousReadings; dayOffset++) {
    const folderDate = previousDateKey(dateKey, dayOffset);
    if (!folderDate) break;

    let entriesRef = tankRef
      .collection("sensor_readings_history").doc(folderDate)
      .collection("entries");
    if (dayOffset === 0) {
      entriesRef = entriesRef.where("recorded_at", "<", new Date(cutoffMillis));
    }

    const remaining = maxPreviousReadings - readings.length;
    const snapshot = await entriesRef
      .orderBy("recorded_at", "desc")
      .limit(remaining)
      .get();

    snapshot.forEach((doc) => {
      if (doc.id === currentEntryId) return;
      const data = doc.data();
      const recordedMillis = timestampMillis(data && data.recorded_at);
      if (data && recordedMillis !== null && recordedMillis < cutoffMillis) {
        readings.push(data);
      }
    });
  }

  return readings
    .sort((a, b) => timestampMillis(a.recorded_at) - timestampMillis(b.recorded_at))
    .slice(-maxPreviousReadings);
}

async function saveResult(tankId, dateKey, entryId, result, existingLatestSnapshot) {
  const tankRef = db.collection("tanks").doc(tankId);
  const latestRef = tankRef.collection("water_quality_classification").doc("latest");
  const historyRef = tankRef.collection("water_quality_classification_history")
    .doc(dateKey).collection("entries").doc(entryId);

  await db.runTransaction(async (transaction) => {
    const historySnapshot = await transaction.get(historyRef);
    let latestSnapshot = existingLatestSnapshot;
    if (!latestSnapshot) {
      latestSnapshot = await transaction.get(latestRef);
    }

    const writeData = {
      ...result,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    if (!historySnapshot.exists) transaction.create(historyRef, writeData);

    const sourceMillis = timestampMillis(result.source_recorded_at);
    const latestMillis = latestSnapshot.exists
      ? timestampMillis((latestSnapshot.data() || {}).source_recorded_at)
      : null;
    if (sourceMillis !== null && (latestMillis === null || sourceMillis >= latestMillis)) {
      transaction.set(latestRef, writeData);
    }
  });
}

module.exports = { fetchRecentReadings, saveResult };
