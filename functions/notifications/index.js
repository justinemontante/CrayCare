const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.database();          // RTDB — ESP32 sensor & feeder data
const firestoreDb = admin.firestore(); // Firestore — user data & notifications

const SENSOR_MAP = {
  temperature: "temp",
  phLevel: "ph",
  dissolvedOxygen: "do",
  turbidity: "turb",
  waterLevel: "waterlevel",
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

// ─── Helper: resolve notification target UID (monitors → owner) ────────
async function getNotificationTargetUid(uid) {
  try {
    const userSnap = await firestoreDb.collection("users").doc(uid).get();
    const userData = userSnap.data() || {};
    const role = userData.role || "";
    if (String(role).toLowerCase() === "monitor") {
      const ownerUid = userData.ownerUid;
      if (ownerUid) return ownerUid;
    }
  } catch (e) {
    functions.logger.error(`getNotificationTargetUid error for ${uid}:`, e.message);
  }
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

// ─── Helper: send FCM push to a user ──────────────────────────────────
async function sendPush(uid, payload, prefsCheck) {
  try {
    // Check user prefs from Firestore
    const prefsSnap = await firestoreDb.collection("notifPrefs").doc(uid).get();
    const prefs = prefsSnap.data() || {};
    if (prefsCheck && prefs[prefsCheck] === false) return;

    // Read FCM token from Firestore
    const userSnap = await firestoreDb.collection("users").doc(uid).get();
    const userData = userSnap.data() || {};
    const token = userData.fcmToken;
    if (!token) return;

    const sound = prefs.sound !== false;
    const vibration = prefs.vibration !== false;

    let targetChannelId = "craycare_alerts_silent";
    if (sound && vibration) targetChannelId = "craycare_alerts_sound_vibrate";
    else if (sound) targetChannelId = "craycare_alerts_sound_only";
    else if (vibration) targetChannelId = "craycare_alerts_vibrate_only";

    await admin.messaging().send({
      token,
      notification: payload.notification,
      data: { ...payload.data, sound: String(sound), vibration: String(vibration) },
      android: {
        priority: "high",
        notification: { channelId: targetChannelId, priority: "high" },
      },
    });

    functions.logger.log(`Push sent to ${uid}: ${payload.notification.title}`);
  } catch (err) {
    if (
      err.code === "messaging/invalid-registration-token" ||
      err.code === "messaging/registration-token-not-registered"
    ) {
      // Remove stale FCM token from Firestore
      try {
        await firestoreDb.collection("users").doc(uid).update({
          fcmToken: admin.firestore.FieldValue.delete(),
        });
      } catch (_) {}
    } else {
      functions.logger.error(`Push failed for ${uid}:`, err.message);
    }
  }
}

// ─── Helper: write notification to Firestore ──────────────────────────
async function writeNotification(targetUid, notif) {
  const docRef = firestoreDb.collection("notifications").doc();
  await docRef.set({
    uid: targetUid,
    ...notif,
    timestamp: Date.now(),
    readBy: {},
  });
}

// ─── Helper: save a marker in Firestore ───────────────────────────────
async function saveMarker(uid, key, value) {
  try {
    await firestoreDb.collection("notifMarkers").doc(`${uid}_${key}`).set({
      uid,
      markerKey: key,
      value,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    functions.logger.error(`saveMarker error for ${uid}/${key}:`, e.message);
  }
}

// ─── Helper: read a marker from Firestore ─────────────────────────────
async function readMarker(uid, key) {
  try {
    const snap = await firestoreDb.collection("notifMarkers").doc(`${uid}_${key}`).get();
    if (snap.exists) {
      return snap.data() || null;
    }
  } catch (e) {
    functions.logger.error(`readMarker error for ${uid}/${key}:`, e.message);
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════
//  1. SENSOR ALERT — triggered on every write to RTDB sensor_readings/latest
// ═══════════════════════════════════════════════════════════════════════
exports.onSensorUpdate = functions.region("asia-southeast1").database
  .ref("sensor_readings/latest")
  .onWrite(async (change, context) => {
    const afterData = change.after.val();
    const beforeData = change.before.val();
    if (!afterData) return;

    try {
      // Read thresholds from Firestore config/default/ranges
      // (written by the Flutter app via DatabaseService.saveSensorThresholds)
      const configSnap = await firestoreDb.collection("config").doc("default").get();
      const config = configSnap.data();
      if (!config) return;

      const ranges = config.ranges;
      if (!ranges) return;

      const stateChanges = [];

      for (const [espKey, svcKey] of Object.entries(SENSOR_MAP)) {
        const newVal = afterData[espKey];
        const oldVal = beforeData ? beforeData[espKey] : null;
        const range = ranges[svcKey];
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

      const uids = await getAuthorizedUids();

      // Write to Firestore (once per unique owner target)
      const uniqueTargets = new Set();
      await Promise.all(
        uids.map(async (uid) => {
          const target = await getNotificationTargetUid(uid);
          uniqueTargets.add(target);
        })
      );

      await Promise.all(
        Array.from(uniqueTargets).map(async (targetUid) => {
          await writeNotification(targetUid, notifPayload);
        })
      );

      // Send FCM push
      await Promise.allSettled(
        uids.map(async (uid) => {
          const prefsSnap = await firestoreDb.collection("notifPrefs").doc(uid).get();
          const prefs = prefsSnap.data() || {};
          if (prefs.critical === false) return;

          const userSnap = await firestoreDb.collection("users").doc(uid).get();
          const userData = userSnap.data() || {};
          const token = userData.fcmToken;
          if (!token) return;

          const sound = prefs.sound !== false;
          const vibration = prefs.vibration !== false;

          let targetChannelId = "craycare_alerts_silent";
          if (sound && vibration) targetChannelId = "craycare_alerts_sound_vibrate";
          else if (sound) targetChannelId = "craycare_alerts_sound_only";
          else if (vibration) targetChannelId = "craycare_alerts_vibrate_only";

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
              await firestoreDb
                .collection("users")
                .doc(uid)
                .update({ fcmToken: admin.firestore.FieldValue.delete() });
            }
          }
        })
      );

      functions.logger.log(
        `Sensor update: ${stateChanges.length} change(s), ${uids.length} user(s) notified`
      );
    } catch (e) {
      functions.logger.error("onSensorUpdate error:", e.message);
    }
  });

// ═══════════════════════════════════════════════════════════════════════
//  2. FEEDING + PRE-ARM — scheduled every 1 minute
// ═══════════════════════════════════════════════════════════════════════
exports.processFeeding = functions.region("asia-southeast1").pubsub
  .schedule("every 1 minutes")
  .onRun(async (context) => {
    try {
      const now = new Date();
      const manilaNow = new Date(now.getTime() + MANILA_OFFSET_MS);
      const todayKey = `${manilaNow.getUTCMonth() + 1}/${manilaNow.getUTCDate()}`;
      const yr = manilaNow.getUTCFullYear();
      const mo = String(manilaNow.getUTCMonth() + 1).padStart(2, "0");
      const dy = String(manilaNow.getUTCDate()).padStart(2, "0");

      // Read feeder schedules from RTDB (ESP writes here)
      const schedSnap = await db.ref("feeder/schedules").once("value");
      if (!schedSnap.exists()) return;
      const schedData = schedSnap.val();

      for (const [key, s] of Object.entries(schedData)) {
        if (!s || s.enabled !== true) continue;

        const time = s.time || "6:00";
        const ampm = s.ampm || "AM";
        let h = parseInt(time.split(":")[0]);
        const m = parseInt(time.split(":")[1]);
        if (ampm === "PM" && h !== 12) h += 12;
        if (ampm === "AM" && h === 12) h = 0;

        const scheduleDate = new Date(
          Date.UTC(manilaNow.getUTCFullYear(), manilaNow.getUTCMonth(), manilaNow.getUTCDate(), h, m)
        );

        const uids = await getAuthorizedUids();
        if (uids.length === 0) continue;

        // ── Pre-arm (T-12m to T-5m) ──
        const twelveMinBefore = new Date(scheduleDate.getTime() - 12 * 60 * 1000);
        const fiveMinBefore = new Date(scheduleDate.getTime() - 5 * 60 * 1000);
        if (manilaNow >= twelveMinBefore && manilaNow < fiveMinBefore) {
          const hhmm = `${String(h).padStart(2, "0")}${String(m).padStart(2, "0")}`;
          const preArmKey = `prearm_${yr}-${mo}-${dy}_${hhmm}`;
          const scheduleEpoch = scheduleDate.getTime() - MANILA_OFFSET_MS;

          await Promise.allSettled(
            uids.map(async (uid) => {
              const userSnap = await firestoreDb.collection("users").doc(uid).get();
              const userData = userSnap.data() || {};
              const token = userData.fcmToken;
              if (!token) return;

              const prefsSnap = await firestoreDb.collection("notifPrefs").doc(uid).get();
              const prefs = prefsSnap.data() || {};
              if (prefs.feeding === false) return;

              const marker = await readMarker(uid, preArmKey);
              if (marker) return;

              try {
                await admin.messaging().send({
                  token,
                  data: {
                    type: "pre_arm",
                    scheduleTime: time,
                    scheduleAmPm: ampm,
                    scheduleEpoch: String(scheduleEpoch),
                  },
                  android: { priority: "high" },
                });
                await saveMarker(uid, preArmKey, Date.now());
                functions.logger.log(`[Pre-arm] Sent to ${uid} for ${time} ${ampm}`);
              } catch (err) {
                if (
                  err.code === "messaging/invalid-registration-token" ||
                  err.code === "messaging/registration-token-not-registered"
                ) {
                  await firestoreDb
                    .collection("users")
                    .doc(uid)
                    .update({ fcmToken: admin.firestore.FieldValue.delete() });
                }
              }
            })
          );
        }

        // ── Feeding reminder (T-5m to T) ──
        if (manilaNow >= fiveMinBefore && manilaNow < scheduleDate) {
          const hhmm = `${String(h).padStart(2, "0")}${String(m).padStart(2, "0")}`;
          const reminderKey = `reminder_${yr}-${mo}-${dy}_${hhmm}`;
          const msg = `Your feeding schedule at ${time} ${ampm} will be dispensed in 5 minutes.`;
          const scheduleEpoch = scheduleDate.getTime() - MANILA_OFFSET_MS;
          const reminderTimestamp = scheduleEpoch - 5 * 60 * 1000;

          const uniqueTargets = new Set();
          await Promise.all(
            uids.map(async (uid) => {
              const target = await getNotificationTargetUid(uid);
              uniqueTargets.add(target);
            })
          );

          let workerWroteMarker = false;
          await Promise.all(
            Array.from(uniqueTargets).map(async (targetUid) => {
              const marker = await readMarker(targetUid, reminderKey);
              if (marker) return;
              await writeNotification(targetUid, {
                type: "reminder",
                title: "Feeding Reminder",
                message: msg,
                timestamp: reminderTimestamp,
              });
              await saveMarker(targetUid, reminderKey, Date.now());
              workerWroteMarker = true;
            })
          );

          if (workerWroteMarker) {
            await Promise.allSettled(
              uids.map(async (uid) => {
                await sendPush(uid, {
                  notification: { title: "Feeding Reminder", body: msg },
                  data: { feeding: "true" },
                }, "feeding");
              })
            );
          }
        }
      }

      // ── Feeding Complete confirmation ──
      const dispSnap = await db.ref(`feeder/dispatched/${todayKey}`).once("value");
      if (dispSnap.exists()) {
        const dispatched = dispSnap.val();
        const confirmUids = await getAuthorizedUids();
        if (confirmUids.length > 0) {
          for (const [schedKey] of Object.entries(dispatched)) {
            const s2Snap = await db.ref(`feeder/schedules/${schedKey}`).once("value");
            const s2 = s2Snap.val();
            if (!s2 || s2.enabled !== true) continue;

            const time2 = s2.time || "6:00";
            const ampm2 = s2.ampm || "AM";
            let h2 = parseInt(time2.split(":")[0]);
            const m2 = parseInt(time2.split(":")[1]);
            if (ampm2 === "PM" && h2 !== 12) h2 += 12;
            if (ampm2 === "AM" && h2 === 12) h2 = 0;
            const hhmm2 = `${String(h2).padStart(2, "0")}${String(m2).padStart(2, "0")}`;
            const confirmKey = `confirm_${yr}-${mo}-${dy}_${hhmm2}`;
            const msg2 = `Scheduled feed at ${time2} ${ampm2} has been dispensed.`;

            const uniqueTargets = new Set();
            await Promise.all(
              confirmUids.map(async (uid) => {
                const target = await getNotificationTargetUid(uid);
                uniqueTargets.add(target);
              })
            );

            let confirmWroteMarker = false;
            await Promise.all(
              Array.from(uniqueTargets).map(async (targetUid) => {
                const marker = await readMarker(targetUid, confirmKey);
                if (marker) return;
                await writeNotification(targetUid, {
                  type: "reminder",
                  title: "Feeding Complete",
                  message: msg2,
                });
                await saveMarker(targetUid, confirmKey, Date.now());
                confirmWroteMarker = true;
              })
            );

            if (confirmWroteMarker) {
              await Promise.allSettled(
                confirmUids.map(async (uid) => {
                  await sendPush(uid, {
                    notification: { title: "Feeding Complete", body: msg2 },
                    data: { feeding: "true" },
                  }, "feeding");
                })
              );
            }
          }
        }
      }
    } catch (e) {
      functions.logger.error("processFeeding error:", e.message);
    }
  });

// ═══════════════════════════════════════════════════════════════════════
//  3. SAMPLING REMINDER (crayfish only) — scheduled every 1 minute
// ═══════════════════════════════════════════════════════════════════════
exports.processSampling = functions.region("asia-southeast1").pubsub
  .schedule("every 1 minutes")
  .onRun(async (context) => {
    try {
      const uids = await getAuthorizedUids();
      if (uids.length === 0) return;

      const uniqueTargets = new Set();
      await Promise.all(
        uids.map(async (uid) => {
          const target = await getNotificationTargetUid(uid);
          uniqueTargets.add(target);
        })
      );

      // Check each target for crayfish sampling due
      await Promise.all(
        Array.from(uniqueTargets).map(async (targetUid) => {
          const due = await getSamplingDue(targetUid);
          if (due) {
            await writeSamplingNotification(targetUid, due.daysSince);
          }
        })
      );

      // Send FCM pushes
      await Promise.allSettled(
        uids.map(async (uid) => {
          try {
            const notifTarget = await getNotificationTargetUid(uid);
            await sendSamplingPush(uid, notifTarget);
          } catch (err) {
            functions.logger.error(`Sampling push failed for ${uid}:`, err.message);
          }
        })
      );
    } catch (e) {
      functions.logger.error("processSampling error:", e.message);
    }
  });

// ─── Sampling Helper: check if crayfish sampling is due ───────────────
async function getSamplingDue(notifTarget) {
  const now = Date.now();
  let lastSampleTs = null;

  try {
    const snap = await firestoreDb
      .collection("production")
      .doc(notifTarget)
      .collection("crayfish")
      .doc("config")
      .get();
    if (!snap.exists) return null;
    const config = snap.data() || {};
    if (!config.isInitialized) return null;
    lastSampleTs = config.lastSampleDate || config.stockingDate;
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
