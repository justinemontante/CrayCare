"use strict";

const TERMINAL_OUTCOMES = new Set(["completed", "skipped_insufficient", "blocked", "failed"]);
const {parseScheduleMinute} = require("./schedule_time");

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : NaN;
}

// Pure contract shared by the trigger and regression tests. Delayed offline
// events cannot overwrite a later occurrence or a newly edited schedule.
//
// Manual Feed Now logs stay truthfully typed `manual`. Only the final top-up
// that completes a slot carries a schedule_key and manual_request trigger, and
// only then may it close that schedule. Pass allowManualCover explicitly so a
// plain manual log can never be mistaken for an automatic outcome.
function scheduleOutcomePatch(schedule, log, options = {}) {
  const {allowManualCover = false} = options;
  const status = String(log.status || "").toLowerCase();
  const at = timestampMillis(log.occurrence_at);
  const isAuto = log.type === "auto";
  const isManualCover = allowManualCover &&
    log.type === "manual" &&
    String(log.trigger_source || "").toLowerCase() === "manual_request" &&
    status === "completed";

  if ((!isAuto && !isManualCover) || !TERMINAL_OUTCOMES.has(status) ||
      !Number.isSafeInteger(at) || at < 1700000000000) return null;
  if (Number(schedule.effective_at_ms || 0) > at ||
      timestampMillis(schedule.last_occurrence_at || 0) > at) return null;
  const local = new Date(at + 8 * 3600000);
  const minute = local.getUTCHours() * 60 + local.getUTCMinutes();
  if (parseScheduleMinute(schedule) !== minute) return null;
  return {
    isDone: status === "completed",
    last_outcome: status,
    // A Date is serialized by the Admin SDK as a Firestore Timestamp.
    last_occurrence_at: new Date(at),
  };
}

module.exports = { TERMINAL_OUTCOMES, scheduleOutcomePatch, timestampMillis };
