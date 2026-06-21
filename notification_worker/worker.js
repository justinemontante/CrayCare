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
  databaseURL: "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app",
});

const db = admin.database();

// Simple HTTP server to bind to port for hosting providers like Hugging Face
const PORT = process.env.PORT || 7860;
http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("CrayCare Notification Worker is running...\n");
}).listen(PORT, "0.0.0.0", () => {
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
const sensorStates = {}; 
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

// ─── Sensor Readings Listener ────────────────────────────────────────────────
db.ref("sensor_readings/latest").on("value", async (snap) => {
  const data = snap.val();
  if (!data) return;

  try {
    const configSnap = await db.ref("sensor_readings/config").once("value");
    const config = configSnap.val();
    if (!config) return;

    const selectedStage = config.selectedStage;
    if (!selectedStage || !config[selectedStage]) return;
    const thresholds = config[selectedStage];

    const stateChanges = [];

    for (const [espKey, svcKey] of Object.entries(SENSOR_MAP)) {
      const val = data[espKey];
      const range = thresholds[svcKey];
      if (val == null || !range) continue;

      const isCritical = (range.min != null && val < range.min) ||
                         (range.max != null && val > range.max);
      const wasCritical = sensorStates[svcKey] || false;

      if (isCritical && !wasCritical) {
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
          sensorStates[svcKey] = false;
          stateChanges.push({ svcKey, val, state: "resolved" });
        } else {
          sensorStates[svcKey] = false;
        }
      }
    }

    firstRun = false;
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
      timestamp: Date.now(),
      unread: true,
    };

    const uids = await getAuthorizedUids();

    // 1. Isave sa database nang ISANG BESES lang per Owner target (Iwas duplicate sa Database)
    const uniqueTargets = new Set();
    await Promise.all(uids.map(async (uid) => {
      const target = await getNotificationTargetUid(uid);
      uniqueTargets.add(target);
    }));

    await Promise.all(Array.from(uniqueTargets).map(async (targetUid) => {
      await db.ref(`users/${targetUid}/notifications`).push().set(notifPayload);
    }));

    // 2. I-send ang Push Notifications (FCM) sa lahat ng kasaping devices
    let successCount = 0;
    let failureCount = 0;

    await Promise.allSettled(uids.map(async (uid) => {
      try {
        const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
        const token = tokenSnap.val();
        if (!token) return;

        const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
        const prefs = prefsSnap.val() || {};
        const sound = prefs.sound !== false;       
        const vibration = prefs.vibration !== false; 
        const critical = prefs.critical !== false;  

        if (!critical) return;

        let targetChannelId = "craycare_alerts_silent";
        if (sound && vibration) targetChannelId = "craycare_alerts_sound_vibrate";
        else if (sound) targetChannelId = "craycare_alerts_sound_only";
        else if (vibration) targetChannelId = "craycare_alerts_vibrate_only";

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
        console.log(`[${new Date().toLocaleTimeString()}] Push alert sent to ${uid}`);
      } catch (err) {
        failureCount++;
        if (err.code === "messaging/invalid-registration-token" ||
            err.code === "messaging/registration-token-not-registered") {
          await db.ref(`users/${uid}/fcmToken`).remove();
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

      if (nowMins < schedMins - 5 || nowMins >= schedMins) continue;

      const reminderKey = `reminder_${todayKey}_${key}`;
      const uids = await getAuthorizedUids();
      if (uids.length === 0) continue;

      // 1. Isave ang feeding reminder sa DB nang isang beses lang per Owner target
      const uniqueTargets = new Set();
      await Promise.all(uids.map(async (uid) => {
        const target = await getNotificationTargetUid(uid);
        uniqueTargets.add(target);
      }));

      const msg = `Your feeding schedule at ${time} ${ampm} will be dispensed in 5 minutes.`;
      const scheduleEpoch = Date.UTC(manilaNow.getUTCFullYear(), manilaNow.getUTCMonth(), manilaNow.getUTCDate(), h, m) - MANILA_OFFSET_MS;
      const reminderTimestamp = scheduleEpoch - 5 * 60 * 1000;

      await Promise.all(Array.from(uniqueTargets).map(async (targetUid) => {
        const markerSnap = await db.ref(`users/${targetUid}/notifications/markers/${reminderKey}`).once("value");
        if (markerSnap.exists()) return;

        await db.ref(`users/${targetUid}/notifications`).push().set({
          type: "reminder",
          title: "Feeding Reminder",
          message: msg,
          timestamp: reminderTimestamp,
          unread: true,
        });

        await db.ref(`users/${targetUid}/notifications/markers/${reminderKey}`).set(true);
      }));

      // 2. I-send ang Push Alerts sa bawat phone ng users
      await Promise.allSettled(uids.map(async (uid) => {
        try {
          const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
          const prefs = prefsSnap.val() || {};
          if (prefs.feeding === false) return;

          const sound = prefs.sound !== false;
          const vibration = prefs.vibration !== false;

          const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
          const token = tokenSnap.val();
          if (token) {
            let targetChannelId = "craycare_alerts_silent";
            if (sound && vibration) targetChannelId = "craycare_alerts_sound_vibrate";
            else if (sound) targetChannelId = "craycare_alerts_sound_only";
            else if (vibration) targetChannelId = "craycare_alerts_vibrate_only";

            await admin.messaging().send({
              token,
              notification: { title: "Feeding Reminder", body: msg },
              data: {
                title: "Feeding Reminder",
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
          console.log(`[${new Date().toLocaleTimeString()}] Feeding reminder push alert processed for ${uid}`);
        } catch (err) {
          if (err.code === "messaging/invalid-registration-token" || err.code === "messaging/registration-token-not-registered") {
            await db.ref(`users/${uid}/fcmToken`).remove();
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
          if (!s2 || s2.enabled !== true) continue;

          const time2 = s2.time || "6:00";
          const ampm2 = s2.ampm || "AM";
          const confirmKey = `confirm_${todayKey}_${schedKey}`;

          // Isave ang Complete log sa DB ng isang beses lang per Owner target
          const uniqueTargets = new Set();
          await Promise.all(confirmUids.map(async (uid) => {
            const target = await getNotificationTargetUid(uid);
            uniqueTargets.add(target);
          }));

          const msg = `Scheduled feed at ${time2} ${ampm2} has been dispensed.`;

          await Promise.all(Array.from(uniqueTargets).map(async (targetUid) => {
            const markerSnap = await db.ref(`users/${targetUid}/notifications/markers/${confirmKey}`).once("value");
            if (markerSnap.exists()) return;

            await db.ref(`users/${targetUid}/notifications`).push().set({
              type: "reminder",
              title: "Feeding Complete",
              message: msg,
              timestamp: Date.now(),
              unread: true,
            });

            await db.ref(`users/${targetUid}/notifications/markers/${confirmKey}`).set(true);
          }));

          // I-send ang confirmation push sa lahat ng phones
          await Promise.allSettled(confirmUids.map(async (uid) => {
            try {
              const prefsSnap = await db.ref(`users/${uid}/notifPrefs`).once("value");
              const prefs = prefsSnap.val() || {};
              if (prefs.feeding === false) return;

              const sound = prefs.sound !== false;
              const vibration = prefs.vibration !== false;

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
            } catch (err) {
              if (err.code === "messaging/invalid-registration-token" || err.code === "messaging/registration-token-not-registered") {
                await db.ref(`users/${uid}/fcmToken`).remove();
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

    // Isave ang Sampling reminder sa DB ng isang beses lang per Owner target
    const uniqueTargets = new Set();
    await Promise.all(uids.map(async (uid) => {
      const target = await getNotificationTargetUid(uid);
      uniqueTargets.add(target);
    }));

    await Promise.all(Array.from(uniqueTargets).map(async (targetUid) => {
      const configSnap = await db.ref(`tank_data/${targetUid}/inventory`).once("value");
      if (!configSnap.exists()) return;
      const config = configSnap.val();
      if (!config.isInitialized) return;

      const lastSampleTs = config.lastSampleDate || config.stockingDate;
      if (!lastSampleTs) return;

      const lastSample = new Date(lastSampleTs);
      const daysSince = Math.floor((now - lastSample) / (1000 * 60 * 60 * 24));
      if (daysSince < 7) return;

      const markerSnap = await db.ref(`users/${targetUid}/notifications/markers/sampling_reminder`).once("value");
      if (markerSnap.exists()) {
        const lastReminderTs = markerSnap.val();
        if (lastReminderTs > 0) {
          const daysSinceReminder = Math.floor((now - lastReminderTs) / (1000 * 60 * 60 * 24));
          if (daysSinceReminder < 7) return;
        }
      }

      const msg = `It's been ${daysSince} days since last sampling. Time to record growth data!`;

      await db.ref(`users/${targetUid}/notifications`).push().set({
        type: "reminder",
        title: "Sampling Reminder",
        message: msg,
        timestamp: Date.now(),
        unread: true,
      });

      await db.ref(`users/${targetUid}/notifications/markers/sampling_reminder`).set(Date.now());
      console.log(`[${new Date().toLocaleTimeString()}] Sampling reminder written to DB for owner: ${targetUid}`);
    }));

    // I-send ang sampling push alert sa phones
    await Promise.allSettled(uids.map(async (uid) => {
      try {
        const notifTarget = await getNotificationTargetUid(uid);
        
        // Basahin ang user preferences
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

        const msg = `It's been ${daysSince} days since last sampling. Time to record growth data!`;

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
            notification: { title: "Sampling Reminder", body: msg },
            data: {
              title: "Sampling Reminder",
              body: msg,
              sound: String(sound),
              vibration: String(vibration),
              sampling: "true",
            },
            android: {
              priority: "high",
              notification: { channelId: targetChannelId, priority: "high" }
            },
          });
        }
      } catch (err) {
        console.error(`Sampling push reminder failed for ${uid}:`, err.message);
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