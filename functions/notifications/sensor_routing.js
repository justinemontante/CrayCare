"use strict";

function sensorRouteDecision(raw, owner, nowMs = Date.now()) {
  if (!owner) return {reason: 'unassigned'};
  const captured = Number(raw.captured_at_ms);
  const assignment = Number(raw.source_assignment_at_ms);
  if (!raw.source_tank_id || !raw.source_owner_uid || !Number.isSafeInteger(assignment) || assignment < 1577836800000) {
    return {reason: 'missing_capture_assignment'};
  }
  if (raw.source_tank_id !== owner.tankId || raw.source_owner_uid !== owner.uid || assignment !== owner.assignedAtMs) {
    return {reason: 'capture_assignment_mismatch'};
  }
  if (!Number.isSafeInteger(captured) || captured < assignment - 1000 || captured > nowMs + 60000) {
    return {reason: 'invalid_capture_time'};
  }
  return {tankId: raw.source_tank_id, capturedAtMs: captured};
}

module.exports = {sensorRouteDecision};
