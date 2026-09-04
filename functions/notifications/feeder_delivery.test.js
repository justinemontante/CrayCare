const test = require('node:test');
const assert = require('node:assert/strict');
const {deliverFeederNotificationOnce} = require('./feeder_delivery');

function fakeDb() {
  const records = new Map();
  const ref = (path = '') => ({path, collection: n => ref(`${path}/${n}`), doc: n => ref(`${path}/${n}`)});
  let lock = Promise.resolve();
  return {...ref(), records, runTransaction(fn) {
    const result = lock.then(async () => {
      const writes = [];
      const result = await fn({
        get: async ref => ({exists: records.has(ref.path)}),
        create: (ref, data) => writes.push([ref.path, data]),
      });
      for (const [path, data] of writes) records.set(path, data);
      return result;
    });
    lock = result.catch(() => {});
    return result;
  }};
}
const args = db => ({db, tankId:'tank', logId:'event', uid:'owner', title:'Completed', body:'Feed complete', type:'feeding', timestamp:()=>123});

test('concurrent duplicate deliveries send once and preserve read state', async () => {
  const db = fakeDb(); let sends = 0;
  const input = {...args(db), send: async () => {sends++;}};
  await Promise.all([deliverFeederNotificationOnce(input), deliverFeederNotificationOnce(input)]);
  const inbox = db.records.get('/notifications/feeder_tank_event');
  inbox.is_read = true;
  await deliverFeederNotificationOnce(input);
  assert.equal(sends, 1);
  assert.equal(inbox.is_read, true);
  assert.equal(db.records.size, 2);
});
test('an uncertain send is not replayed; durable inbox remains', async () => {
  const db = fakeDb(); let sends = 0;
  const input = {...args(db), send: async () => {sends++; throw Error('uncertain delivery');}};
  await assert.rejects(deliverFeederNotificationOnce(input));
  assert.equal(await deliverFeederNotificationOnce(input), false);
  assert.equal(sends, 1);
  assert.equal(db.records.get('/notifications/feeder_tank_event').body, 'Feed complete');
});
