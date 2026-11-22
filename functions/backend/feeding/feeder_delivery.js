"use strict";

// FCM has no exactly-once send transaction. Claim before sending: duplicates
// never resend, while an interrupted attempt remains available in the inbox.
async function deliverFeederNotificationOnce({db, tankId, logId, uid, title, body, type, timestamp, send}) {
  const feederLog = db.collection("tanks").doc(tankId)
    .collection("feeder_logs").doc(logId);
  const notification = db.collection("notifications").doc(`feeder_${tankId}_${logId}`);
  const claimed = await db.runTransaction(async tx => {
    const log = await tx.get(feederLog);
    if (!log.exists || log.get("push_attempt_claimed_at")) return false;
    const inbox = await tx.get(notification);
    if (inbox.exists) {
      // Preserve the claim if an earlier attempt created the inbox entry.
      tx.update(feederLog, {push_attempt_claimed_at: timestamp()});
      return false;
    }
    tx.create(notification, {
      uid, notif_type: type, title, body, is_read: false, created_at: timestamp(),
    });
    tx.update(feederLog, {push_attempt_claimed_at: timestamp()});
    return true;
  });
  if (!claimed) return false;
  await send();
  return true;
}

module.exports = {deliverFeederNotificationOnce};
