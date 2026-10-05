const test = require('node:test');
const assert = require('node:assert/strict');
const {mutateSchedule, scheduleFields} = require('./feeder_schedule_mutation');

const NOW = 1770000000000;
const uid = 'owner-uid';
const tankPrefix = `tanks/${uid}`;

/** In-memory Firestore with just enough shape for mutateSchedule's transaction. */
function makeHarness(seed = {}) {
  const store = {
    [`users/${uid}`]: {role: 'owner', status: 'active'},
    [tankPrefix]: {owner_uid: uid, is_initialized: true, current_batch_id: 'batch-1'},
    ...seed,
  };
  let seq = 0;
  const listUnder = (prefix) => Object.keys(store)
    .filter((k) => k.startsWith(`${prefix}/`) && !k.slice(prefix.length + 1).includes('/'))
    .map((k) => ({id: k.split('/').pop(), data: () => store[k]}));
  const ref = (path) => ({
    path,
    id: path.split('/').pop(),
    get: async () => (path in store
      ? {exists: true, id: path.split('/').pop(), data: () => store[path]}
      : {exists: false, id: path.split('/').pop(), data: () => undefined}),
    collection: (name) => ({
      doc: (id) => ref(`${path}/${name}/${id || `gen${++seq}`}`),
      get: async () => ({docs: listUnder(`${path}/${name}`)}),
    }),
  });
  const root = (name) => ({
    doc: (id) => ref(`${name}/${id}`),
    get: async () => ({docs: listUnder(name)}),
  });
  const db = {
    collection: root,
    runTransaction: (fn) => fn({
      get: (r) => r.get(),
      set: (r, d) => { store[r.path] = {...d}; },
      create: (r, d) => { store[r.path] = {...d}; },
      update: (r, d) => { store[r.path] = {...(store[r.path] || {}), ...d}; },
      delete: (r) => { delete store[r.path]; },
    }),
  };
  const scheduleDocs = () => listUnder(`${tankPrefix}/feeder_schedules`);
  return {
    db,
    store,
    scheduleDocs,
    snapshot: () => JSON.stringify(store),
    addScheduleDoc: (id, data) => { store[`${tankPrefix}/feeder_schedules/${id}`] = data; },
  };
}

const call = (h, input, auth = uid) => mutateSchedule({
  db: h.db,
  uid: auth,
  input,
  timestamp: () => ({__serverTimestamp: true}),
  deleteField: () => ({__delete: true}),
  now: () => NOW,
});

const codeOf = (fn) => fn().then(() => null, (e) => e.code);
const valid = (over = {}) => ({operation: 'add', time: '7:30', ampm: 'AM', days: '1111111', grams: 40, enabled: true, ...over});

test('add writes the schedule, bumps the shared guard, and leaves an audit log', async () => {
  const h = makeHarness();
  const res = await call(h, valid());
  const [doc] = h.scheduleDocs();
  assert.equal(res.scheduleId, doc.id);
  const stored = {...doc.data()};
  delete stored.created_at;
  assert.deepEqual(stored, {
      scheduled_time: '07:30', days: '1111111', grams: 40,
      enabled: true, isDone: false, effective_at_ms: NOW,
    },
  );
  assert.deepEqual(doc.data().created_at, {__serverTimestamp: true});
  assert.equal(h.store[`${tankPrefix}/feeder/schedule_guard`].revision, 1);
  assert.equal(h.scheduleDocs().length, 1);
  const audit = listLogs(h);
  assert.equal(audit.length, 1);
  assert.equal(audit[0].action, 'Scheduled auto feed at 7:30 AM');
  assert.equal(audit[0].type, 'auto');
});

function listLogs(h) {
  return Object.entries(h.store)
    .filter(([k]) => k.startsWith(`${tankPrefix}/feeder_logs/`))
    .map(([, v]) => v);
}

test('a rejected mutation writes nothing, so replaying after an auth failure is safe', async () => {
  const h = makeHarness();
  await call(h, valid());
  const before = h.snapshot();
  // Unknown operation is rejected before the transaction even opens.
  assert.equal(await codeOf(() => call(h, {operation: 'who-knows'})), 'invalid-argument');
  assert.equal(h.snapshot(), before);
  // A conflicting slot is rejected inside the transaction, after the guard read.
  const err = await call(h, valid({grams: 20})).then(() => null, (e) => e);
  assert.equal(err.code, 'already-exists');
  assert.deepEqual(err.details.conflictingSchedule, {scheduled_time: '07:30', days: '1111111'});
  assert.equal(h.snapshot(), before, 'guard revision, schedules and logs must be untouched');
});

test('a missing uid is reported as unauthenticated, never as an internal error', async () => {
  const h = makeHarness();
  assert.equal(await codeOf(() => call(h, valid(), null)), 'unauthenticated');
  assert.equal(h.snapshot(), JSON.stringify(h.store));
});

test('schedule enable/disable does not carry a per-schedule turbidity setting', async () => {
  const h = makeHarness();
  await call(h, valid({time: '6:15', ampm: 'PM', grams: 20}));
  const [doc] = h.scheduleDocs();
  const key = `${tankPrefix}/feeder_schedules/${doc.id}`;

  await call(h, {operation: 'toggle', scheduleId: doc.id, enabled: false});
  assert.equal(h.store[key].enabled, false);
  assert.equal(h.store[key].isDone, false);
  assert.equal(h.store[key].grams, 20);
  assert.equal(h.store[key].scheduled_time, '18:15');
  assert.deepEqual(h.store[key].time, {__delete: true});
  assert.deepEqual(h.store[key].ampm, {__delete: true});
  assert.deepEqual(h.store[key].timeValue, {__delete: true});
  assert.deepEqual(h.store[key].allow_high_turbidity, {__delete: true});
  assert.equal(h.store[key].effective_at_ms, NOW);

  h.store[key] = {...h.store[key], effective_at_ms: NOW - 9e7, last_outcome: 'failed', last_occurrence_at: NOW - 9e7};
  await call(h, {operation: 'toggle', scheduleId: doc.id, enabled: true});
  assert.equal(h.store[key].enabled, true);
  assert.deepEqual(h.store[key].allow_high_turbidity, {__delete: true});
  assert.equal(h.store[key].effective_at_ms, NOW);
  assert.deepEqual(h.store[key].last_outcome, {__delete: true});
  assert.deepEqual(h.store[key].last_occurrence_at, {__delete: true});
});

test('legacy schedule rows are normalized to the single time field when toggled', async () => {
  const h = makeHarness();
  h.addScheduleDoc('legacy-1', {time: '5:00', ampm: 'AM', enabled: false, timeValue: 300});
  const result = await call(h, {operation: 'toggle', scheduleId: 'legacy-1', enabled: true});
  assert.equal(result.scheduleId, 'legacy-1');
  const stored = h.store[`${tankPrefix}/feeder_schedules/legacy-1`];
  assert.equal(stored.enabled, true);
  assert.equal(stored.days, '1111111');
  assert.equal(stored.grams, 20);
  assert.equal(stored.scheduled_time, '05:00');
  assert.deepEqual(stored.allow_high_turbidity, {__delete: true});
  assert.deepEqual(stored.time, {__delete: true});
  assert.deepEqual(stored.ampm, {__delete: true});
  assert.deepEqual(stored.timeValue, {__delete: true});
});

test('delete of an already-removed schedule is idempotent', async () => {
  const h = makeHarness();
  const res = await call(h, {operation: 'delete', scheduleId: 'gone'});
  assert.deepEqual(res, {scheduleId: 'gone'});
});

test('only the active tank owner may mutate, and the tank must be initialized', async () => {
  const denied = async (seed, input = valid()) => codeOf(() => call(makeHarness(seed), input));
  assert.equal(await denied({[`users/${uid}`]: {role: 'admin', status: 'active'}}), 'permission-denied');
  assert.equal(await denied({[`users/${uid}`]: {role: 'owner', status: 'suspended'}}), 'permission-denied');
  assert.equal(await denied({[tankPrefix]: {owner_uid: 'someone-else', is_initialized: true}}), 'permission-denied');
  assert.equal(await denied({[tankPrefix]: {owner_uid: uid, is_initialized: false}}), 'failed-precondition');
  // No tank document at all (an owner whose tank doc was never provisioned).
  const orphan = makeHarness();
  delete orphan.store[tankPrefix];
  assert.equal(await codeOf(() => call(orphan, valid())), 'permission-denied');
});

test('role and status are normalized like the app treats them', async () => {
  const h = makeHarness({[`users/${uid}`]: {role: ' Owner ', status: 'Active'}});
  assert.ok((await call(h, valid({time: '7:05', grams: 20}))).scheduleId);
});

test('scheduleFields enforces the time shape and 1-200 g whole-gram doses', () => {
  assert.equal(scheduleFields({time: '12:00', ampm: 'AM', days: '1111111'}).scheduled_time, '00:00');
  assert.equal(scheduleFields({time: '12:30', ampm: 'PM', days: '1111111'}).scheduled_time, '12:30');
  assert.equal(scheduleFields({time: '6:00', ampm: 'PM', timeValue: null, days: '1111111'}).scheduled_time, '18:00');
  assert.equal(scheduleFields({scheduled_time: '07:30', days: '1111111'}).scheduled_time, '07:30');
  assert.equal(scheduleFields({time: '7:30', ampm: 'AM', days: '1111111'}).grams, 20);
  assert.equal(scheduleFields({time: '7:30', ampm: 'AM', days: '1111111', grams: 5}).grams, 5);
  assert.equal(scheduleFields({time: '7:30', ampm: 'AM', days: '1111111', grams: 30}).grams, 30);
  assert.equal('allow_high_turbidity' in scheduleFields({time: '7:30', ampm: 'AM', days: '1111111'}), false);
  const bad = [
    {time: '0:30', ampm: 'AM', days: '1111111'},
    {time: '13:30', ampm: 'PM', days: '1111111'},
    {time: '7.30', ampm: 'AM', days: '1111111'},
    {time: '7:70', ampm: 'AM', days: '1111111'},
    {time: '7:30', ampm: 'Night', days: '1111111'},
    {time: '7:30', ampm: 'AM', days: '111111'},
    {time: '7:30', ampm: 'AM', days: '0000000'},
    {time: '7:30', ampm: 'AM', days: '1111111', grams: 2.5},
    {time: '7:30', ampm: 'AM', days: '1111111', grams: 220},
    {time: '7:30', ampm: 'AM', days: '1111111', enabled: 'yes'},
    {scheduled_time: '24:00', days: '1111111'},
    {scheduled_time: '24:00', time: '7:30', ampm: 'AM', timeValue: 450, days: '1111111'},
    {scheduled_time: '7:30 PM', days: '1111111'},
  ];
  for (const input of bad) {
    let code = null;
    try { scheduleFields(input); } catch (e) { code = e.code; }
    assert.equal(code, 'invalid-argument', `expected rejection for ${JSON.stringify(input)}`);
  }
});

test('retired high-turbidity-only operation is rejected', async () => {
  const h = makeHarness();
  assert.equal(await codeOf(() => call(h, {
    operation: 'set_schedule_turbidity_policy', allowHighTurbidity: true,
  })), 'invalid-argument');
  assert.equal(Object.keys(h.store).some((key) => key.endsWith('/feeder/feeder_policy')), false);
});

test('shared water-quality policy uses feeder_policy and mirrors legacy path without retired field', async () => {
  const legacyPath = `${tankPrefix}/feeder/schedule_policy`;
  const canonicalPath = `${tankPrefix}/feeder/feeder_policy`;
  const h = makeHarness({
    [legacyPath]: {allow_high_turbidity: false, allow_water_quality_override: false},
  });
  await call(h, {operation: 'set_schedule_water_quality_policy', allowWaterQualityOverride: true});
  assert.equal(h.store[canonicalPath].allow_water_quality_override, true);
  assert.equal(h.store[legacyPath].allow_water_quality_override, true);
  assert.equal('allow_high_turbidity' in h.store[canonicalPath], false);
  assert.equal('allow_high_turbidity' in h.store[legacyPath], false);
  assert.equal(listLogs(h)[0].action, 'Manual and scheduled water-quality range override enabled');
  const before = h.snapshot();
  const result = await call(h, {operation: 'set_schedule_water_quality_policy', allowWaterQualityOverride: true});
  assert.deepEqual(result, {updated: false});
  assert.equal(h.snapshot(), before, 'setting the existing value should not add a duplicate audit entry');
  await call(h, {operation: 'set_schedule_water_quality_policy', allowWaterQualityOverride: false});
  assert.equal(h.store[canonicalPath].allow_water_quality_override, false);
  assert.equal(h.store[legacyPath].allow_water_quality_override, false);
  assert.equal(listLogs(h).length, 2);
});

test('same minute on an overlapping day is a conflict even when grams differ', async () => {
  const h = makeHarness();
  h.addScheduleDoc('a', {time: '7:30', ampm: 'AM', days: '1111111', grams: 40, enabled: true, timeValue: 450});
  assert.equal(await codeOf(() => call(h, valid({days: '0000001'}))), 'already-exists');
  assert.equal(await codeOf(() => call(h, valid({days: '0100000'}))), 'already-exists');
  assert.equal(await codeOf(() => call(h, valid({days: '0000000'.replace('0', '1'), time: '8:30'}))), null);
});

test('canonical 24-hour field conflicts with legacy schedule times', async () => {
  const h = makeHarness();
  h.addScheduleDoc('legacy', {time: '7:30', ampm: 'PM', days: '1111111'});
  assert.equal(await codeOf(() => call(h, valid({scheduled_time: '19:30'}))), 'already-exists');
});
