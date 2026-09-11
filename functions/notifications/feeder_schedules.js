"use strict";

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {mutateSchedule, ScheduleMutationError} = require("./feeder_schedule_mutation");

exports.mutateFeederSchedule = functions.region("asia-southeast1").https.onCall(async (data, context) => {
  try {
    let uid = context.auth && context.auth.uid;
    let tokenAuth = false;
    // Fallback: the client also sends its ID token explicitly. If the auth
    // context was stripped in transit, verify the token directly instead of
    // rejecting a signed-in owner as unauthenticated.
    if (!uid && data && typeof data.idToken === "string" && data.idToken.length > 0) {
      try {
        const decoded = await admin.auth().verifyIdToken(data.idToken);
        uid = decoded.uid;
        tokenAuth = true;
      } catch (verifyError) {
        functions.logger.warn("mutateFeederSchedule rejected: invalid idToken", {
          error: verifyError.code || verifyError.message,
        });
      }
    }
    if (!uid) {
      // Boolean-only diagnostic (no PII): tells Cloud Logging whether the
      // client arrived without an auth context at all.
      functions.logger.warn("mutateFeederSchedule rejected: missing auth context", {
        hasAuth: !!context.auth,
        hadIdToken: !!(data && data.idToken),
        tokenAuth,
      });
    }
    // Never forward the raw token into business logic/audit writes.
    const {idToken: _dropped, ...input} = data || {};
    return await mutateSchedule({
      db: admin.firestore(), uid, input,
      timestamp: () => admin.firestore.FieldValue.serverTimestamp(),
      deleteField: () => admin.firestore.FieldValue.delete(),
    });
  } catch (error) {
    if (error instanceof ScheduleMutationError) {
      throw new functions.https.HttpsError(error.code, error.message, error.details);
    }
    functions.logger.error("Schedule mutation failed", {code: error.code, message: error.message});
    throw new functions.https.HttpsError("internal", "Could not save the schedule. Refresh your schedules before retrying.");
  }
});
