"use strict";

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const REMINDER_WINDOW_MS = 5 * 60 * 1000;

// Consider any upcoming occurrence in the next five minutes. This tolerates a
// delayed scheduler tick and a schedule added inside the reminder window, while
// never promising that a past occurrence will be dispensed.
function feedingReminderOccurrence(schedule, nowMs) {
  // The schedule contract uses `enabled`; there is no `is_active` field.
  if (schedule.enabled === false || !Number.isFinite(nowMs)) return null;
  const minute = schedule.timeValue;
  if (!Number.isInteger(minute) || minute < 0 || minute >= 1440) return null;
  const days = schedule.days ?? "1111111";
  if (typeof days !== "string" || !/^[01]{7}$/.test(days)) return null;
  const effectiveAt = schedule.effective_at_ms ?? 0;
  if (!Number.isFinite(effectiveAt) || effectiveAt < 0) return null;
  const localNow = new Date(nowMs + MANILA_OFFSET_MS);
  const today = Date.UTC(localNow.getUTCFullYear(), localNow.getUTCMonth(), localNow.getUTCDate());
  for (let dayOffset = 0; dayOffset <= 1; dayOffset++) {
    const localDay = new Date(today + dayOffset * DAY_MS);
    const occurrenceAtMs = localDay.getTime() - MANILA_OFFSET_MS + minute * 60000;
    const remainingMs = occurrenceAtMs - nowMs;
    if (remainingMs <= 0 || remainingMs > REMINDER_WINDOW_MS ||
        occurrenceAtMs < effectiveAt || days[localDay.getUTCDay()] !== "1") continue;
    const hour = Math.floor(minute / 60);
    return {
      occurrenceAtMs,
      dateKey: localDay.toISOString().slice(0, 10),
      minutesUntil: Math.ceil(remainingMs / 60000),
      timeLabel: `${hour % 12 || 12}:${String(minute % 60).padStart(2, "0")} ${hour >= 12 ? "PM" : "AM"}`,
    };
  }
  return null;
}

function feedingReminderBody(occurrence) {
  const when = occurrence.minutesUntil === 1
    ? "within a minute"
    : `in about ${occurrence.minutesUntil} minutes`;
  return `Your next feeding is scheduled for ${occurrence.timeLabel} (${when}).`;
}

module.exports = {feedingReminderOccurrence, feedingReminderBody};
