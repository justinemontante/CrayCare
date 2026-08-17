// firebase-functions v7 removed the v1 API from the package root. This file
// still uses the v1 style (functions.region(...).firestore/pubsub), so import
// it from the v1 subpath explicitly. v1 remains supported through the 2026
// Node 20 deprecation window and is the smallest safe change.
const functions = require("firebase-functions/v1");
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

// Warning zone: a sensor value within this fraction of the valid range's edge
// (but not past the threshold) is reported as a WARNING instead of CRITICAL.
// The per-user "Warning Alerts" preference gates these pushes.
const WARNING_MARGIN_FRACTION = 0.1;

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

// Epoch-ms threshold for a "trusted" ESP capture time (2020-01-01). The ESP
// only sends captured_at_ms after its NTP clock is synced (guarded in
// firmware), so anything below this is treated as unsynced -> server time.
const TRUSTED_EPOCH_MS = 1577836800000;

function normalizeSensorReading(raw) {
  // Accept the present ESP payload during migration, but write only the final
  // thesis/app schema into tanks/{tankId}/... .
  const reading = {
    // Live snapshot fields (5-sec latest) — legacy names kept for the
    // dashboard + backward compatibility with old history entries.
    temperature: raw.temperature ?? null,
    ph_level: raw.ph_level ?? raw.phLevel ?? null,
    dissolved_oxygen: raw.dissolved_oxygen ?? raw.dissolvedOxygen ?? null,
    turbidity: raw.turbidity ?? null,
    water_level: raw.water_level ?? raw.waterLevelPercent ?? raw.waterLevel ?? null,
    // Turbidity sensor out-of-water flag: the ESP sets this when the probe
    // reads "air" (true). The Flutter app uses it to block feeding and to
    // disable the feeder control. Previously dropped here, so the safety
    // interlock silently never fired.
    turbidity_air: raw.turbidity_air ?? raw.turbidityAir ?? null,

    // 10-min window aggregates (min → max → avg per sensor). These match
    // the ML training schema (temp_min/temp_max/temp_avg, pH_*, DO_*,
    // turbidity_*, waterLevel_*) and the app analytics _historyKeyMap.
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

    // Offline-backfill support: keep the ORIGINAL capture time so buffered
    // readings land in the right date folder with their true timestamp.
    // Live 5-sec payloads have no captured_at_ms -> serverTimestamp() (same
    // behaviour as before).
    recorded_at: (() => {
      const capMs = Number(raw.captured_at_ms);
      if (Number.isFinite(capMs) && capMs > TRUSTED_EPOCH_MS) {
        return new Date(capMs);
      }
      return admin.firestore.FieldValue.serverTimestamp();
    })(),
  };
  // Pass the pending-backlog count through to the app (for the "Syncing N
  // offline readings…" indicator). Only include it when present.
  if (typeof raw.buffered_entries === "number" && Number.isFinite(raw.buffered_entries)) {
    reading.buffered_entries = raw.buffered_entries;
  }
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
    // A latest reading is a complete snapshot. Replace rather than merge so a
    // sensor omitted/disabled by firmware cannot leave an old value looking fresh.
    await firestoreDb.collection("tanks").doc(owner.tankId)
      .collection("sensor_readings").doc("latest")
      .set(normalizeSensorReading(change.after.data()));
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
    // Date partition = the reading's ORIGINAL capture time (Manila), so
    // offline-buffered backfill lands in the correct day folder.
    const capMs = Number(snap.data().captured_at_ms);
    const recorded =
      Number.isFinite(capMs) && capMs > TRUSTED_EPOCH_MS ? new Date(capMs) : new Date();
    const manilaTime = new Date(recorded.getTime() + MANILA_OFFSET_MS);
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

        // Warning zone: within WARNING_MARGIN_FRACTION of the range edge —
        // approaching the threshold but not past it yet.
        const span =
          range.min != null && range.max != null ? range.max - range.min : 0;
        const margin = span > 0 ? span * WARNING_MARGIN_FRACTION : 0;
        const warnLow = range.min != null ? range.min + margin : null;
        const warnHigh = range.max != null ? range.max - margin : null;

        const isWarning =
          !isCritical &&
          ((warnLow != null && newVal >= range.min && newVal < warnLow) ||
            (warnHigh != null && newVal <= range.max && newVal > warnHigh));

        const wasWarning =
          oldVal != null &&
          ((warnLow != null && oldVal >= range.min && oldVal < warnLow) ||
            (warnHigh != null && oldVal <= range.max && oldVal > warnHigh));

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
        } else if (isWarning && !wasWarning && !wasCritical) {
          // Entering the warning zone from normal — alert once (no spam).
          let dir, threshold;
          if (warnLow != null && newVal < warnLow) {
            dir = "low";
            threshold = range.min;
          } else {
            dir = "high";
            threshold = range.max;
          }
          stateChanges.push({ svcKey, val: newVal, threshold, dir, state: "warning" });
        } else if (!isCritical && !isWarning && (wasCritical || wasWarning)) {
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
        }
        const d =
          state === "warning"
            ? dir === "low"
              ? "is approaching minimum"
              : "is approaching maximum"
            : dir === "low"
              ? "is below minimum"
              : "is above maximum";
        return unit
          ? `${label} (${val.toFixed(1)} ${unit}) ${d} of ${threshold}`
          : `${label} (${val.toFixed(1)}) ${d} of ${threshold}`;
      });

      const hasCritical = stateChanges.some((c) => c.state === "critical");
      const hasWarning = stateChanges.some((c) => c.state === "warning");
      const alertType = hasCritical ? "critical" : hasWarning ? "warning" : "operational";
      const notifPayload = {
        type: alertType,
        title: hasCritical
          ? "Sensor Alert"
          : hasWarning
            ? "Sensor Warning"
            : "Sensor Normalized",
        message: msgLines.join("; "),
      };

      // Target the specific owner of this sensor reading
      await writeNotification(ownerUid, notifPayload);

      // Send FCM push to this owner. Respect the per-user notification toggles:
      //  - "critical" alerts  -> prefs.critical  (Sensor Alert)
      //  - "warning" alerts   -> prefs.warning   (Sensor Warning)
      //  - "operational" (resolved) -> always sent (good news / back to normal)
      try {
        const prefs = await getUserPreferences(ownerUid);
        const pushAllowed =
          alertType === "critical"
            ? prefs.critical !== false
            : alertType === "warning"
              ? prefs.warning !== false
              : true; // resolved

        if (pushAllowed) {
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
                    critical: String(hasCritical),
                    warning: String(hasWarning),
                    alertType,
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

        // Honor the same Sunday-first day-of-week mask ("1111111") the app
        // writes: index 0 = Sunday, 6 = Saturday. Without this filter the
        // 5-minute reminder fires even on days the schedule is disabled.
        let activeToday = true;
        if (typeof data.days === "string" && data.days.length >= 7) {
          const manilaDayIdx = manila.getUTCDay(); // 0=Sun..6=Sat
          activeToday = data.days.charAt(manilaDayIdx) === "1";
        }
        if (!activeToday) continue;

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

// Sampling reminders fire only at 8:00 AM and 2:00 PM (Philippine time),
// with an escalating message so the researcher is reminded early and again
// in the afternoon without spamming throughout the day.
function isSamplingReminderHour() {
  const manilaHour = new Date(Date.now() + 8 * 3600 * 1000).getUTCHours();
  return manilaHour === 8 || manilaHour === 14; // 8 AM or 2 PM Manila
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

    const isInitialized = config.is_initialized === true;
    if (!isInitialized) return null;

    const currentBatchId = config.current_batch_id || "";
    if (currentBatchId) {
      const latestSampling = await firestoreDb
        .collection("tanks").doc(tankId)
        .collection("batches").doc(currentBatchId)
        .collection("sampling_records")
        .orderBy("sampling_date", "desc")
        .limit(1)
        .get();
      if (!latestSampling.empty) {
        lastSampleTs = latestSampling.docs[0].data().sampling_date || null;
      }
    }

    lastSampleTs = lastSampleTs || config.last_sample_date || config.stocking_date;
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
  const manilaHour = new Date(Date.now() + 8 * 3600 * 1000).getUTCHours();
  const isMorning = manilaHour === 8;

  if (marker) {
    const val = marker.value;
    const lastReminderTs = typeof val === "number" ? val : 0;
    if (lastReminderTs > 0) {
      // Only one reminder per window (morning OR afternoon) per day.
      const hoursSince = (Date.now() - lastReminderTs) / (1000 * 60 * 60);
      if (hoursSince < 5) return false;
      // If the last reminder was within the same day, skip the second window.
      const lastDay = new Date(lastReminderTs + 8 * 3600 * 1000).getUTCDate();
      const today = new Date(Date.now() + 8 * 3600 * 1000).getUTCDate();
      const lastMonth = new Date(lastReminderTs + 8 * 3600 * 1000).getUTCMonth();
      const thisMonth = new Date(Date.now() + 8 * 3600 * 1000).getUTCMonth();
      if (lastMonth === thisMonth && lastDay === today) return false;
    }
  }

  let title = "Crayfish Sampling Reminder";
  let msg;
  if (daysSince === 7) {
    msg = isMorning
      ? "It's been 7 days since your last sampling. Time to record today's growth data!"
      : "Sampling due today — record your weekly growth data before the day ends!";
  } else {
    const overdue = daysSince - 7;
    msg = `⚠️ Sampling OVERDUE by ${overdue} day${overdue > 1 ? "s" : ""} — please record growth data as soon as possible!`;
    if (overdue > 1) title = "Sampling Overdue";
  }

  await writeNotification(targetUid, {
    type: "reminder",
    title,
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
