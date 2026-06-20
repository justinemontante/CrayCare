const http = require("http");
const admin = require("firebase-admin");

let serviceAccount;
if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  try {
    serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    console.log("Loading service account credentials from environment variable.");
  } catch (err) {
    console.error("Failed to parse FIREBASE_SERVICE_ACCOUNT env variable:", err.message);
    serviceAccount = require("./serviceAccountKey.json");
  }
} else {
  serviceAccount = require("./serviceAccountKey.json");
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL:
    "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app",
});

const db = admin.database();

// Simple HTTP server to bind to port for hosting providers like Render
const PORT = process.env.PORT || 7860;
http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("CrayCare Worker is running...\n");
}).listen(PORT, () => {
  console.log(`HTTP server listening on port ${PORT}`);
});
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

// Sensor state tracker — ON/OFF per sensor
const sensorStates = {}; // { temp: false, ph: false, ... }
// Flag para hindi mag-spam ng "resolved" sa umpisa
let firstRun = true;

// Returns the UID where notifications should be saved for a given user.
// Monitors → saves under owner's UID (shared inbox).
// Owners → saves under own UID.
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

    // Filter out admin accounts from uids
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

async function getAuthorizedUids() {

db.ref("sensor_readings/latest").on("value", async (snap) => {
  const data = snap.val();
  if (!data) return;

  try {
    const configSnap = await db
      .ref("sensor_readings/config")
      .once("value");
    const config = configSnap.val();
    if (!config) return;

    const selectedStage = config.selectedStage;
    if (!selectedStage || !config[selectedStage]) return;
    const thresholds = config[selectedStage];

    // Check each sensor for state changes (ON / OFF)
    const stateChanges = [];

    for (const [espKey, svcKey] of Object.entries(SENSOR_MAP)) {
      const val = data[espKey];
      const range = thresholds[svcKey];
      if (val == null || !range) continue;

      const isCritical = (range.min != null && val < range.min) ||
                         (range.max != null && val > range.max);
      const wasCritical = sensorStates[svcKey] || false;

      if (isCritical && !wasCritical) {
        // normal → critical : send ON alert
        sensorStates[svcKey] = true;
        let dir, threshold;
        if (range.min != null && val < range.min) {
          dir = "low";
          threshold = range.min;
        } else {
          dir = "high";
          threshold = range.max;
        }
        stateChanges.push({ svcKey, val, threshold, dir, state: "critical" });
      } else if (!isCritical && wasCritical) {
        if (!firstRun) {
          // critical → normal : send OFF alert
          sensorStates[svcKey] = false;
          stateChanges.push({ svcKey, val, state: "resolved" });
        } else {
          // First run — just mark as normal, no alert
          sensorStates[svcKey] = false;
        }
      }
      // else: no state change → skip
    }

    firstRun = false;

    // Walang state change → huwag mag-send
    if (stateChanges.length === 0) return;

    // Build notification messages
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
      timestamp: Date.now(),
      unread: true,
    };

    // Get authorized users
    const uids = await getAuthorizedUids();

    let successCount = 0;
    let failureCount = 0;

    await Promise.allSettled(uids.map(async (uid) => {
      try {
        const notifTarget = await getNotificationTargetUid(uid);
        await db.ref(`users/${notifTarget}/notifications`).push().set(notifPayload);

        const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
        const token = tokenSnap.val();
        if (!token) return;

        // Read prefs from dedicated 'notifPrefs' node (separate from notification records)
        const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
        const prefs = prefsSnap.val() || {};
        const sound = prefs.sound !== false;       // default: true
        const vibration = prefs.vibration !== false; // default: true
        const critical = prefs.critical !== false;  // default: true

        // Respect user's critical setting — skip FCM entirely if turned off
        if (!critical) {
          console.log(`[${new Date().toLocaleTimeString()}] Skipping FCM for ${uid} — critical alerts disabled`);
          return;
        }

        // Determine the target channel based on preferences
        let targetChannelId = "craycare_alerts_silent";
        if (sound && vibration) {
          targetChannelId = "craycare_alerts_sound_vibrate";
        } else if (sound) {
          targetChannelId = "craycare_alerts_sound_only";
        } else if (vibration) {
          targetChannelId = "craycare_alerts_vibrate_only";
        }

        await admin.messaging().send({
          token,
          notification: {
            title: notifPayload.title,
            body: msgLines.join("\n"),
          },
          data: {
            title: notifPayload.title,
            body: msgLines.join("\n"),
            sound: String(sound),
            vibration: String(vibration),
            critical: String(critical),
          },
          android: {
            priority: "high",
            notification: {
              channelId: targetChannelId,
              priority: "high",
            }
          },
        });

        successCount++;
        console.log(`[${new Date().toLocaleTimeString()}] Alert sent to ${uid}`);
      } catch (err) {
        failureCount++;
        if (err.code === "messaging/invalid-registration-token" ||
            err.code === "messaging/registration-token-not-registered") {
          await db.ref(`users/${uid}/fcmToken`).remove();
          console.log(`Removed invalid token for ${uid}`);
        } else {
          console.error(`FCM failed for ${uid}:`, err.message);
        }
      }
    }));

    console.log(`[${new Date().toLocaleTimeString()}] Processed ${uids.length} users: ${successCount} OK, ${failureCount} FAIL`);
  } catch (e) {
    console.error("Worker error:", e.message);
  }
});

// ─── Feeding Schedule Reminder Checker ───────────────────────────────────────
setInterval(async () => {
  try {
    const now = new Date();
    const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
    const manilaNow = new Date(now.getTime() + MANILA_OFFSET_MS);
    const todayKey = `${manilaNow.getUTCFullYear()}-${manilaNow.getUTCMonth() + 1}-${manilaNow.getUTCDate()}`;
    const nowMins = manilaNow.getUTCHours() * 60 + manilaNow.getUTCMinutes();

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

      const schedMins = h * 60 + m;
      if (schedMins <= 0) continue;

      // Check if within 5-minute window
      if (nowMins < schedMins - 5 || nowMins >= schedMins) continue;

      const reminderKey = `reminder_${todayKey}_${key}`;
      const uids = await getAuthorizedUids();
      if (uids.length === 0) continue;

      const h12 = h > 12 ? h - 12 : (h === 0 ? 12 : h);
      const ampmStr = h >= 12 ? "PM" : "AM";
      const timeStr = `${h12}:${m.toString().padStart(2, "0")} ${ampmStr}`;

      await Promise.allSettled(uids.map(async (uid) => {
        try {
          const notifTarget = await getNotificationTargetUid(uid);
          const markerSnap = await db.ref(`users/${notifTarget}/notifications/markers/${reminderKey}`).once("value");
          if (markerSnap.exists()) return;

          const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
          const prefs = prefsSnap.val() || {};
          if (prefs.feeding === false) return;

          const sound = prefs.sound !== false;
          const vibration = prefs.vibration !== false;
          const msg = `Your feeding schedule at ${time} ${ampm} will be dispensed in 5 minutes.`;

          const scheduleEpoch = Date.UTC(manilaNow.getUTCFullYear(), manilaNow.getUTCMonth(), manilaNow.getUTCDate(), h, m) - MANILA_OFFSET_MS;
          const reminderTimestamp = scheduleEpoch - 5 * 60 * 1000;

          await db.ref(`users/${notifTarget}/notifications`).push().set({
            type: "reminder",
            title: "Feeding Reminder",
            message: msg,
            timestamp: reminderTimestamp,
            unread: true,
          });

          const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
          const token = tokenSnap.val();
          if (token) {
            let targetChannelId = "craycare_alerts_silent";
            if (sound && vibration) targetChannelId = "craycare_alerts_sound_vibrate";
            else if (sound) targetChannelId = "craycare_alerts_sound_only";
            else if (vibration) targetChannelId = "craycare_alerts_vibrate_only";

            await admin.messaging().send({
              token,
              notification: {
                title: "Feeding Reminder",
                body: msg,
              },
              data: {
                title: "Feeding Reminder",
                body: msg,
                sound: String(sound),
                vibration: String(vibration),
                feeding: "true",
              },
              android: {
                priority: "high",
                notification: {
                  channelId: targetChannelId,
                  priority: "high",
                }
              },
            });
          }

          await db.ref(`users/${notifTarget}/notifications/markers/${reminderKey}`).set(true);
          console.log(`[${new Date().toLocaleTimeString()}] Feeding reminder sent to ${uid} for ${time} ${ampm}`);
        } catch (err) {
          if (err.code === "messaging/invalid-registration-token" ||
              err.code === "messaging/registration-token-not-registered") {
            await db.ref(`users/${uid}/fcmToken`).remove();
          } else {
            console.error(`Feeding reminder failed for ${uid}:`, err.message);
          }
        }
      }));
    }

    // ─── Feeding Complete Confirmation Checker ──────────────────────
    const dispSnap = await db.ref(`feeder/dispatched/${todayKey}`).once("value");
    if (dispSnap.exists()) {
      const dispatched = dispSnap.val();
      const confirmUids = await getAuthorizedUids();
      if (confirmUids.length > 0) {
        for (const [schedKey] of Object.entries(dispatched)) {
          const s2Snap = await db.ref(`feeder/schedules/${schedKey}`).once("value");
          const s2 = s2Snap.val();
          if (!s2) continue;
          if (s2.enabled !== true) continue;

          const time2 = s2.time || "6:00";
          const ampm2 = s2.ampm || "AM";
          const confirmKey = `confirm_${todayKey}_${schedKey}`;

          await Promise.allSettled(confirmUids.map(async (uid) => {
            try {
              const notifTarget = await getNotificationTargetUid(uid);
              const markerSnap = await db.ref(`users/${notifTarget}/notifications/markers/${confirmKey}`).once("value");
              if (markerSnap.exists()) return;

              const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
              const prefs = prefsSnap.val() || {};
              if (prefs.feeding === false) return;

              const sound = prefs.sound !== false;
              const vibration = prefs.vibration !== false;
              const msg = `Scheduled feed at ${time2} ${ampm2} has been dispensed.`;

              await db.ref(`users/${notifTarget}/notifications`).push().set({
                type: "reminder",
                title: "Feeding Complete",
                message: msg,
                timestamp: Date.now(),
                unread: true,
              });

              const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
              const token = tokenSnap.val();
              if (token) {
                let targetChannelId = "craycare_alerts_silent";
                if (sound && vibration) targetChannelId = "craycare_alerts_sound_vibrate";
                else if (sound) targetChannelId = "craycare_alerts_sound_only";
                else if (vibration) targetChannelId = "craycare_alerts_vibrate_only";

                await admin.messaging().send({
                  token,
                  notification: { title: "Feeding Complete", body: msg },
                  data: {
                    title: "Feeding Complete",
                    body: msg,
                    sound: String(sound),
                    vibration: String(vibration),
                    feeding: "true",
                  },
                  android: {
                    priority: "high",
                    notification: { channelId: targetChannelId, priority: "high" }
                  },
                });
              }

              await db.ref(`users/${notifTarget}/notifications/markers/${confirmKey}`).set(true);
              console.log(`[${new Date().toLocaleTimeString()}] Feeding complete sent to ${uid} for ${time2} ${ampm2}`);
            } catch (err) {
              if (err.code === "messaging/invalid-registration-token" ||
                  err.code === "messaging/registration-token-not-registered") {
                await db.ref(`users/${uid}/fcmToken`).remove();
              } else {
                console.error(`Feeding complete failed for ${uid}:`, err.message);
              }
            }
          }));
        }
      }
    }
  } catch (e) {
    console.error("Feeding schedule checker error:", e.message);
  }
}, 30000);

// ─── Sampling Reminder Checker ──────────────────────────────────────────────
setInterval(async () => {
  try {
    const now = new Date();
    const uids = await getAuthorizedUids();
    if (uids.length === 0) return;

    await Promise.allSettled(uids.map(async (uid) => {
      try {
        const notifTarget = await getNotificationTargetUid(uid);

        const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
        const prefs = prefsSnap.val() || {};
        if (prefs.sampling === false) return;

        const configSnap = await db.ref(`tank_data/${notifTarget}/inventory`).once("value");
        if (!configSnap.exists()) return;
        const config = configSnap.val();
        if (!config.isInitialized) return;

        const lastSampleTs = config.lastSampleDate || config.stockingDate;
        if (!lastSampleTs) return;

        const lastSample = new Date(lastSampleTs);
        const daysSince = Math.floor((now - lastSample) / (1000 * 60 * 60 * 24));
        if (daysSince < 7) return;

        const markerSnap = await db.ref(`users/${notifTarget}/notifications/markers/sampling_reminder`).once("value");
        if (markerSnap.exists()) {
          const lastReminderTs = markerSnap.val();
          if (lastReminderTs > 0) {
            const daysSinceReminder = Math.floor((now - lastReminderTs) / (1000 * 60 * 60 * 24));
            if (daysSinceReminder < 7) return;
          }
        }

        const msg = `It's been ${daysSince} days since last sampling. Time to record growth data!`;

        await db.ref(`users/${notifTarget}/notifications`).push().set({
          type: "reminder",
          title: "Sampling Reminder",
          message: msg,
          timestamp: Date.now(),
          unread: true,
        });

        const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
        const token = tokenSnap.val();
        if (token) {
          const sound = prefs.sound !== false;
          const vibration = prefs.vibration !== false;
          let targetChannelId = "craycare_alerts_silent";
          if (sound && vibration) targetChannelId = "craycare_alerts_sound_vibrate";
          else if (sound) targetChannelId = "craycare_alerts_sound_only";
          else if (vibration) targetChannelId = "craycare_alerts_vibrate_only";

          await admin.messaging().send({
            token,
            notification: {
              title: "Sampling Reminder",
              body: msg,
            },
            data: {
              title: "Sampling Reminder",
              body: msg,
              sound: String(sound),
              vibration: String(vibration),
              sampling: "true",
            },
            android: {
              priority: "high",
              notification: {
                channelId: targetChannelId,
                priority: "high",
              }
            },
          });
        }

        await db.ref(`users/${notifTarget}/notifications/markers/sampling_reminder`).set(Date.now());
        console.log(`[${new Date().toLocaleTimeString()}] Sampling reminder sent to ${uid} (${daysSince} days)`);
      } catch (err) {
        console.error(`Sampling reminder failed for ${uid}:`, err.message);
      }
    }));
  } catch (e) {
    console.error("Sampling reminder checker error:", e.message);
  }
}, 60000);

console.log("CrayCare Notification Worker started.");
console.log("Monitoring sensor_readings/latest for threshold alerts...");
console.log("Checking feeder/schedules for 5-min feeding reminders and confirmations...");
console.log("Checking tank/config for sampling reminders...");
