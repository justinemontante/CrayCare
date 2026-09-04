const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

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
    if (data.uid == null && data.tank_id == null) return null;
    if (await isEligibleAssignment(data)) return null;

    functions.logger.warn("[HardwareAssignment] Invalid owner assignment cleared.");
    await change.after.ref.set({
      uid: null,
      tank_id: null,
    }, { merge: true });
    return null;
  });
