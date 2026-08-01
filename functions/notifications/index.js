const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const firestoreDb = admin.firestore(); // Firestore — user data & notifications

// Final Firestore sensor field -> internal alert key.
const SENSOR_MAP = {
  temperature: "temp",
  ph_level: "ph",
  dissolved_oxygen: "do",
  turbidity: "turb",
  water_level: "waterlevel",
};

const LABELS = {
  temp: "Temperature",
  ph: "pH Level",
  do: "Dissolved Oxygen",
  turb: "Turbidity",
  waterlevel: "Water Level",
};

const UNITS = {
  temp: "°C",
  ph: "",
  do: "mg/L",
  turb: "NTU",
  waterlevel: "cm",
};

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;

// ─── Multi-device token helpers ────────────────────────────────────────
// Returns all FCM tokens for a user — supports both the new `fcmTokens`
// array (one entry per logged-in device) and the legacy `fcmToken` string
// so older client versions keep working during the migration window.
function getTokensFromUserData(userData) {
  const tokens = [];
  if (Array.isArray(userData.fcmTokens)) {
    tokens.push(...userData.fcmTokens.filter(Boolean));
  }
  if (userData.fcmToken && typeof userData.fcmToken === "string") {
    if (!tokens.includes(userData.fcmToken)) tokens.push(userData.fcmToken);
  }
  return tokens;
}

// Canonical paths used by the Flutter app and Firestore rules.
async function getUserPreferences(uid) {
  const snap = await firestoreDb.collection("users").doc(uid)
    .collection("notification_settings").doc("preferences").get();
  return snap.exists ? (snap.data() || {}) : {};
}

async function getUserTokens(uid) {
  const tokens = [];
  const userSnap = await firestoreDb.collection("users").doc(uid).get();
  if (userSnap.exists) tokens.push(...getTokensFromUserData(userSnap.data() || {}));
  const tokenSnap = await firestoreDb.collection("users").doc(uid).collection("fcm_tokens").get();
  tokenSnap.forEach((doc) => {
    const token = doc.data().token;
    if (typeof token === "string" && token && !tokens.includes(token)) tokens.push(token);
  });
  return tokens;
}

// Removes one stale/invalid token from the user's token array.
async function removeStaleToken(uid, token) {
  try {
    await firestoreDb.collection("users").doc(uid).update({
      fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
    });
  } catch (_) {}
}

// ─── Helper: resolve notification target UID ───────────────────────────
// (No redirect logic anymore — every account is its own notification
// target now that the 'monitor' role has been removed.)
async function getNotificationTargetUid(uid) {
  return uid;
}

// ─── Helper: get all authorized (non-admin) UIDs ───────────────────────
async function getAuthorizedUids() {
  let uids = [];

  try {
    const authSnap = await firestoreDb.collection("system").doc("authorizedOperators").get();
    const authVal = authSnap.data();

    if (!authVal) {
      // No authorized operators doc — treat all non-admin users as authorized
      const usersSnap = await firestoreDb.collection("users").get();
      usersSnap.forEach((doc) => {
        const role = doc.data().role || "";
        if (String(role).toLowerCase() !== "admin") {
          uids.push(doc.id);
        }
      });
    } else {
      // Support both { UID: "uid1,uid2,..." } and { uid: true, ... } formats
      if (authVal.UID && typeof authVal.UID === "string") {
        uids = authVal.UID.split(",").map((u) => u.trim()).filter(Boolean);
      } else {
        for (const [key, val] of Object.entries(authVal)) {
          if (val === true) uids.push(key);
        }
      }

      // Filter out admins
      const filteredUids = [];
      await Promise.all(
        uids.map(async (uid) => {
          try {
            const userSnap = await firestoreDb.collection("users").doc(uid).get();
            const role = (userSnap.data() || {}).role || "";
            if (String(role).toLowerCase() !== "admin") {
              filteredUids.push(uid);
            }
          } catch (_) {
            filteredUids.push(uid);
          }
        })
      );
      uids = filteredUids;
    }
  } catch (e) {
    functions.logger.error("getAuthorizedUids error:", e.message);
  }

  return uids;
}

// ─── Helper: send FCM push to a user (all logged-in devices) ──────────
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

    await Promise.allSettled(
      tokens.map(async (token) => {
        try {
          await admin.messaging().send({
            token,
            notification: payload.notification,
            data: { ...payload.data, sound: String(sound), vibration: String(vibration) },
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
      })
    );

    functions.logger.log(`Push sent to ${uid} (${tokens.length} device(s)): ${payload.notification.title}`);
  } catch (err) {
    functions.logger.error(`Push failed for ${uid}:`, err.message);
  }
}

// ─── Helper: write notification to Firestore ──────────────────────────
async function writeNotification(targetUid, notif) {
  // Canonical notification schema consumed by NotificationService.
  await firestoreDb.collection("notifications").doc().set({
    uid: targetUid,
    notif_type: notif.notif_type || notif.type || "general",
    title: notif.title || "CrayCare",
    body: notif.body || notif.message || "",
    is_read: false,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
  });
}

// ─── Helper: save a marker in Firestore ───────────────────────────────
async function saveMarker(uid, key, value) {
  try {
    await firestoreDb.collection("users").doc(uid).collection("notif_markers").doc(key).set({
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
    const snap = await firestoreDb.collection("users").doc(uid).collection("notif_markers").doc(key).get();
    return snap.exists ? (snap.data() || null) : null;
  } catch (e) {
    functions.logger.error(`readMarker error for ${uid}/${key}:`, e.message);
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
//  0. HARDWARE OWNERSHIP ROUTING
//
//  There is ONE hardware package. The ESP32 writes to a fixed path:
//    sensorIngestion/current              (latest — patched every 5 s)
//    sensorIngestion/current/history/*    (history — created every 10 min)
//
//  These two Cloud Functions trigger on those writes, look up the current
//  owner via hardware_system/currentOwner { uid }, and copy into:
//    tanks/{tankId}/sensor_readings/latest
//    tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{id}
//
//  Reassignment: admin updates hardware_system/currentOwner to a new uid.
//  From that moment ALL new readings go to the new owner.
//  Previous data stays permanently in the old owner's paths — nothing is
//  ever moved or deleted. The ESP firmware never needs to be reflashed.
// ═══════════════════════════════════════════════════════════════════════

// ─── Hardware ownership routing ───────────────────────────────────────
// The ESP always writes only to the private ingestion paths.  Functions use
// hardware_system/currentOwner to resolve the assigned tank, so an ESP never
// needs a user UID and changing the assignment takes effect immediately.
async function getCurrentHardwareOwner() {
  const snap = await firestoreDb.collection("hardware_system").doc("currentOwner").get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  if (!data.uid || !data.tank_id) return null;
  return { uid: data.uid, tankId: data.tank_id };
}

function normalizeSensorReading(raw) {
  // Accept the present ESP payload during migration, but write only the final
  // thesis/app schema into tanks/{tankId}/... .
  const reading = {
    temperature: raw.temperature ?? null,
    ph_level: raw.ph_level ?? raw.phLevel ?? null,
    dissolved_oxygen: raw.dissolved_oxygen ?? raw.dissolvedOxygen ?? null,
    turbidity: raw.turbidity ?? null,
    water_level: raw.water_level ?? raw.waterLevelPercent ?? raw.waterLevel ?? null,
    recorded_at: admin.firestore.FieldValue.serverTimestamp(),
  };
  return Object.fromEntries(Object.entries(reading).filter(([, value]) => value !== null));
}

// Latest ESP upload (every 5 seconds) -> active tank's canonical latest doc.
exports.onSensorIngestionWrite = functions.region("asia-southeast1").firestore
  .document("sensorIngestion/current")
  .onWrite(async (change) => {
    if (!change.after.exists) return null;
    const owner = await getCurrentHardwareOwner();
    if (!owner) {
      functions.logger.warn("[Ingestion] No hardware owner/tank assigned; latest reading not routed.");
      return null;
    }
    await firestoreDb.collection("tanks").doc(owner.tankId)
      .collection("sensor_readings").doc("latest")
      .set(normalizeSensorReading(change.after.data()), { merge: true });
    functions.logger.log(`[Ingestion] Latest routed -> tanks/${owner.tankId}/sensor_readings/latest`);
    return null;
  });

// Historical ESP upload -> canonical tank history path.
exports.onSensorIngestionHistoryCreate = functions.region("asia-southeast1").firestore
  .document("sensorIngestion/current/history/{docId}")
  .onCreate(async (snap, context) => {
    const owner = await getCurrentHardwareOwner();
    if (!owner) {
      functions.logger.warn("[Ingestion] No hardware owner/tank assigned; history reading not routed.");
      return null;
    }
    const manilaTime = new Date(Date.now() + MANILA_OFFSET_MS);
    const dateKey = [manilaTime.getUTCFullYear(), String(manilaTime.getUTCMonth() + 1).padStart(2, "0"), String(manilaTime.getUTCDate()).padStart(2, "0")].join("-");
    await firestoreDb.collection("tanks").doc(owner.tankId)
      .collection("sensor_readings_history").doc(dateKey)
      .collection("entries").doc(context.params.docId)
      .set(normalizeSensorReading(snap.data()));
    functions.logger.log(`[Ingestion] History routed -> tanks/${owner.tankId}/sensor_readings_history/${dateKey}/entries/${context.params.docId}`);
    return null;
  });

// ═══════════════════════════════════════════════════════════════════════
//  1. SENSOR ALERT — triggered on every write to tanks/{tankId}/sensor_readings/latest
// ═══════════════════════════════════════════════════════════════════════
exports.onSensorUpdate = functions.region("asia-southeast1").firestore
  .document("tanks/{tankId}/sensor_readings/latest")
  .onWrite(async (change, context) => {
    const afterData = change.after.exists ? change.after.data() : null;
    const beforeData = change.before.exists ? change.before.data() : null;
    if (!afterData) return;

    const { tankId } = context.params;

    try {
      const tankSnap = await firestoreDb.collection("tanks").doc(tankId).get();
      const ownerUid = tankSnap.exists ? tankSnap.data().owner_uid : null;
      if (!ownerUid) return;

      // Thresholds use the canonical per-tank sensor documents.
      const thresholds = {};
      const sensorsSnap = await firestoreDb.collection("tanks").doc(tankId).collection("sensors").get();
      sensorsSnap.forEach((doc) => {
        const data = doc.data();
        thresholds[doc.id] = { min: data.min_value, max: data.max_value };
      });

      const stateChanges = [];

      for (const [espKey, svcKey] of Object.entries(SENSOR_MAP)) {
        const newVal = afterData[espKey];
        const oldVal = beforeData ? beforeData[espKey] : null;
        const range = thresholds[espKey];
        if (newVal == null || !range) continue;

        const isCritical =
          (range.min != null && newVal < range.min) ||
          (range.max != null && newVal > range.max);

        const wasCritical =
          oldVal != null &&
          ((range.min != null && oldVal < range.min) ||
            (range.max != null && oldVal > range.max));

        if (isCritical && !wasCritical) {
          let dir, threshold;
          if (range.min != null && newVal < range.min) {
            dir = "low";
            threshold = range.min;
          } else {
            dir = "high";
            threshold = range.max;
          }
          stateChanges.push({ svcKey, val: newVal, threshold, dir, state: "critical" });
        } else if (!isCritical && wasCritical) {
          stateChanges.push({ svcKey, val: newVal, state: "resolved" });
        }
      }

      if (stateChanges.length === 0) return;

      const msgLines = stateChanges.map(({ svcKey, val, threshold, dir, state }) => {
        const label = LABELS[svcKey] || svcKey;
        const unit = UNITS[svcKey] || "";
        if (state === "resolved") {
          return unit
            ? `${label} is back to normal (${val.toFixed(1)} ${unit})`
            : `${label} is back to normal (${val.toFixed(1)})`;
        } else {
          const d = dir === "low" ? "below minimum" : "above maximum";
          return unit
            ? `${label} (${val.toFixed(1)} ${unit}) is ${d} of ${threshold}`
            : `${label} (${val.toFixed(1)}) is ${d} of ${threshold}`;
        }
      });

      const notifPayload = {
        type: stateChanges.some((c) => c.state === "critical") ? "critical" : "operational",
        title: stateChanges.some((c) => c.state === "critical") ? "Sensor Alert" : "Sensor Normalized",
        message: msgLines.join("; "),
      };

      // Target the specific owner of this sensor reading
      await writeNotification(ownerUid, notifPayload);

      // Send FCM push to this owner
      try {
        const prefs = await getUserPreferences(ownerUid);
        if (prefs.critical !== false) {
          const tokens = await getUserTokens(ownerUid);

          const sound = prefs.sound !== false;
          const vibration = prefs.vibration !== false;

          let targetChannelId = "craycare_alerts_silent";
          if (sound && vibration) targetChannelId = "craycare_alerts_sound_vibrate";
          else if (sound) targetChannelId = "craycare_alerts_sound_only";
          else if (vibration) targetChannelId = "craycare_alerts_vibrate_only";

          await Promise.allSettled(
            tokens.map(async (token) => {
              try {
                await admin.messaging().send({
                  token,
                  notification: { title: notifPayload.title, body: msgLines.join("\n") },
                  data: {
                    title: notifPayload.title,
                    body: msgLines.join("\n"),
                    sound: String(sound),
                    vibration: String(vibration),
                    critical: String(true),
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
                  await removeStaleToken(ownerUid, token);
                }
              }
            })
          );
        }
      } catch (err) {
        functions.logger.error("FCM send error:", err.message);
      }

      functions.logger.log(
        `Sensor update: ${stateChanges.length} change(s), owner ${ownerUid} notified`
      );
    } catch (e) {
      functions.logger.error("onSensorUpdate error:", e.message);
    }
  });

// ═══════════════════════════════════════════════════════════════════════
//  2. FEEDING + PRE-ARM — scheduled every 1 minute
// ═══════════════════════════════════════════════════════════════════════
// The project has one ESP. Scheduling follows the tank currently assigned to it.
exports.processFeeding = functions.region("asia-southeast1").pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    try {
      const owner = await getCurrentHardwareOwner();
      if (!owner) return null;

      const now = new Date();
      const manila = new Date(now.getTime() + MANILA_OFFSET_MS);
      const dateKey = `${manila.getUTCFullYear()}-${String(manila.getUTCMonth() + 1).padStart(2, "0")}-${String(manila.getUTCDate()).padStart(2, "0")}`;
      const minuteOfDay = manila.getUTCHours() * 60 + manila.getUTCMinutes();
      const tankRef = firestoreDb.collection("tanks").doc(owner.tankId);
      const schedules = await tankRef.collection("feeder_schedules").get();
      const prefs = await getUserPreferences(owner.uid);

      for (const schedule of schedules.docs) {
        const data = schedule.data();
        if (data.enabled === false || data.is_active === false) continue;
        const timeValue = typeof data.timeValue === "number" ? data.timeValue : null;
        if (timeValue === null) continue;
        const markerKey = `feed_${dateKey}_${schedule.id}`;
        const marker = await readMarker(owner.uid, markerKey);
        if (marker) continue;

        // Reminder five minutes before the configured schedule.
        if (minuteOfDay === timeValue - 5 && prefs.feeding !== false) {
          const time = data.time || data.feed_time || "";
          const ampm = data.ampm || "";
          const body = `Your feeding schedule at ${time} ${ampm} will be dispensed in 5 minutes.`;
          await writeNotification(owner.uid, { type: "feeder", title: "Feeding Reminder", message: body });
          await sendPush(owner.uid, { notification: { title: "Feeding Reminder", body }, data: { feeding: "true" } }, "feeding");
          await saveMarker(owner.uid, markerKey, Date.now());
        }
      }
      return null;
    } catch (e) {
      functions.logger.error("processFeeding error:", e.message);
      return null;
    }
  });

exports.processSampling = functions.region("asia-southeast1").pubsub
  .schedule("every 1 minutes")
  .onRun(async () => {
    try {
      const owner = await getCurrentHardwareOwner();
      if (!owner) return null;
      const due = await getSamplingDue(owner.uid);
      if (!due) return null;
      const wrote = await writeSamplingNotification(owner.uid, due.daysSince);
      if (wrote) await sendSamplingPush(owner.uid, owner.uid);
      return null;
    } catch (e) {
      functions.logger.error("processSampling error:", e.message);
      return null;
    }
  });

// ─── Sampling Helper: check if crayfish sampling is due ───────────────
async function getSamplingDue(notifTarget) {
  const now = Date.now();
  let lastSampleTs = null;

  try {
    const profile = await firestoreDb.collection("users").doc(notifTarget).get();
    const tankId = profile.exists ? (profile.data() || {}).tank_id : null;
    if (!tankId) return null;

    const snap = await firestoreDb.collection("tanks").doc(tankId).get();
    if (!snap.exists) return null;
    const config = snap.data() || {};

    const isInitialized = config.isInitialized === true || config.is_initialized === true;
    if (!isInitialized) return null;

    const currentBatchId = config.currentBatchId || config.current_batch_id || "";
    if (currentBatchId) {
      const latestSampling = await firestoreDb
        .collection("tanks").doc(tankId)
        .collection("batches").doc(currentBatchId)
        .collection("sampling_records")
        .orderBy("date", "desc")
        .limit(1)
        .get();
      if (!latestSampling.empty) {
        lastSampleTs = latestSampling.docs[0].data().date || null;
      }
    }

    lastSampleTs = lastSampleTs || config.lastSampleDate || config.last_sample_date || config.stockingDate || config.stocking_date;
  } catch (e) {
    functions.logger.error(`getSamplingDue error for ${notifTarget}:`, e.message);
    return null;
  }

  if (!lastSampleTs) return null;
  const daysSince = Math.floor((now - lastSampleTs) / (1000 * 60 * 60 * 24));
  if (daysSince < 7) return null;

  return { daysSince, lastSampleTs };
}

// ─── Sampling Helper: write DB notification ───────────────────────────
async function writeSamplingNotification(targetUid, daysSince) {
  const markerKey = "sampling_reminder_crayfish";
  const marker = await readMarker(targetUid, markerKey);
  if (marker) {
    const val = marker.value;
    const lastReminderTs = typeof val === "number" ? val : 0;
    if (lastReminderTs > 0) {
      const daysSinceReminder = Math.floor((Date.now() - lastReminderTs) / (1000 * 60 * 60 * 24));
      if (daysSinceReminder < 7) return false;
    }
  }

  const msg = `It's been ${daysSince} days since last Crayfish sampling. Time to record growth data!`;

  await writeNotification(targetUid, {
    type: "reminder",
    title: "Crayfish Sampling Reminder",
    message: msg,
  });

  await saveMarker(targetUid, markerKey, Date.now());
  functions.logger.log(`Crayfish sampling reminder written for owner: ${targetUid}`);
  return true;
}

// ─── Sampling Helper: send FCM push ───────────────────────────────────
async function sendSamplingPush(uid, notifTarget) {
  const markerKey = "sampling_reminder_crayfish";
  const marker = await readMarker(notifTarget, markerKey);
  if (!marker) return;
  const markerVal = marker.value;
  if (typeof markerVal === "number" && Date.now() - markerVal > 120000) return;

  const due = await getSamplingDue(notifTarget);
  if (!due) return;

  const msg = `It's been ${due.daysSince} days since last Crayfish sampling. Time to record growth data!`;

  await sendPush(uid, {
    notification: { title: "Crayfish Sampling Reminder", body: msg },
    data: { sampling: "true" },
  }, "sampling");
}
