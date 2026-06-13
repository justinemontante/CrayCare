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

// Sensor state tracker — ON/OFF per sensor
const sensorStates = {}; // { temp: false, ph: false, ... }
// Flag para hindi mag-spam ng "resolved" sa umpisa
let firstRun = true;

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

    let successCount = 0;
    let failureCount = 0;

    await Promise.allSettled(uids.map(async (uid) => {
      try {
        await db.ref(`users/${uid}/notifications`).push().set(notifPayload);

        const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
        const token = tokenSnap.val();
        if (!token) return;

        const prefsSnap = await db.ref(`users/${uid}/notifications`).once("value");
        const prefs = prefsSnap.val() || {};
        const sound = prefs.sound !== false;
        const vibration = prefs.vibration !== false;
        const critical = prefs.critical !== false;

        if (!critical) return;

        await admin.messaging().send({
          token,
          data: {
            title: "CrayCare Alert",
            body: msgLines.join("\n"),
            sound: String(sound),
            vibration: String(vibration),
            critical: String(critical),
          },
          android: {
            priority: "high",
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

console.log("CrayCare Notification Worker started.");
console.log("Monitoring sensor_readings/latest for threshold alerts...");
