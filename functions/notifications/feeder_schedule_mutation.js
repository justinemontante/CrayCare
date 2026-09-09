"use strict";

class ScheduleMutationError extends Error {
  constructor(code, message, details) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

function scheduleFields(data) {
  if (typeof data.time !== "string" || !/^\d{1,2}:\d{2}$/.test(data.time) ||
      !["AM", "PM"].includes(data.ampm)) {
    throw new ScheduleMutationError("invalid-argument", "Choose a valid feeding time.");
  }
  const [hour, minute] = data.time.split(":").map(Number);
  if (hour < 1 || hour > 12 || minute > 59) {
    throw new ScheduleMutationError("invalid-argument", "Choose a valid feeding time.");
  }
  if (typeof data.days !== "string" || !/^[01]{7}$/.test(data.days) || !data.days.includes("1")) {
    throw new ScheduleMutationError("invalid-argument", "Select at least one repeat day.");
  }
  const grams = data.grams == null ? null : data.grams;
  if (grams !== null && (typeof grams !== "number" || !Number.isFinite(grams) ||
      grams < 20 || grams > 200 || grams % 20 !== 0)) {
    throw new ScheduleMutationError("invalid-argument", "Use 20–200 g in steps of 20 g.");
  }
  if (data.enabled !== undefined && typeof data.enabled !== "boolean") {
    throw new ScheduleMutationError("invalid-argument", "Schedule enabled must be true or false.");
  }
  return {
    time: `${hour}:${String(minute).padStart(2, "0")}`,
    ampm: data.ampm,
    timeValue: (hour % 12 + (data.ampm === "PM" ? 12 : 0)) * 60 + minute,
    days: data.days,
    grams,
    enabled: data.enabled !== false,
  };
}

function scheduleMinutes(data) {
  if (Number.isInteger(data.timeValue) && data.timeValue >= 0 && data.timeValue < 1440) {
    return data.timeValue;
  }
  try { return scheduleFields({...data, days: "1111111"}).timeValue; }
  catch (_) { return null; }
}

function overlaps(first, second) {
  if (scheduleMinutes(first) !== scheduleMinutes(second)) return false;
  // Matches the existing app/device treatment of missing legacy day masks.
  const days = typeof second.days === "string" && second.days.length >= 7
    ? second.days : "1111111";
  return [...first.days].some((day, index) => day === "1" && days[index] === "1");
}

async function mutateSchedule({db, uid, input, timestamp, deleteField, now = Date.now}) {
  if (!uid) throw new ScheduleMutationError("unauthenticated", "Sign in before changing schedules.");
  if (!input || !["add", "edit", "toggle", "delete"].includes(input.operation)) {
    throw new ScheduleMutationError("invalid-argument", "Unknown schedule action.");
  }
  const operation = input.operation;
  if (operation !== "add" && (typeof input.scheduleId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(input.scheduleId))) {
    throw new ScheduleMutationError("invalid-argument", "A valid schedule ID is required.");
  }
  if (operation === "toggle" && typeof input.enabled !== "boolean") {
    throw new ScheduleMutationError("invalid-argument", "Schedule enabled must be true or false.");
  }
  const requested = ["add", "edit"].includes(operation) ? scheduleFields(input) : null;
  const tank = db.collection("tanks").doc(uid);
  const schedules = tank.collection("feeder_schedules");
  const scheduleRef = operation === "add" ? schedules.doc() : schedules.doc(input.scheduleId);
  const guard = tank.collection("feeder").doc("schedule_guard");
  const profile = db.collection("users").doc(uid);
  const audit = tank.collection("feeder_logs").doc();

  return db.runTransaction(async tx => {
    // Every writer reads and updates this one server-only document. Concurrent
    // requests retry against the full current collection, including legacy rows.
    // No client-populated index or migration can omit an existing reservation.
    const guardSnap = await tx.get(guard);
    const profileSnap = await tx.get(profile);
    const tankSnap = await tx.get(tank);
    const user = profileSnap.exists ? profileSnap.data() : {};
    const tankData = tankSnap.exists ? tankSnap.data() : {};
    if (user.role !== "owner" || (user.status || "active") !== "active" || tankData.owner_uid !== uid) {
      throw new ScheduleMutationError("permission-denied", "Only the active tank owner can change schedules.");
    }
    if (tankData.is_initialized !== true) {
      throw new ScheduleMutationError("failed-precondition", "Initialize your tank before adding schedules.");
    }
    const snapshot = await tx.get(schedules);
    const oldDoc = snapshot.docs.find(doc => doc.id === scheduleRef.id);
    if (operation !== "add" && !oldDoc) {
      if (operation === "delete") return {scheduleId: scheduleRef.id};
      throw new ScheduleMutationError("not-found", "This schedule was removed. Refresh your schedules.");
    }
    const previous = oldDoc ? oldDoc.data() : null;
    const desired = requested || (operation === "toggle" ? {...previous, enabled: input.enabled} : null);
    if (operation === "toggle" && input.enabled) {
      // Validate legacy entries before enabling them on the physical feeder.
      Object.assign(desired, scheduleFields(desired));
    }
    if (desired && (operation !== "toggle" || input.enabled)) {
      const conflict = snapshot.docs.find(doc => doc.id !== scheduleRef.id && overlaps(desired, doc.data()));
      if (conflict) {
        const fields = conflict.data();
        throw new ScheduleMutationError("already-exists", "That day and time already have a feeding schedule.", {
          conflictingSchedule: {time: fields.time, ampm: fields.ampm, days: fields.days || "1111111"},
        });
      }
    }

    const nowMs = now();
    let action;
    if (operation === "delete") {
      tx.delete(scheduleRef);
      action = `Removed schedule at ${previous.time} ${previous.ampm}`;
    } else if (operation === "toggle") {
      tx.update(scheduleRef, {
        ...(input.enabled ? scheduleFields(desired) : {}),
        enabled: input.enabled,
        isDone: false,
        ...(input.enabled ? {effective_at_ms: nowMs, last_outcome: deleteField(), last_occurrence_at: deleteField()} : {}),
      });
      action = `Schedule ${input.enabled ? "enabled" : "disabled"}: ${previous.time} ${previous.ampm}`;
    } else {
      const data = {...desired, isDone: false, effective_at_ms: nowMs};
      if (operation === "add") tx.create(scheduleRef, {...data, created_at: timestamp()});
      else tx.update(scheduleRef, {...data, last_outcome: deleteField(), last_occurrence_at: deleteField()});
      action = `${operation === "add" ? "Scheduled auto feed at" : "Edited schedule to"} ${desired.time} ${desired.ampm}`;
    }
    const oldRevision = guardSnap.exists ? guardSnap.data().revision : 0;
    tx.set(guard, {revision: (Number.isSafeInteger(oldRevision) ? oldRevision : 0) + 1, updated_at: timestamp()});
    tx.create(audit, {action, type: "auto", logged_at: nowMs});
    return {scheduleId: scheduleRef.id};
  });
}

module.exports = {mutateSchedule, scheduleFields, overlaps, ScheduleMutationError};
