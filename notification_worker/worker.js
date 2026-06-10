const admin = require("firebase-admin");
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL:
    "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app",
});

const db = admin.database();
const SENSOR_MAP = {
  temperature: "temp",
  phLevel: "ph",
  dissolvedOxygen: "do",
  turbidity: "turb",
  waterLevelPercent: "waterlevel",
};

let previousAlertHash = "";

db.ref("sensor_readings/latest").on("value", async (snap) => {
  const data = snap.val();
  if (!data) return;

  try {
    const thresholdSnap = await db
      .ref("sensor_readings/thresholds/ranges")
      .once("value");
    const thresholds = thresholdSnap.val();
    if (!thresholds) return;

    const issues = [];
    for (const [fbKey, svcKey] of Object.entries(SENSOR_MAP)) {
      const val = data[fbKey];
      const t = thresholds[svcKey];
      if (val == null || !t) continue;

      if (t.min != null && val < t.min) {
        issues.push(`${fbKey} (${val}) is below ideal minimum of ${t.min}`);
      } else if (t.max != null && val > t.max) {
        issues.push(`${fbKey} (${val}) is above ideal maximum of ${t.max}`);
      }
    }

    if (issues.length === 0) {
      previousAlertHash = "";
      return;
    }

    // Prevent duplicate alerts
    const hash = issues.sort().join("|");
    if (hash === previousAlertHash) return;
    previousAlertHash = hash;

    // Save notification to Firebase
    const notifRef = db.ref("notifications").push();
    await notifRef.set({
      type: "critical",
      title: "Sensor Alert",
      message: issues.join("; "),
      timestamp: Date.now(),
      unread: true,
    });

    // Collect all user FCM tokens
    const usersSnap = await db.ref("users").once("value");
    const tokens = [];
    usersSnap.forEach((userSnap) => {
      const token = userSnap.child("fcmToken").val();
      if (token) tokens.push(token);
    });

    if (tokens.length === 0) return;

    // Send FCM push
    const result = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: "CrayCare Alert",
        body: issues.join("\n"),
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

    console.log(
      `[${new Date().toLocaleTimeString()}] Sent: ${result.successCount} success, ${result.failureCount} failed`
    );

    // Remove invalid tokens
    if (result.failureCount > 0) {
      const invalidTokens = [];
      result.responses.forEach((resp, i) => {
        if (
          !resp.success &&
          (resp.error.code === "messaging/invalid-registration-token" ||
            resp.error.code === "messaging/registration-token-not-registered")
        ) {
          invalidTokens.push(i);
        }
      });

      let idx = 0;
      usersSnap.forEach((userSnap) => {
        if (invalidTokens.includes(idx)) {
          userSnap.ref.child("fcmToken").remove();
          console.log(`Removed invalid token for user ${userSnap.key}`);
        }
        idx++;
      });
    }
  } catch (e) {
    console.error("Worker error:", e.message);
  }
});

console.log("CrayCare Notification Worker started.");
console.log("Monitoring sensor_readings/latest for threshold alerts...");
