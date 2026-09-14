"use strict";

const TERMINAL_OUTCOMES = new Set(["completed", "skipped_insufficient", "blocked", "failed"]);

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : NaN;
}

// Pure contract shared by the trigger and regression tests. Delayed offline
// events cannot overwrite a later occurrence or a newly edited schedule.
function scheduleOutcomePatch(schedule, log) {
  const status = String(log.status || "").toLowerCase();
  const at = timestampMillis(log.occurrence_at);
  if (log.type !== "auto" || !TERMINAL_OUTCOMES.has(status) ||
      !Number.isSafeInteger(at) || at < 1700000000000) return null;
  if (Number(schedule.effective_at_ms || 0) > at ||
      timestampMillis(schedule.last_occurrence_at || 0) > at) return null;
  const local = new Date(at + 8 * 3600000);
  const minute = local.getUTCHours() * 60 + local.getUTCMinutes();
  if (Number(schedule.timeValue) !== minute) return null;
  return {
    isDone: status === "completed",
    last_outcome: status,
    // A Date is serialized by the Admin SDK as a Firestore Timestamp.
    last_occurrence_at: new Date(at),
  };
}

module.exports = { TERMINAL_OUTCOMES, scheduleOutcomePatch, timestampMillis };
