"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { scheduleOutcomePatch } = require("./feeder_outcome");
const at = Date.parse("2026-08-26T08:00:00Z"); // Manila 4 PM
const schedule = {timeValue: 960, effective_at_ms: at - 60000};
const event = {type: "auto", status: "completed", occurrence_at: at};

test("Firestore Timestamp occurrence writes a Timestamp-compatible schedule result", () => {
  const firestoreTimestamp = {toMillis: () => at};
  const patch = scheduleOutcomePatch(schedule, {...event, occurrence_at: firestoreTimestamp});
  assert.equal(patch.last_occurrence_at.getTime(), at);
  assert.equal(scheduleOutcomePatch({...schedule, last_occurrence_at: {toMillis: () => at + 1}}, event), null);
});

test("completed, blocked, and failed have distinct outcomes", () => {
  assert.equal(scheduleOutcomePatch(schedule, event).isDone, true);
  for (const status of ["blocked", "failed"]) {
    const patch = scheduleOutcomePatch(schedule, {...event, status});
    assert.equal(patch.isDone, false);
    assert.equal(patch.last_outcome, status);
  }
});
test("offline backfill preserves original occurrence date", () => {
  assert.equal(scheduleOutcomePatch(schedule, {...event, logged_at: at + 86400000}).last_occurrence_at.getTime(), at);
});
test("older and pre-edit events cannot replace current results", () => {
  assert.equal(scheduleOutcomePatch({...schedule, last_occurrence_at: at + 86400000}, event), null);
  assert.equal(scheduleOutcomePatch({...schedule, effective_at_ms: at + 1000}, event), null);
});
test("manual, malformed, and changed-time events do not complete schedules", () => {
  assert.equal(scheduleOutcomePatch(schedule, {...event, type: "manual"}), null);
  assert.equal(scheduleOutcomePatch(schedule, {...event, occurrence_at: null}), null);
  assert.equal(scheduleOutcomePatch({...schedule, timeValue: 360}, event), null);
});
