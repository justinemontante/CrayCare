const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL:
      "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app",
  });
}

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
  temp: "\u00B0C",
  ph: "",
  do: "mg/L",
  turb: "NTU",
  waterlevel: "cm",
};

async function main() {
  const dataSnap = await db.ref("sensor_readings/latest").once("value");
  const data = dataSnap.val();
  if (!data) {
    console.log("No sensor data");
    return;
  }

  const configSnap = await db.ref("sensor_readings/config").once("value");
  const config = configSnap.val();
  if (!config) {
    console.log("No config");
    return;
  }

  const stage = config.selectedStage;
  if (!stage || !config[stage]) {
    console.log("No stage selected");
    return;
  }
  const thresholds = config[stage];

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

  // Dedup via RTDB (persists across GH Action runs)
  const hashSnap = await db.ref("system/lastAlertHash").once("value");
  const lastHash = hashSnap.val();

  if (issues.length === 0) {
    if (lastHash) await db.ref("system/lastAlertHash").remove();
    console.log("All sensors OK");
    return;
  }

  const hash = issues.map(i => `${i.espKey}:${i.dir}`).sort().join("|");
  if (hash === lastHash) {
    console.log("Already alerted, skipping");
    return;
  }
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

  let sent = 0;
  await Promise.allSettled(
    uids.map(async (uid) => {
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
        sent++;
        console.log(`Sent to ${uid}`);
      } catch (err) {
        if (
          err.code === "messaging/invalid-registration-token" ||
          err.code === "messaging/registration-token-not-registered"
        ) {
          await db.ref(`users/${uid}/fcmToken`).remove();
          console.log(`Removed invalid token for ${uid}`);
        } else {
          console.error(`Failed ${uid}:`, err.message);
        }
      }
    })
  );

  console.log(`Done - ${sent}/${uids.length} sent`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error("Fatal:", e.message);
  process.exit(1);
});
