const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {notificationEventId} = require("./notification_delivery");

// main.js loads index.js first, so the shared Admin app is already initialized.
const firestoreDb = admin.firestore();

function normalized(value) {
  return String(value == null ? "" : value).trim().toLowerCase();
}

async function isEligibleAssignment(data) {
  if (!data) return false;
  const uid = typeof data.uid === "string" ? data.uid.trim() : "";
  const tankId = typeof data.tank_id === "string" ? data.tank_id.trim() : "";
  if (!uid || !tankId) return false;

  const [userSnap, tankSnap] = await Promise.all([
    firestoreDb.collection("users").doc(uid).get(),
    firestoreDb.collection("tanks").doc(tankId).get(),
  ]);
  if (!userSnap.exists || !tankSnap.exists) return false;
  const user = userSnap.data() || {};
  const tank = tankSnap.data() || {};
  const role = normalized(user.role || "owner");
  const status = normalized(user.status || "active");
  return role === "owner" && status === "active" && tank.owner_uid === uid;
}

async function clearMatchingAssignment(uid, tankId) {
  const ownerRef = firestoreDb.collection("hardware_system").doc("currentOwner");
  await firestoreDb.runTransaction(async (transaction) => {
    const ownerSnap = await transaction.get(ownerRef);
    if (!ownerSnap.exists) return;
    const owner = ownerSnap.data() || {};
    const assignedUid = typeof owner.uid === "string" ? owner.uid : "";
    const assignedTankId = typeof owner.tank_id === "string" ? owner.tank_id : "";
    const matchesUid = uid && assignedUid === uid;
    const matchesLegacyTank = !assignedUid && tankId && assignedTankId === tankId;
    if (!matchesUid && !matchesLegacyTank) return;

    transaction.set(ownerRef, {
      uid: null,
      tank_id: null,
    }, { merge: true });
  });
}

function textValue(value) {
  return typeof value === "string" ? value.trim() : "";
}

function timestampMillis(value) {
  return value && typeof value.toMillis === "function" ? value.toMillis() : null;
}

// Firestore retries triggers. Use the document update time as the event key so
// a retry cannot create duplicate inbox notifications for the same change.
function assignmentEventKey(change) {
  const updateMs = timestampMillis(change.after.updateTime);
  if (Number.isFinite(updateMs)) return String(Math.floor(updateMs));
  const assignedMs = timestampMillis((change.after.data() || {}).assigned_at);
  if (Number.isFinite(assignedMs)) return String(Math.floor(assignedMs));
  return "assignment-change";
}

async function writeAssignmentNotification({uid, eventKey, title, body}) {
  if (!uid) return;
  const id = notificationEventId("hardware_assignment", uid, eventKey);
  const ref = firestoreDb.collection("notifications").doc(id);
  await firestoreDb.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return;
    transaction.create(ref, {
      uid,
      notif_type: "warning",
      title,
      body,
      is_read: false,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

async function notifyAssignmentChange(change) {
  const before = change.before.exists ? change.before.data() || {} : {};
  const after = change.after.exists ? change.after.data() || {} : {};
  const previousUid = textValue(before.uid);
  const previousTank = textValue(before.tank_id);
  const nextUid = textValue(after.uid);
  const nextTank = textValue(after.tank_id);

  if (!previousUid && !nextUid) return;
  if (previousUid === nextUid && previousTank === nextTank) return;

  const eventKey = assignmentEventKey(change);
  const notices = [];
  if (previousUid && (previousUid !== nextUid || previousTank !== nextTank)) {
    notices.push(writeAssignmentNotification({
      uid: previousUid,
      eventKey: `${eventKey}:previous:${previousTank}`,
      title: "Hardware assignment changed",
      body: "The CrayCare hardware is no longer assigned to your tank. New sensor readings will not be recorded here.",
    }));
  }
  if (nextUid && (previousUid !== nextUid || previousTank !== nextTank)) {
    notices.push(writeAssignmentNotification({
      uid: nextUid,
      eventKey: `${eventKey}:current:${nextTank}`,
      title: "Hardware assigned",
      body: "The CrayCare hardware is now assigned to your tank. New sensor readings will appear after the ESP32 refreshes its assignment.",
    }));
  }
  await Promise.all(notices);
}

// Defense in depth for status/role changes made outside the Flutter Admin UI.
// The client already unassigns atomically, but Console/Admin-SDK changes must
// not leave a disabled/non-owner account connected to the physical hardware.
exports.onUserAssignmentEligibilityChange = functions.region("asia-southeast1").firestore
  .document("users/{uid}")
  .onUpdate(async (change, context) => {
    const after = change.after.data() || {};
    const role = normalized(after.role || "owner");
    const status = normalized(after.status || "active");
    if (role === "owner" && status === "active") return null;

    await clearMatchingAssignment(context.params.uid, context.params.uid);
    return null;
  });

// Validate writes even when they come from trusted/Admin-SDK code that bypasses
// Firestore client rules. Clearing the invalid write triggers this function a
// second time, but the null/null state exits immediately and does not loop.
exports.onHardwareAssignmentWrite = functions.region("asia-southeast1").firestore
  .document("hardware_system/currentOwner")
  .onWrite(async (change) => {
    if (!change.after.exists) return null;
    const data = change.after.data() || {};
    // A null/null transition is a legitimate unassignment. Notify the old
    // owner before returning, so an in-app warning is not silently skipped.
    if (data.uid == null && data.tank_id == null) {
      await notifyAssignmentChange(change);
      return null;
    }
    if (await isEligibleAssignment(data)) {
      await notifyAssignmentChange(change);
      return null;
    }

    functions.logger.warn("[HardwareAssignment] Invalid owner assignment cleared.");
    await change.after.ref.set({
      uid: null,
      tank_id: null,
    }, { merge: true });
    return null;
  });
