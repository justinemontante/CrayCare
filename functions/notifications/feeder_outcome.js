"use strict";

const TERMINAL_OUTCOMES = new Set(["completed", "skipped_insufficient", "blocked", "failed"]);

// Pure contract shared by the trigger and regression tests. Delayed offline
// events cannot overwrite a later occurrence or a newly edited schedule.
function scheduleOutcomePatch(schedule, log) {
  const status = String(log.status || "").toLowerCase();
  const at = Number(log.occurrence_at);
  if (log.type !== "auto" || !TERMINAL_OUTCOMES.has(status) ||
      !Number.isSafeInteger(at) || at < 1700000000000) return null;
  if (Number(schedule.effective_at_ms || 0) > at ||
      Number(schedule.last_occurrence_at || 0) > at) return null;
  const local = new Date(at + 8 * 3600000);
  const minute = local.getUTCHours() * 60 + local.getUTCMinutes();
  if (Number(schedule.timeValue) !== minute) return null;
  return {
    isDone: status === "completed",
    last_outcome: status,
    last_occurrence_at: at,
  };
}

module.exports = { TERMINAL_OUTCOMES, scheduleOutcomePatch };
