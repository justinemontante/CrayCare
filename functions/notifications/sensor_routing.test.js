const test = require('node:test');
const assert = require('node:assert/strict');
const {sensorRouteDecision} = require('./sensor_routing');
const at = 1800000000000;
const owner = {tankId:'A', uid:'owner-A', assignedAtMs: at};
const raw = {source_tank_id:'A', source_owner_uid:'owner-A', source_assignment_at_ms:at, captured_at_ms:at+600000};

test('same assignment routes original capture time', () => {
  assert.deepEqual(sensorRouteDecision(raw, owner, at+3600000), {tankId:'A', capturedAtMs:at+600000});
});
test('old offline readings never enter a newly assigned tank', () => {
  const next = {tankId:'B', uid:'owner-B', assignedAtMs:at+3600000};
  assert.equal(sensorRouteDecision(raw, next, at+7200000).reason, 'capture_assignment_mismatch');
});
test('legacy, unassigned and previous sessions are quarantined', () => {
  assert.equal(sensorRouteDecision({}, owner).reason, 'missing_capture_assignment');
  assert.equal(sensorRouteDecision(raw, null).reason, 'unassigned');
  assert.equal(sensorRouteDecision(raw, {...owner, assignedAtMs:at+1}).reason, 'capture_assignment_mismatch');
});
test('capture cannot precede assignment or be far in the future', () => {
  assert.equal(sensorRouteDecision({...raw, captured_at_ms:at-600000}, owner, at).reason, 'invalid_capture_time');
  assert.equal(sensorRouteDecision(raw, owner, at).reason, 'invalid_capture_time');
});
