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
const PORT = process.env.PORT || 3000;
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

    const issues = [];
    for (const [espKey, svcKey] of Object.entries(SENSOR_MAP)) {
      const val = data[espKey];
      const range = thresholds[svcKey];
      if (val == null || !range) continue;

      if (range.min != null && val < range.min) {
        issues.push({ espKey, svcKey, val, threshold: range.min, dir: "low" });
      } else if (range.max != null && val > range.max) {
        issues.push({ espKey, svcKey, val, threshold: range.max, dir: "high" });
      }
    }

    const previousAlertHashSnap = await db.ref("system/lastAlertHash").once("value");
    const previousAlertHash = previousAlertHashSnap.val() || "";

    if (issues.length === 0) {
      if (previousAlertHash !== "") {
        await db.ref("system/lastAlertHash").set("");
        console.log(`[${new Date().toLocaleTimeString()}] Sensors normalized. Resetting hash.`);
      }
      return;
    }

    const hash = issues.map(i => `${i.espKey}:${i.dir}`).sort().join("|");
    if (hash === previousAlertHash) return;

    await db.ref("system/lastAlertHash").set(hash);

    const msgLines = issues.map(({ svcKey, val, threshold, dir }) => {
      const label = LABELS[svcKey] || svcKey;
      const unit = UNITS[svcKey] || "";
      const d = dir === "low" ? "below minimum" : "above maximum";
      return unit
        ? `${label} (${val.toFixed(1)} ${unit}) is ${d} of ${threshold}`
        : `${label} (${val.toFixed(1)}) is ${d} of ${threshold}`;
    });

    const notifPayload = {
      type: "critical",
      title: "Sensor Alert",
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
        usersSnap.forEach((child) => uids.push(child.key));
      }
    } else if (typeof authVal === "object") {
      if (authVal.UID && typeof authVal.UID === "string") {
        uids = authVal.UID.split(",").map(u => u.trim()).filter(Boolean);
      } else {
        for (const [key, val] of Object.entries(authVal)) {
          if (val === true) uids.push(key);
        }
      }
    }

    let successCount = 0;
    let failureCount = 0;

    await Promise.allSettled(uids.map(async (uid) => {
      try {
        await db.ref(`users/${uid}/notifications`).push().set(notifPayload);

        const tokenSnap = await db.ref(`users/${uid}/fcmToken`).once("value");
        const token = tokenSnap.val();
        if (!token) return;

        await admin.messaging().send({
          token,
          notification: {
            title: "CrayCare Alert",
            body: msgLines.join("\n"),
          },
          android: {
            priority: "high",
            notification: {
              channelId: "craycare_alerts",
              priority: "high",
              sound: "default",
            },
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
