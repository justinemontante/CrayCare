"use strict";

// FCM has no exactly-once send transaction. Claim before sending: duplicates
// never resend, while an interrupted attempt remains available in the inbox.
async function deliverFeederNotificationOnce({db, tankId, logId, uid, title, body, type, timestamp, send}) {
  const receipt = db.collection("tanks").doc(tankId)
    .collection("feeder_notification_receipts").doc(logId);
  const notification = db.collection("notifications").doc(`feeder_${tankId}_${logId}`);
  const claimed = await db.runTransaction(async tx => {
    const previous = await tx.get(receipt);
    if (previous.exists) return false;
    const inbox = await tx.get(notification);
    if (!inbox.exists) tx.create(notification, {
      uid, notif_type: type, title, body, is_read: false, created_at: timestamp(),
    });
    tx.create(receipt, {uid, push_attempt_claimed_at: timestamp()});
    return true;
  });
  if (!claimed) return false;
  await send();
  return true;
}

module.exports = {deliverFeederNotificationOnce};
