"use strict";

const {createHash} = require("node:crypto");

function notificationEventId(kind, tankId, eventId) {
  if (!kind || !tankId || !eventId) throw new Error("Notification event identity is required");
  const digest = createHash("sha256")
    .update(JSON.stringify([kind, tankId, eventId])).digest("hex");
  return `${kind}_${digest}`;
}

// Firestore triggers can overlap or retry. The private subdocument survives
// deleting the inbox item, so a retry cannot recreate it or reset its read state.
// FCM cannot join the transaction: claim one send attempt before sending. If a
// process dies after the claim, the inbox remains but the push may be missed.
async function deliverNotificationOnce({db, id, uid, type, title, body, timestamp, send}) {
  const notification = db.collection("notifications").doc(id);
  const receipt = notification.collection("delivery").doc("push");
  const claimed = await db.runTransaction(async tx => {
    const previous = await tx.get(receipt);
    if (previous.exists) return false;
    const inbox = await tx.get(notification);
    if (!inbox.exists) tx.create(notification, {
      uid, notif_type: type, title, body, is_read: false, created_at: timestamp(),
    });
    tx.create(receipt, {uid, push_attempt_claimed_at: timestamp()});
    // A pre-existing notification may already have produced a push.
    return !inbox.exists;
  });
  if (!claimed) return false;
  await send();
  return true;
}

module.exports = {notificationEventId, deliverNotificationOnce};
