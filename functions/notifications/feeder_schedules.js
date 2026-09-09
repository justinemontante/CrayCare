"use strict";

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const {mutateSchedule, ScheduleMutationError} = require("./feeder_schedule_mutation");

exports.mutateFeederSchedule = functions.region("asia-southeast1").https.onCall(async (data, context) => {
  try {
    return await mutateSchedule({
      db: admin.firestore(), uid: context.auth && context.auth.uid, input: data,
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
