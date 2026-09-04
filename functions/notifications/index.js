const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
admin.initializeApp();

const firestoreDb = admin.firestore();
const {sensorRouteDecision} = require('./sensor_routing');

const SENSOR_MAP = {
  temperature: "temp",
  ph_level: "ph",
  dissolved_oxygen: "do",
  turbidity: "turb",
  water_level: "waterlevel",
  feed_level: "feedlevel",
};

const LABELS = {
  temp: "Temperature",
  ph: "pH Level",
  do: "Dissolved Oxygen",
  turb: "Turbidity",
  waterlevel: "Water Level",
  feedlevel: "Feed Level",
};

const UNITS = {
  temp: "°C",
  ph: "",
  do: "mg/L",
  turb: "NTU",
  waterlevel: "cm",
  feedlevel: "%",
};

const WARNING_MARGIN_FRACTION = 0.1;
const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
const TRUSTED_EPOCH_MS = 1577836800000;

function getTokensFromUserData(userData) {
  const tokens = [];
  if (Array.isArray(userData.fcmTokens)) {
    tokens.push(...userData.fcmTokens.filter(Boolean));
  }
  const legacyToken = typeof userData.fcmToken === "string"
    ? userData.fcmToken.trim()
    : "";
  if (legacyToken && !tokens.includes(legacyToken)) tokens.push(legacyToken);
  return tokens;
}

async function getUserPreferences(uid) {
  const snap = await firestoreDb.collection("users").doc(uid)
    .collection("notification_settings").doc("preferences").get();
  return snap.exists ? (snap.data() || {}) : {};
}

async function getUserTokens(uid) {
  const snap = await firestoreDb.collection("users").doc(uid).get();
  return snap.exists ? getTokensFromUserData(snap.data() || {}) : [];
}

async function removeStaleToken(uid, token) {
  try {
    const userRef = firestoreDb.collection("users").doc(uid);
    const userSnap = await userRef.get();
    const updates = {
      fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
    };
    if (userSnap.exists && (userSnap.data() || {}).fcmToken === token) {
      updates.fcmToken = admin.firestore.FieldValue.delete();
    }
    await userRef.update(updates);
  } catch (_) {}
}

async function sendPush(uid, payload, prefsCheck) {
  try {
    const prefs = await getUserPreferences(uid);
    if (prefsCheck && prefs[prefsCheck] === false) return;

    const tokens = await getUserTokens(uid);
    if (tokens.length === 0) return;

    const sound = prefs.sound !== false;
    const vibration = prefs.vibration !== false;
    let targetChannelId = "craycare_alerts_silent";
    if (sound && vibration) targetChannelId = "craycare_alerts_sound_vibrate";
    else if (sound) targetChannelId = "craycare_alerts_sound_only";
    else if (vibration) targetChannelId = "craycare_alerts_vibrate_only";

    await Promise.allSettled(tokens.map(async (token) => {
      try {
        await admin.messaging().send({
          token,
          notification: payload.notification,
          data: {
            ...payload.data,
            sound: String(sound),
            vibration: String(vibration),
          },
          android: {
            priority: "high",
            notification: { channelId: targetChannelId, priority: "high" },
          },
        });
      } catch (err) {
        if (
          err.code === "messaging/invalid-registration-token" ||
          err.code === "messaging/registration-token-not-registered"
        ) {
          await removeStaleToken(uid, token);
        } else {
          throw err;
        }
      }
    }));
  } catch (err) {
    functions.logger.error(`Push failed for ${uid}:`, err.message);
  }
}

async function writeNotification(targetUid, notif) {
  const collectionRef = firestoreDb.collection("notifications");
  const docRef = notif.docId ? collectionRef.doc(notif.docId) : collectionRef.doc();
  await docRef.set({
    uid: targetUid,
    notif_type: notif.notif_type || notif.type || "general",
    title: notif.title || "CrayCare",
    body: notif.body || notif.message || "",
    is_read: false,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function saveMarker(uid, key, value) {
  try {
    await firestoreDb.collection("users").doc(uid)
      .collection("notif_markers").doc(key).set({
        markerKey: key,
        value,
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
      });
  } catch (e) {
    functions.logger.error(`saveMarker error for ${uid}/${key}:`, e.message);
  }
}

async function readMarker(uid, key) {
  try {
    const snap = await firestoreDb.collection("users").doc(uid)
      .collection("notif_markers").doc(key).get();
    return snap.exists ? (snap.data() || null) : null;
  } catch (e) {
    functions.logger.error(`readMarker error for ${uid}/${key}:`, e.message);
    return null;
  }
}

async function getCurrentHardwareOwner() {
  const snap = await firestoreDb.collection("hardware_system").doc("currentOwner").get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  if (!data.uid || !data.tank_id) return null;
  const assignedAt = data.assigned_at || snap.updateTime;
  const assignedAtMs = assignedAt && typeof assignedAt.toMillis === 'function' ? Math.floor(assignedAt.toMillis()) : NaN;
  return { uid: data.uid, tankId: data.tank_id, assignedAtMs };
}

function normalizeSensorReading(raw) {
  const reading = {
    temperature: raw.temperature ?? null,
    ph_level: raw.ph_level ?? raw.phLevel ?? null,
    dissolved_oxygen: raw.dissolved_oxygen ?? raw.dissolvedOxygen ?? null,
    turbidity: raw.turbidity ?? null,
    water_level: raw.water_level ?? raw.waterLevelPercent ?? raw.waterLevel ?? null,
    feed_level: raw.feed_level ?? raw.feedLevel ?? null,
    estimated_feed_grams: raw.estimated_feed_grams ?? raw.estimatedFeedGrams ?? null,
    turbidity_air: raw.turbidity_air ?? raw.turbidityAir ?? null,
    temp_min: raw.temp_min ?? null,
    temp_max: raw.temp_max ?? null,
    temp_avg: raw.temp_avg ?? null,
    pH_min: raw.pH_min ?? null,
    pH_max: raw.pH_max ?? null,
    pH_avg: raw.pH_avg ?? null,
    DO_min: raw.DO_min ?? null,
    DO_max: raw.DO_max ?? null,
    DO_avg: raw.DO_avg ?? null,
    turbidity_min: raw.turbidity_min ?? null,
    turbidity_max: raw.turbidity_max ?? null,
    turbidity_avg: raw.turbidity_avg ?? null,
    waterLevel_min: raw.waterLevel_min ?? null,
    waterLevel_max: raw.waterLevel_max ?? null,
    waterLevel_avg: raw.waterLevel_avg ?? null,
    recorded_at: (() => {
      const capMs = Number(raw.captured_at_ms);
      return Number.isFinite(capMs) && capMs > TRUSTED_EPOCH_MS
        ? new Date(capMs)
        : admin.firestore.FieldValue.serverTimestamp();
    })(),
  };
  if (typeof raw.buffered_entries === "number" && Number.isFinite(raw.buffered_entries)) {
    reading.buffered_entries = raw.buffered_entries;
  }
  return Object.fromEntries(Object.entries(reading).filter(([, value]) => value !== null));
}

function sensorState(value, range) {
  if (!Number.isFinite(Number(value)) || !range) return { state: "unknown" };
  const val = Number(value);
  const min = Number(range.min);
  const max = Number(range.max);
  if (!Number.isFinite(min) || !Number.isFinite(max) || min >= max) {
    return { state: "unknown" };
  }
  if (val < min) return { state: "critical", dir: "low", threshold: min };
  if (val > max) return { state: "critical", dir: "high", threshold: max };

  const margin = (max - min) * WARNING_MARGIN_FRACTION;
  if (val >= min && val < min + margin) {
    return { state: "warning", dir: "low", threshold: min };
  }
  if (val <= max && val > max - margin) {
    return { state: "warning", dir: "high", threshold: max };
  }
  return { state: "normal" };
}

function feedLevelState(value, range) {
  const val = Number(value);
  const low = Number(range && range.min);
  const critical = Number(range && range.critical);
  if (!Number.isFinite(val) || !Number.isFinite(low) || !Number.isFinite(critical)) {
    return { state: "unknown" };
  }
  if (val <= 0) return { state: "critical", dir: "empty", threshold: 0 };
  if (val <= critical) return { state: "critical", dir: "low", threshold: critical };
  if (val <= low) return { state: "warning", dir: "low", threshold: low };
  return { state: "normal" };
}

function stateForSensor(sensorName, value, range) {
  return sensorName === "feed_level"
    ? feedLevelState(value, range)
    : sensorState(value, range);
}

function stateSignature(state) {
  return `${state.state}:${state.dir || ""}`;
}

function sensorMessage(change) {
  const label = LABELS[change.svcKey] || change.svcKey;
  const unit = UNITS[change.svcKey] || "";
  const suffix = unit ? ` ${unit}` : "";
  if (change.svcKey === "feedlevel") {
    if (change.state === "resolved") {
      return `Feed level is back to normal (${change.val.toFixed(0)}%)`;
    }
    if (change.dir === "empty") {
      return "Feed hopper is empty. Refill before the next feeding.";
    }
    if (change.state === "critical") {
      return `Feed level is critically low at ${change.val.toFixed(0)}%. Refill the feeder soon.`;
    }
    return `Feed level is low at ${change.val.toFixed(0)}%. Consider refilling soon.`;
  }
  if (change.state === "resolved") {
    return `${label} is back to normal (${change.val.toFixed(1)}${suffix})`;
  }
  const description = change.state === "warning"
    ? (change.dir === "low" ? "is approaching minimum" : "is approaching maximum")
    : (change.dir === "low" ? "is below minimum" : "is above maximum");
  return `${label} (${change.val.toFixed(1)}${suffix}) ${description} of ${change.threshold}`;
}

async function notifySensorChanges(ownerUid, stateChanges) {
  if (!ownerUid || stateChanges.length === 0) return;
  const lines = stateChanges.map(sensorMessage);
  const hasCritical = stateChanges.some((c) => c.state === "critical");
  const hasWarning = stateChanges.some((c) => c.state === "warning");
  const alertType = hasCritical ? "critical" : hasWarning ? "warning" : "operational";
  const title = hasCritical
    ? "Sensor Alert"
    : hasWarning
      ? "Sensor Warning"
      : "Sensor Normalized";
  const bodyForDb = lines.join("; ");
  const bodyForPush = lines.join("\n");

  await writeNotification(ownerUid, {
    type: alertType,
    title,
    message: bodyForDb,
  });

  const prefsCheck = alertType === "critical"
    ? "critical"
    : alertType === "warning"
      ? "warning"
      : "operational";
  await sendPush(ownerUid, {
    notification: { title, body: bodyForPush },
    data: {
      title,
      body: bodyForPush,
      critical: String(hasCritical),
      warning: String(hasWarning),
      operational: String(alertType === "operational"),
      alertType,
    },
  }, prefsCheck);
}

exports.onSensorIngestionWrite = functions.region("asia-southeast1").firestore
  .document("sensorIngestion/current")
  .onWrite(async (change) => {
    if (!change.after.exists) return null;
    const owner = await getCurrentHardwareOwner();
    const raw = change.after.data();
    const route = sensorRouteDecision(raw, owner);
    if (!route.tankId) {
      functions.logger.warn('Latest sensor reading not routed:', route.reason);
      return null;
    }
    const latest = firestoreDb.collection("tanks").doc(route.tankId)
      .collection("sensor_readings").doc("latest");
    await firestoreDb.runTransaction(async tx => {
      const previous = await tx.get(latest);
      const recorded = previous.exists ? previous.data().recorded_at : null;
      if (recorded && typeof recorded.toMillis === 'function' && recorded.toMillis() > route.capturedAtMs) return;
      tx.set(latest, normalizeSensorReading(raw));
    });
    return null;
  });

exports.onSensorIngestionHistoryCreate = functions.region("asia-southeast1").firestore
  .document("sensorIngestion/current/history/{docId}")
  .onCreate(async (snap, context) => {
    const owner = await getCurrentHardwareOwner();
    const route = sensorRouteDecision(snap.data(), owner);
    if (!route.tankId) {
      // Keep the original staged payload; never guess who owned old readings.
      await snap.ref.set({routing_status: 'quarantined', routing_reason: route.reason}, {merge: true});
      return null;
    }
    const recorded = new Date(route.capturedAtMs);
    const manilaTime = new Date(recorded.getTime() + MANILA_OFFSET_MS);
    const dateKey = [
      manilaTime.getUTCFullYear(),
      String(manilaTime.getUTCMonth() + 1).padStart(2, "0"),
      String(manilaTime.getUTCDate()).padStart(2, "0"),
    ].join("-");
    await firestoreDb.collection("tanks").doc(route.tankId)
      .collection("sensor_readings_history").doc(dateKey)
      .collection("entries").doc(context.params.docId)
      .set(normalizeSensorReading(snap.data()));
    return null;
  });

const { TERMINAL_OUTCOMES, scheduleOutcomePatch } = require("./feeder_outcome");
const { deliverFeederNotificationOnce } = require("./feeder_delivery");

exports.onFeederLogCreate = functions.runWith({failurePolicy: true}).region("asia-southeast1").firestore
  .document("tanks/{tankId}/feeder_logs/{logId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const status = String(data.status || "").trim().toLowerCase();
    if (!TERMINAL_OUTCOMES.has(status)) return null;

    try {
      const { tankId, logId } = context.params;
      if (data.type === "auto" && typeof data.schedule_key === "string" &&
          data.schedule_key.length > 0 && !data.schedule_key.includes("/")) {
        const scheduleRef = firestoreDb.collection("tanks").doc(tankId)
          .collection("feeder_schedules").doc(data.schedule_key);
        await firestoreDb.runTransaction(async (transaction) => {
          const schedule = await transaction.get(scheduleRef);
          if (!schedule.exists) return; // Do not resurrect a deleted schedule.
          const patch = scheduleOutcomePatch(schedule.data(), data);
          if (patch) transaction.update(scheduleRef, patch);
        });
      }
      // Status reconciliation is independent of notification preferences.
      if (status !== "completed" && status !== "skipped_insufficient") return null;
      const tankSnap = await firestoreDb.collection("tanks").doc(tankId).get();
      const ownerUid = tankSnap.exists ? (tankSnap.data() || {}).owner_uid : null;
      if (!ownerUid) return null;

      const prefs = await getUserPreferences(ownerUid);
      if (prefs.feeding === false) return null;

      const requested = Number(data.requested_grams);
      const available = Number(data.estimated_available_grams);
      const requestedText = Number.isFinite(requested)
        ? `${requested.toFixed(0)} g`
        : "the scheduled amount";
      const source = String(data.type || "").toLowerCase() === "manual"
        ? "Manual feeding"
        : "Scheduled feeding";

      let title;
      let body;
      if (status === "completed") {
        title = "Feeding Completed";
        body = `${source} cycle completed (estimated ${requestedText}).`;
      } else {
        title = "Feeding Skipped";
        const availableText = Number.isFinite(available)
          ? `${available.toFixed(0)} g available`
          : "insufficient feed available";
        body = `${source} was skipped: insufficient feed (${availableText}; ${requestedText} required). Refill the hopper.`;
      }

      await deliverFeederNotificationOnce({
        db: firestoreDb, tankId, logId, uid: ownerUid,
        type: status === "completed" ? "feeding" : "warning",
        title, body,
        timestamp: () => admin.firestore.FieldValue.serverTimestamp(),
        send: () => sendPush(ownerUid, {
        notification: { title, body },
        data: {
          feeding: "true",
          feederStatus: status,
          tankId,
          logId,
        },
        }, "feeding"),
      });
    } catch (e) {
      functions.logger.error("onFeederLogCreate error:", e.message);
      throw e;
    }
    return null;
  });

exports.onSensorUpdate = functions.region("asia-southeast1").firestore
  .document("tanks/{tankId}/sensor_readings/latest")
  .onWrite(async (change, context) => {
    const afterData = change.after.exists ? change.after.data() : null;
    const beforeData = change.before.exists ? change.before.data() : null;
    if (!afterData) return null;

    try {
      const { tankId } = context.params;
      const tankSnap = await firestoreDb.collection("tanks").doc(tankId).get();
      const ownerUid = tankSnap.exists ? (tankSnap.data() || {}).owner_uid : null;
      if (!ownerUid) return null;

      const thresholds = {};
      const sensorsSnap = await firestoreDb.collection("tanks").doc(tankId)
        .collection("sensors").get();
      sensorsSnap.forEach((doc) => {
        const data = doc.data() || {};
        thresholds[doc.id] = {
          min: data.min_value,
          max: data.max_value,
          critical: data.critical_value,
        };
      });

      const stateChanges = [];
      for (const [field, svcKey] of Object.entries(SENSOR_MAP)) {
        const newVal = Number(afterData[field]);
        if (!Number.isFinite(newVal) || !thresholds[field]) continue;
        const oldRaw = beforeData ? Number(beforeData[field]) : NaN;
        const current = stateForSensor(field, newVal, thresholds[field]);
        const previous = Number.isFinite(oldRaw)
          ? stateForSensor(field, oldRaw, thresholds[field])
          : { state: "unknown" };
        if (stateSignature(current) === stateSignature(previous)) continue;
        if (current.state === "critical" || current.state === "warning") {
          stateChanges.push({
            svcKey,
            val: newVal,
            threshold: current.threshold,
            dir: current.dir,
            state: current.state,
          });
        } else if (current.state === "normal" && ["critical", "warning"].includes(previous.state)) {
          stateChanges.push({ svcKey, val: newVal, state: "resolved" });
        }
      }
      await notifySensorChanges(ownerUid, stateChanges);
    } catch (e) {
      functions.logger.error("onSensorUpdate error:", e.message);
    }
    return null;
  });

exports.onSensorThresholdUpdate = functions.region("asia-southeast1").firestore
  .document("tanks/{tankId}/sensors/{sensorName}")
  .onUpdate(async (change, context) => {
    try {
      const before = change.before.data() || {};
      const after = change.after.data() || {};
      if (
        before.min_value === after.min_value &&
        before.max_value === after.max_value &&
        before.critical_value === after.critical_value
      ) {
        return null;
      }

      const { tankId, sensorName } = context.params;
      const svcKey = SENSOR_MAP[sensorName];
      if (!svcKey) return null;

      const [tankSnap, latestSnap] = await Promise.all([
        firestoreDb.collection("tanks").doc(tankId).get(),
        firestoreDb.collection("tanks").doc(tankId)
          .collection("sensor_readings").doc("latest").get(),
      ]);
      const ownerUid = tankSnap.exists ? (tankSnap.data() || {}).owner_uid : null;
      if (!ownerUid || !latestSnap.exists) return null;

      const value = Number((latestSnap.data() || {})[sensorName]);
      if (!Number.isFinite(value)) return null;

      const previous = stateForSensor(sensorName, value, {
        min: before.min_value,
        max: before.max_value,
        critical: before.critical_value,
      });
      const current = stateForSensor(sensorName, value, {
        min: after.min_value,
        max: after.max_value,
        critical: after.critical_value,
      });
      if (stateSignature(previous) === stateSignature(current)) return null;

      const stateChanges = [];
      if (current.state === "critical" || current.state === "warning") {
        stateChanges.push({
          svcKey,
          val: value,
          threshold: current.threshold,
          dir: current.dir,
          state: current.state,
        });
      } else if (current.state === "normal" && ["critical", "warning"].includes(previous.state)) {
        stateChanges.push({ svcKey, val: value, state: "resolved" });
      }
      await notifySensorChanges(ownerUid, stateChanges);
    } catch (e) {
      functions.logger.error("onSensorThresholdUpdate error:", e.message);
    }
    return null;
  });

exports.processFeeding = functions.region("asia-southeast1").pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    try {
      const owner = await getCurrentHardwareOwner();
      if (!owner) return null;

      const now = new Date();
      const target = new Date(now.getTime() + MANILA_OFFSET_MS + 5 * 60 * 1000);
      const targetDateKey = `${target.getUTCFullYear()}-${String(target.getUTCMonth() + 1).padStart(2, "0")}-${String(target.getUTCDate()).padStart(2, "0")}`;
      const targetMinuteOfDay = target.getUTCHours() * 60 + target.getUTCMinutes();
      const targetDayIdx = target.getUTCDay();
      const tankRef = firestoreDb.collection("tanks").doc(owner.tankId);
      const schedules = await tankRef.collection("feeder_schedules").get();
      const prefs = await getUserPreferences(owner.uid);

      for (const schedule of schedules.docs) {
        const data = schedule.data() || {};
        if (data.enabled === false || data.is_active === false) continue;
        const timeValue = typeof data.timeValue === "number" ? data.timeValue : null;
        if (timeValue === null || targetMinuteOfDay !== timeValue) continue;

        if (typeof data.days === "string" && data.days.length >= 7) {
          if (data.days.charAt(targetDayIdx) !== "1") continue;
        }

        const markerKey = `feed_${targetDateKey}_${schedule.id}`;
        if (await readMarker(owner.uid, markerKey)) continue;
        if (prefs.feeding === false) continue;

        const time = data.time || data.feed_time || "";
        const ampm = data.ampm || "";
        const body = `Your feeding schedule at ${time} ${ampm} will be dispensed in 5 minutes.`;
        await writeNotification(owner.uid, {
          type: "reminder",
          title: "Feeding Reminder",
          message: body,
        });
        await sendPush(owner.uid, {
          notification: { title: "Feeding Reminder", body },
          data: { feeding: "true" },
        }, "feeding");
        await saveMarker(owner.uid, markerKey, Date.now());
      }
    } catch (e) {
      functions.logger.error("processFeeding error:", e.message);
    }
    return null;
  });

function isSamplingReminderHour() {
  const manilaHour = new Date(Date.now() + MANILA_OFFSET_MS).getUTCHours();
  return manilaHour === 8 || manilaHour === 14;
}

function sameManilaDay(aMs, bMs) {
  const a = new Date(aMs + MANILA_OFFSET_MS);
  const b = new Date(bMs + MANILA_OFFSET_MS);
  return a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate();
}

exports.processSampling = functions.region("asia-southeast1").pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    try {
      if (!isSamplingReminderHour()) return null;
      const owner = await getCurrentHardwareOwner();
      if (!owner) return null;
      const due = await getSamplingDue(owner.uid);
      if (!due) return null;
      const payload = await writeSamplingNotification(owner.uid, due.daysSince);
      if (payload) {
        await sendPush(owner.uid, {
          notification: { title: payload.title, body: payload.body },
          data: { sampling: "true" },
        }, "sampling");
      }
    } catch (e) {
      functions.logger.error("processSampling error:", e.message);
    }
    return null;
  });

async function getSamplingDue(notifTarget) {
  const now = Date.now();
  let lastSampleTs = null;
  try {
    const tankId = notifTarget;
    const tankSnap = await firestoreDb.collection("tanks").doc(tankId).get();
    if (!tankSnap.exists || (tankSnap.data() || {}).owner_uid !== notifTarget) return null;
    const config = tankSnap.data() || {};
    if (config.is_initialized !== true) return null;

    const currentBatchId = config.current_batch_id || "";
    if (currentBatchId) {
      const weekly = await firestoreDb.collection("tanks").doc(tankId)
        .collection("batches").doc(currentBatchId)
        .collection("sampling_records")
        .where("is_baseline", "==", false)
        .orderBy("sampling_date", "desc")
        .limit(1)
        .get();
      if (!weekly.empty) lastSampleTs = weekly.docs[0].data().sampling_date || null;
      else lastSampleTs = config.stocking_date || null;
    }
    if (!lastSampleTs) lastSampleTs = config.stocking_date || null;
  } catch (e) {
    functions.logger.error(`getSamplingDue error for ${notifTarget}:`, e.message);
    return null;
  }

  if (!lastSampleTs) return null;
  const anchorMs = lastSampleTs.toMillis ? lastSampleTs.toMillis() : Number(lastSampleTs);
  if (!Number.isFinite(anchorMs)) return null;
  const mn = new Date(now + MANILA_OFFSET_MS);
  const an = new Date(anchorMs + MANILA_OFFSET_MS);
  const today0 = Date.UTC(mn.getUTCFullYear(), mn.getUTCMonth(), mn.getUTCDate());
  const anchor0 = Date.UTC(an.getUTCFullYear(), an.getUTCMonth(), an.getUTCDate());
  const daysSince = Math.floor((today0 - anchor0) / 86400000);
  return daysSince >= 7 ? { daysSince, lastSampleTs } : null;
}

async function writeSamplingNotification(targetUid, daysSince) {
  const markerKey = "sampling_reminder_crayfish";
  const marker = await readMarker(targetUid, markerKey);
  const nowMs = Date.now();
  if (marker && typeof marker.value === "number" && sameManilaDay(marker.value, nowMs)) {
    return null;
  }

  const manilaHour = new Date(nowMs + MANILA_OFFSET_MS).getUTCHours();
  const isMorning = manilaHour === 8;
  let title = "Crayfish Sampling Reminder";
  let body;
  if (daysSince === 7) {
    body = isMorning
      ? "It's been 7 days since your last sampling. Time to record today's growth data!"
      : "Sampling due today — record your weekly growth data before the day ends!";
  } else {
    const overdue = daysSince - 7;
    body = `⚠️ Sampling OVERDUE by ${overdue} day${overdue > 1 ? "s" : ""} — please record growth data as soon as possible!`;
    title = "Sampling Overdue";
  }

  await writeNotification(targetUid, {
    type: "reminder",
    title,
    message: body,
  });
  await saveMarker(targetUid, markerKey, nowMs);
  return { title, body };
}

exports.onAutoActuatorLogCreate = functions.region("asia-southeast1").firestore
  .document("tanks/{tankId}/actuator_logs/{logId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const action = String(data.action || "");
    if (!action.includes("(AUTO)")) return null;

    const { tankId, logId } = context.params;
    const tankSnap = await firestoreDb.collection("tanks").doc(tankId).get();
    if (!tankSnap.exists) return null;
    const ownerUid = String((tankSnap.data() || {}).owner_uid || "").trim();
    if (!ownerUid) return null;

    const userSnap = await firestoreDb.collection("users").doc(ownerUid).get();
    const userData = userSnap.exists ? (userSnap.data() || {}) : {};
    if (String(userData.role || "owner").toLowerCase() === "admin") return null;
    if (String(userData.status || "active").toLowerCase() === "disabled") return null;

    const actuatorId = String(data.actuator_type || "");
    const labels = { aerator1: "Aerator 1", aerator2: "Aerator 2", pump: "Water Pump" };
    const label = labels[actuatorId] || actuatorId || "Actuator";
    const turnedOn = action.includes("Switched ON");
    const turnedOff = action.includes("Switched OFF");
    if (!turnedOn && !turnedOff) return null;

    const title = `${label} turned ${turnedOn ? "ON" : "OFF"}`;
    let body = action.replace(
      /^Switched (?:ON|OFF)(?:\s*\(AUTO\))?\s*[-–—]\s*[^–—-]+?\s*[-–—]\s*/,
      "",
    );
    if (body === action) {
      body = action.replace(/^Switched (?:ON|OFF)(?:\s*\(AUTO\))?\s*[-–—]\s*/, "");
    }

    await writeNotification(ownerUid, {
      docId: `actuator_${logId}`,
      type: "operational",
      title,
      message: body,
    });
    await sendPush(ownerUid, {
      notification: { title, body },
      data: { operational: "true", critical: "false" },
    }, "operational");
    return null;
  });
