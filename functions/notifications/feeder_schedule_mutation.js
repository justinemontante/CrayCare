"use strict";

const {parseScheduleMinute, formatScheduleMinute, formatScheduleLabel} = require("./schedule_time");

class ScheduleMutationError extends Error {
  constructor(code, message, details) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

function scheduleFields(data) {
  const minuteOfDay = parseScheduleMinute(data);
  const scheduledTime = formatScheduleMinute(minuteOfDay);
  if (!scheduledTime) {
    throw new ScheduleMutationError("invalid-argument", "Choose a valid feeding time.");
  }
  if (typeof data.days !== "string" || !/^[01]{7}$/.test(data.days) || !data.days.includes("1")) {
    throw new ScheduleMutationError("invalid-argument", "Select at least one repeat day.");
  }
  // 1 g-only model: the ESP dispenses one gate swing per gram, so whole
  // grams 1-200 map 1:1 to actuations. Persist the same canonical default
  // instead of storing null, so every reader sees one consistent dose.
  const grams = data.grams == null ? 20 : data.grams;
  if (typeof grams !== "number" || !Number.isFinite(grams) ||
      grams < 1 || grams > 200 || !Number.isInteger(grams)) {
    throw new ScheduleMutationError("invalid-argument", "Use 1–200 g in whole grams (1 swing per gram).");
  }
  if (data.enabled !== undefined && typeof data.enabled !== "boolean") {
    throw new ScheduleMutationError("invalid-argument", "Schedule enabled must be true or false.");
  }
  return {
    scheduled_time: scheduledTime,
    days: data.days,
    grams,
    enabled: data.enabled !== false,
  };
}

function scheduleMinutes(data) {
  return parseScheduleMinute(data);
}

function overlaps(first, second) {
  const firstMinute = scheduleMinutes(first);
  const secondMinute = scheduleMinutes(second);
  if (firstMinute == null || firstMinute !== secondMinute) return false;
  // Matches the existing app/device treatment of missing legacy day masks.
  const days = typeof second.days === "string" && second.days.length >= 7
    ? second.days : "1111111";
  return [...first.days].some((day, index) => day === "1" && days[index] === "1");
}

async function mutateSchedule({db, uid, input, timestamp, deleteField, now = Date.now}) {
  if (!uid) throw new ScheduleMutationError("unauthenticated", "Sign in before changing schedules.");
  if (!input || !["add", "edit", "toggle", "delete", "set_schedule_water_quality_policy"].includes(input.operation)) {
    throw new ScheduleMutationError("invalid-argument", "Unknown schedule action.");
  }
  const operation = input.operation;
  if (operation === "set_schedule_water_quality_policy") {
    if (typeof input.allowWaterQualityOverride !== "boolean") {
      throw new ScheduleMutationError("invalid-argument", "The shared feeding water-quality override must be true or false.");
    }
    const tank = db.collection("tanks").doc(uid);
    const profile = db.collection("users").doc(uid);
    const policy = tank.collection("feeder").doc("feeder_policy");
    // Keep the old document mirrored temporarily: deployed ESP32 firmware may
    // still read schedule_policy until the owner uploads the updated firmware.
    const legacyPolicy = tank.collection("feeder").doc("schedule_policy");
    const audit = tank.collection("feeder_logs").doc();
    return db.runTransaction(async tx => {
      const profileSnap = await tx.get(profile);
      const tankSnap = await tx.get(tank);
      const user = profileSnap.exists ? profileSnap.data() : {};
      const tankData = tankSnap.exists ? tankSnap.data() : {};
      const role = String(user.role || "owner").trim().toLowerCase();
      const status = String(user.status || "active").trim().toLowerCase();
      if (role !== "owner" || status !== "active" || tankData.owner_uid !== uid) {
        throw new ScheduleMutationError("permission-denied", "Only the active tank owner can change feeding settings.");
      }
      if (tankData.is_initialized !== true) {
        throw new ScheduleMutationError("failed-precondition", "Initialize your tank before changing feeding settings.");
      }
      const [policySnap, legacySnap] = await Promise.all([
        tx.get(policy),
        tx.get(legacyPolicy),
      ]);
      const policyData = policySnap.exists ? policySnap.data() : {};
      const legacyData = legacySnap.exists ? legacySnap.data() : {};
      const canonicalMatches = policySnap.exists &&
        policyData.allow_water_quality_override === input.allowWaterQualityOverride;
      const legacyMatches = legacySnap.exists &&
        legacyData.allow_water_quality_override === input.allowWaterQualityOverride &&
        !Object.prototype.hasOwnProperty.call(legacyData, "allow_high_turbidity");
      if (canonicalMatches && legacyMatches) {
        return {updated: false};
      }
      const savedPolicy = {
        allow_water_quality_override: input.allowWaterQualityOverride,
        updated_at: timestamp(),
      };
      tx.set(policy, {
        ...savedPolicy,
      });
      tx.set(legacyPolicy, {
        ...savedPolicy,
      });
      tx.create(audit, {
        action: `Manual and scheduled water-quality range override ${input.allowWaterQualityOverride ? "enabled" : "disabled"}`,
        type: "auto",
        logged_at: timestamp(),
      });
      return {updated: true};
    });
  }
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
    // Normalize like the app: legacy profiles may store "Owner"/whitespace.
    const role = String(user.role || "owner").trim().toLowerCase();
    const status = String(user.status || "active").trim().toLowerCase();
    if (role !== "owner" || status !== "active" || tankData.owner_uid !== uid) {
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
    const desired = requested || (operation === "toggle" ? {
      ...previous,
      // Older schedule rows may predate repeat-day and explicit grams fields.
      // Use the same defaults the app/ESP already display and execute.
      days: previous.days || "1111111",
      grams: previous.grams == null ? 20 : previous.grams,
      enabled: input.enabled,
    } : null);
    const normalized = desired ? scheduleFields(desired) : null;
    if (desired && (operation !== "toggle" || input.enabled)) {
      const conflict = snapshot.docs.find(doc => doc.id !== scheduleRef.id && overlaps(normalized, doc.data()));
      if (conflict) {
        const fields = conflict.data();
        throw new ScheduleMutationError("already-exists", "That day and time already have a feeding schedule.", {
          conflictingSchedule: {
            scheduled_time: formatScheduleMinute(scheduleMinutes(fields)),
            days: fields.days || "1111111",
          },
        });
      }
    }

    const nowMs = now();
    let action;
    if (operation === "delete") {
      tx.delete(scheduleRef);
      action = `Removed schedule at ${formatScheduleLabel(previous)}`;
    } else if (operation === "toggle") {
      tx.update(scheduleRef, {
        ...normalized,
        time: deleteField(),
        ampm: deleteField(),
        timeValue: deleteField(),
        allow_high_turbidity: deleteField(),
        enabled: input.enabled,
        isDone: false,
        ...(input.enabled ? {effective_at_ms: nowMs, last_outcome: deleteField(), last_occurrence_at: deleteField()} : {}),
      });
      action = `Schedule ${input.enabled ? "enabled" : "disabled"}: ${formatScheduleLabel(normalized)}`;
    } else {
      const data = {...normalized, isDone: false, effective_at_ms: nowMs};
      if (operation === "add") tx.create(scheduleRef, {...data, created_at: timestamp()});
      else tx.update(scheduleRef, {
        ...data,
        time: deleteField(),
        ampm: deleteField(),
        timeValue: deleteField(),
        allow_high_turbidity: deleteField(),
        last_outcome: deleteField(),
        last_occurrence_at: deleteField(),
      });
      action = `${operation === "add" ? "Scheduled auto feed at" : "Edited schedule to"} ${formatScheduleLabel(normalized)}`;
    }
    const oldRevision = guardSnap.exists ? guardSnap.data().revision : 0;
    tx.set(guard, {revision: (Number.isSafeInteger(oldRevision) ? oldRevision : 0) + 1, updated_at: timestamp()});
    tx.create(audit, {action, type: "auto", logged_at: timestamp()});
    return {scheduleId: scheduleRef.id};
  });
}

module.exports = {mutateSchedule, scheduleFields, overlaps, ScheduleMutationError};
