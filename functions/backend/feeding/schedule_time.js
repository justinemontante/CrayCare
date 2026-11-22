"use strict";

// Canonical Firestore schedule time: zero-padded 24-hour "HH:mm".
// Legacy parsing keeps existing schedule documents readable during rollout.
function parseCanonicalScheduleMinute(value) {
  if (typeof value !== "string") return null;
  const match = /^(?:([01]\d|2[0-3])):([0-5]\d)$/.exec(value);
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

function parseScheduleMinute(schedule) {
  if (!schedule || typeof schedule !== "object") return null;
  if (Object.prototype.hasOwnProperty.call(schedule, "scheduled_time")) {
    return parseCanonicalScheduleMinute(schedule.scheduled_time);
  }

  if (schedule.timeValue != null) {
    const oldMinute = Number(schedule.timeValue);
    if (Number.isInteger(oldMinute) && oldMinute >= 0 && oldMinute < 1440) {
      return oldMinute;
    }
  }

  if (typeof schedule.time !== "string" || !["AM", "PM"].includes(schedule.ampm)) {
    return null;
  }
  const match = /^(\d{1,2}):([0-5]\d)$/.exec(schedule.time);
  if (!match) return null;
  const hour = Number(match[1]);
  if (hour < 1 || hour > 12) return null;
  return (hour % 12 + (schedule.ampm === "PM" ? 12 : 0)) * 60 + Number(match[2]);
}

function formatScheduleMinute(minute) {
  if (!Number.isInteger(minute) || minute < 0 || minute >= 1440) return null;
  return `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
}

function formatScheduleLabel(schedule) {
  const minute = parseScheduleMinute(schedule);
  if (minute == null) return "the selected time";
  const hour24 = Math.floor(minute / 60);
  return `${hour24 % 12 || 12}:${String(minute % 60).padStart(2, "0")} ${hour24 >= 12 ? "PM" : "AM"}`;
}

module.exports = {
  parseCanonicalScheduleMinute,
  parseScheduleMinute,
  formatScheduleMinute,
  formatScheduleLabel,
};
