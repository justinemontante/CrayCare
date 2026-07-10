const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.database();

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
  const roleSnap = await db.ref(`users/${uid}/profile/role`).once("value");
  const role = roleSnap.val();
  if (String(role).toLowerCase() === "monitor") {
    const ownerUidSnap = await db.ref(`users/${uid}/profile/ownerUid`).once("value");
    const ownerUid = ownerUidSnap.val();
    if (ownerUid) return ownerUid;
  }
  return uid;
}

// ─── Helper: get all authorized (non-admin) UIDs ───────────────────────
async function getAuthorizedUids() {
  const authSnap = await db.ref("system/authorizedOperators").once("value");
  const authVal = authSnap.val();
  let uids = [];

  if (authVal === null) {
    const usersSnap = await db.ref("users").once("value");
    if (usersSnap.exists()) {
      usersSnap.forEach((child) => {
        const userData = child.val();
        const role = userData && userData.profile && userData.profile.role;
        if (!role || String(role).toLowerCase() !== "admin") {
          uids.push(child.key);
        }
      });
    }
  } else if (typeof authVal === "object") {
    if (authVal.UID && typeof authVal.UID === "string") {
      uids = authVal.UID.split(",").map(u => u.trim()).filter(Boolean);
    } else {
      for (const [key, val] of Object.entries(authVal)) {
        if (val === true) uids.push(key);
      }
    }

    const filteredUids = [];
    await Promise.all(
      uids.map(async (uid) => {
        const roleSnap = await db.ref(`users/${uid}/profile/role`).once("value");
        const role = roleSnap.val();
        if (!role || String(role).toLowerCase() !== "admin") {
          filteredUids.push(uid);
        }
      })
    );
    uids = filteredUids;
  }

  return uids;
}

// ─── Helper: send FCM push to a user ──────────────────────────────────
async function sendPush(uid, payload, prefsCheck) {
  try {
    if (prefsCheck) {
      const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
      const prefs = prefsSnap.val() || {};
      if (prefs[prefsCheck] === false) return;
    }

    const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
    const token = tokenSnap.val();
    if (!token) return;

    const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
    const prefs = prefsSnap.val() || {};
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
    if (err.code === "messaging/invalid-registration-token" ||
        err.code === "messaging/registration-token-not-registered") {
      await db.ref(`users/${uid}/fcmToken`).remove();
    } else {
      functions.logger.error(`Push failed for ${uid}:`, err.message);
    }
  }
}

// ─── Helper: write notification to DB ─────────────────────────────────
async function writeNotification(targetUid, notif) {
  await db.ref(`users/${targetUid}/notifications`).push().set({
    ...notif,
    timestamp: Date.now(),
    unread: true,
  });
}

// ═══════════════════════════════════════════════════════════════════════
//  1. SENSOR ALERT — triggered on every write to sensor_readings/latest
// ═══════════════════════════════════════════════════════════════════════
exports.onSensorUpdate = functions.region("asia-southeast1").database
  .ref("sensor_readings/latest")
  .onWrite(async (change, context) => {
    const afterData = change.after.val();
    const beforeData = change.before.val();
    if (!afterData) return;

    try {
      const configSnap = await db.ref("sensor_readings/config").once("value");
      const config = configSnap.val();
      if (!config) return;

      const selectedStage = config.selectedStage;
      if (!selectedStage || !config[selectedStage]) return;
      const thresholds = config[selectedStage];

      const stateChanges = [];

      for (const [espKey, svcKey] of Object.entries(SENSOR_MAP)) {
        const newVal = afterData[espKey];
        const oldVal = beforeData ? beforeData[espKey] : null;
        const range = thresholds[svcKey];
        if (newVal == null || !range) continue;

        const isCritical = (range.min != null && newVal < range.min) ||
                           (range.max != null && newVal > range.max);

        const wasCritical = oldVal != null && (
          (range.min != null && oldVal < range.min) ||
          (range.max != null && oldVal > range.max)
        );

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
        // Both same state → no change, skip
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
        type: "critical",
        title: stateChanges.some(c => c.state === "critical") ? "Sensor Alert" : "Sensor Normalized",
        message: msgLines.join("; "),
      };

      const uids = await getAuthorizedUids();

      // Write to DB (once per unique owner target)
      const uniqueTargets = new Set();
      await Promise.all(uids.map(async (uid) => {
        const target = await getNotificationTargetUid(uid);
        uniqueTargets.add(target);
      }));

      await Promise.all(Array.from(uniqueTargets).map(async (targetUid) => {
        await writeNotification(targetUid, notifPayload);
      }));

      // Send FCM push
      await Promise.allSettled(uids.map(async (uid) => {
        const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
        const prefs = prefsSnap.val() || {};
        if (prefs.critical === false) return;

        const sound = prefs.sound !== false;
        const vibration = prefs.vibration !== false;

        const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
        const token = tokenSnap.val();
        if (!token) return;

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
          if (err.code === "messaging/invalid-registration-token" ||
              err.code === "messaging/registration-token-not-registered") {
            await db.ref(`users/${uid}/fcmToken`).remove();
          }
        }
      }));

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

        const scheduleDate = new Date(Date.UTC(
          manilaNow.getUTCFullYear(), manilaNow.getUTCMonth(),
          manilaNow.getUTCDate(), h, m
        ));

        const uids = await getAuthorizedUids();
        if (uids.length === 0) continue;

        // ── Pre-arm (T-12m to T-5m) ──
        const twelveMinBefore = new Date(scheduleDate.getTime() - 12 * 60 * 1000);
        const fiveMinBefore = new Date(scheduleDate.getTime() - 5 * 60 * 1000);
        if (manilaNow >= twelveMinBefore && manilaNow < fiveMinBefore) {
          const hhmm = `${String(h).padStart(2, "0")}${String(m).padStart(2, "0")}`;
          const preArmKey = `prearm_${yr}-${mo}-${dy}_${hhmm}`;
          const scheduleEpoch = scheduleDate.getTime() - MANILA_OFFSET_MS;

          await Promise.allSettled(uids.map(async (uid) => {
            const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
            const token = tokenSnap.val();
            if (!token) return;

            const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
            const prefs = prefsSnap.val() || {};
            if (prefs.feeding === false) return;

            const markerSnap = await db.ref(`users/${uid}/notifications/markers/${preArmKey}`).once("value");
            if (markerSnap.exists()) return;

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
              await db.ref(`users/${uid}/notifications/markers/${preArmKey}`).set(Date.now());
              functions.logger.log(`[Pre-arm] Sent to ${uid} for ${time} ${ampm}`);
            } catch (err) {
              if (err.code === "messaging/invalid-registration-token" ||
                  err.code === "messaging/registration-token-not-registered") {
                await db.ref(`users/${uid}/fcmToken`).remove();
              }
            }
          }));
        }

        // ── Feeding reminder (T-5m to T) ──
        if (manilaNow >= fiveMinBefore && manilaNow < scheduleDate) {
          const hhmm = `${String(h).padStart(2, "0")}${String(m).padStart(2, "0")}`;
          const reminderKey = `reminder_${yr}-${mo}-${dy}_${hhmm}`;
          const msg = `Your feeding schedule at ${time} ${ampm} will be dispensed in 5 minutes.`;
          const scheduleEpoch = scheduleDate.getTime() - MANILA_OFFSET_MS;
          const reminderTimestamp = scheduleEpoch - 5 * 60 * 1000;

          const uniqueTargets = new Set();
          await Promise.all(uids.map(async (uid) => {
            const target = await getNotificationTargetUid(uid);
            uniqueTargets.add(target);
          }));

          let workerWroteMarker = false;
          await Promise.all(Array.from(uniqueTargets).map(async (targetUid) => {
            const markerSnap = await db.ref(`users/${targetUid}/notifications/markers/${reminderKey}`).once("value");
            if (markerSnap.exists()) return;
            await writeNotification(targetUid, {
              type: "reminder",
              title: "Feeding Reminder",
              message: msg,
              timestamp: reminderTimestamp,
            });
            await db.ref(`users/${targetUid}/notifications/markers/${reminderKey}`).set(Date.now());
            workerWroteMarker = true;
          }));

          if (workerWroteMarker) {
            await Promise.allSettled(uids.map(async (uid) => {
              await sendPush(uid, {
                notification: { title: "Feeding Reminder", body: msg },
                data: { feeding: "true" },
              }, "feeding");
            }));
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
            const msg = `Scheduled feed at ${time2} ${ampm2} has been dispensed.`;

            const uniqueTargets = new Set();
            await Promise.all(confirmUids.map(async (uid) => {
              const target = await getNotificationTargetUid(uid);
              uniqueTargets.add(target);
            }));

            let confirmWroteMarker = false;
            await Promise.all(Array.from(uniqueTargets).map(async (targetUid) => {
              const markerSnap = await db.ref(`users/${targetUid}/notifications/markers/${confirmKey}`).once("value");
              if (markerSnap.exists()) return;
              await writeNotification(targetUid, {
                type: "reminder",
                title: "Feeding Complete",
                message: msg,
              });
              await db.ref(`users/${targetUid}/notifications/markers/${confirmKey}`).set(Date.now());
              confirmWroteMarker = true;
            }));

            if (confirmWroteMarker) {
              await Promise.allSettled(confirmUids.map(async (uid) => {
                await sendPush(uid, {
                  notification: { title: "Feeding Complete", body: msg },
                  data: { feeding: "true" },
                }, "feeding");
              }));
            }
          }
        }
      }
    } catch (e) {
      functions.logger.error("processFeeding error:", e.message);
    }
  });

// ═══════════════════════════════════════════════════════════════════════
//  3. SAMPLING REMINDER — scheduled every 1 minute
// ═══════════════════════════════════════════════════════════════════════
exports.processSampling = functions.region("asia-southeast1").pubsub
  .schedule("every 1 minutes")
  .onRun(async (context) => {
    try {
      const uids = await getAuthorizedUids();
      if (uids.length === 0) return;

      const uniqueTargets = new Set();
      await Promise.all(uids.map(async (uid) => {
        const target = await getNotificationTargetUid(uid);
        uniqueTargets.add(target);
      }));

      // Check each target for sampling due
      await Promise.all(Array.from(uniqueTargets).map(async (targetUid) => {
        const types = [
          { type: "crayfish", label: "Crayfish" },
          { type: "lettuce", label: "Lettuce" },
        ];

        for (const { type, label } of types) {
          const due = await getSamplingDue(targetUid, type);
          if (due) {
            await writeSamplingNotification(targetUid, type, label, due.daysSince);
          }
        }
      }));

      // Send FCM pushes
      await Promise.allSettled(uids.map(async (uid) => {
        try {
          const notifTarget = await getNotificationTargetUid(uid);
          await sendSamplingPush(uid, notifTarget, "crayfish", "Crayfish");
          await sendSamplingPush(uid, notifTarget, "lettuce", "Lettuce");
        } catch (err) {
          functions.logger.error(`Sampling push failed for ${uid}:`, err.message);
        }
      }));
    } catch (e) {
      functions.logger.error("processSampling error:", e.message);
    }
  });

// ─── Sampling Helper: check if sampling is due ────────────────────────
async function getSamplingDue(notifTarget, type) {
  const now = Date.now();
  let lastSampleTs = null;

  if (type === "crayfish") {
    const snap = await db.ref(`production/${notifTarget}/crayfish/config`).once("value");
    if (!snap.exists()) return null;
    const config = snap.val();
    if (!config.isInitialized) return null;
    lastSampleTs = config.lastSampleDate || config.stockingDate;
  } else if (type === "lettuce") {
    const snap = await db.ref(`production/${notifTarget}/lettuce/batches`).once("value");
    if (!snap.exists()) return null;
    const batches = snap.val();
    let activeBatch = null;
    for (const key of Object.keys(batches)) {
      const b = batches[key];
      if (b.status === "active") { activeBatch = b; break; }
    }
    if (!activeBatch) return null;
    lastSampleTs = activeBatch.lastSampleDate || activeBatch.plantingDate;
  }

  if (!lastSampleTs) return null;
  const daysSince = Math.floor((now - lastSampleTs) / (1000 * 60 * 60 * 24));
  if (daysSince < 7) return null;

  return { daysSince, lastSampleTs };
}

// ─── Sampling Helper: write DB notification ───────────────────────────
async function writeSamplingNotification(targetUid, type, label, daysSince) {
  const markerKey = `sampling_reminder_${type}`;
  const markerSnap = await db.ref(`users/${targetUid}/notifications/markers/${markerKey}`).once("value");
  if (markerSnap.exists()) {
    const lastReminderTs = markerSnap.val();
    if (lastReminderTs > 0) {
      const daysSinceReminder = Math.floor((Date.now() - lastReminderTs) / (1000 * 60 * 60 * 24));
      if (daysSinceReminder < 7) return false;
    }
  }

  const msg = `It's been ${daysSince} days since last ${label} sampling. Time to record growth data!`;

  await writeNotification(targetUid, {
    type: "reminder",
    title: `${label} Sampling Reminder`,
    message: msg,
  });

  await db.ref(`users/${targetUid}/notifications/markers/${markerKey}`).set(Date.now());
  functions.logger.log(`${label} sampling reminder written for owner: ${targetUid}`);
  return true;
}

// ─── Sampling Helper: send FCM push ───────────────────────────────────
async function sendSamplingPush(uid, notifTarget, type, label) {
  const markerKey = `sampling_reminder_${type}`;
  const markerSnap = await db.ref(`users/${notifTarget}/notifications/markers/${markerKey}`).once("value");
  if (!markerSnap.exists()) return;
  const markerTs = markerSnap.val();
  if (typeof markerTs === "number" && Date.now() - markerTs > 120000) return;

  const due = await getSamplingDue(notifTarget, type);
  if (!due) return;

  const msg = `It's been ${due.daysSince} days since last ${label} sampling. Time to record growth data!`;

  await sendPush(uid, {
    notification: { title: `${label} Sampling Reminder`, body: msg },
    data: { sampling: "true" },
  }, "sampling");
}
