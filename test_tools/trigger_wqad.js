const admin = require('firebase-admin');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const path = require('path');
const fs = require('fs');

const keyPaths = [
  path.join(__dirname, 'serviceAccountKey.json'),
  path.join(__dirname, '..', 'serviceAccountKey.json'),
];
let serviceAccount;
for (const keyPath of keyPaths) {
  if (fs.existsSync(keyPath)) { serviceAccount = require(keyPath); break; }
}
if (!serviceAccount) { console.error('No service account found.'); process.exit(1); }

admin.initializeApp({ credential: admin.cert(serviceAccount) });
const db = getFirestore();

function manilaDateKey(milliseconds) {
  const manila = new Date(milliseconds + 8 * 60 * 60 * 1000);
  return [
    manila.getUTCFullYear(),
    String(manila.getUTCMonth() + 1).padStart(2, '0'),
    String(manila.getUTCDate()).padStart(2, '0'),
  ].join('-');
}

async function removeRecentTestRecords(tankRef, now) {
  const entries = [];
  // A seed run only spans two hours, so test entries can only affect the
  // recent date buckets. Delete our seed IDs and mock-tool r_ IDs only.
  for (let dayOffset = 0; dayOffset <= 2; dayOffset++) {
    const dateKey = manilaDateKey(now - dayOffset * 24 * 60 * 60 * 1000);
    const docs = await tankRef.collection('sensor_readings_history')
      .doc(dateKey).collection('entries').listDocuments();
    for (const doc of docs) {
      if (doc.id.startsWith('ml_test_')) {
        entries.push(doc);
      } else if (doc.id.startsWith('r_')) {
        const snapshot = await doc.get();
        if (snapshot.data()?.hardwareId === 'MOCK_TEST_TOOL') entries.push(doc);
      }
    }
  }

  for (let offset = 0; offset < entries.length; offset += 450) {
    const batch = db.batch();
    for (const ref of entries.slice(offset, offset + 450)) batch.delete(ref);
    await batch.commit();
  }
  return entries.length;
}

async function seedHistory() {
  const assignment = await db.collection('hardware_system').doc('currentOwner').get();
  const assignmentData = assignment.exists ? (assignment.data() || {}) : {};
  const tankId = typeof assignmentData.tank_id === 'string'
    ? assignmentData.tank_id.trim()
    : '';
  const ownerUid = typeof assignmentData.uid === 'string'
    ? assignmentData.uid.trim()
    : '';
  if (!tankId || !ownerUid) {
    throw new Error('No complete hardware_system/currentOwner owner/tank assignment. No readings were written.');
  }

  const tankSnapshot = await db.collection('tanks').doc(tankId).get();
  const tankData = tankSnapshot.data() || {};
  if (!tankSnapshot.exists || tankData.owner_uid !== ownerUid || tankData.is_initialized !== true) {
    throw new Error('Assigned tank is missing, uninitialized, or does not belong to the assigned owner. No readings were written.');
  }

  const now = Date.now();
  const assignedAt = assignmentData.assigned_at;
  const assignmentAtMs = assignedAt && typeof assignedAt.toMillis === 'function'
    ? assignedAt.toMillis()
    : assignment.updateTime?.toMillis?.() ?? now;
  const tankRef = db.collection('tanks').doc(tankId);
  const removed = await removeRecentTestRecords(tankRef, now);
  const round = (value, digits = 2) => parseFloat(value.toFixed(digits));
  const jitter = (amount) => (Math.random() * 2 - 1) * amount;
  // Stable overall pattern, fresh small random variation every run, and a
  // gradual turbidity increase near the end to exercise anomaly presentation.
  const profile = [
    { temp: 25.9, ph: 7.42, do: 6.35, turbidity: 10.8, water: 18.40, feed: 70.0 },
    { temp: 26.0, ph: 7.44, do: 6.28, turbidity: 11.2, water: 18.36, feed: 69.8 },
    { temp: 25.8, ph: 7.40, do: 6.32, turbidity: 10.9, water: 18.33, feed: 69.6 },
    { temp: 26.1, ph: 7.46, do: 6.18, turbidity: 11.4, water: 18.29, feed: 69.4 },
    { temp: 26.0, ph: 7.43, do: 6.22, turbidity: 11.7, water: 18.25, feed: 69.2 },
    { temp: 26.2, ph: 7.47, do: 6.08, turbidity: 11.5, water: 18.22, feed: 69.0 },
    { temp: 26.1, ph: 7.45, do: 6.14, turbidity: 12.1, water: 18.18, feed: 68.8 },
    { temp: 26.2, ph: 7.49, do: 5.98, turbidity: 12.4, water: 18.14, feed: 68.6 },
    { temp: 26.4, ph: 7.46, do: 6.03, turbidity: 13.0, water: 18.10, feed: 68.4 },
    { temp: 26.3, ph: 7.51, do: 5.86, turbidity: 15.2, water: 18.06, feed: 68.2 },
    { temp: 26.5, ph: 7.48, do: 5.92, turbidity: 19.1, water: 18.02, feed: 68.0 },
    { temp: 26.6, ph: 7.52, do: 5.74, turbidity: 23.8, water: 17.98, feed: 67.8 },
  ];
  const samples = profile.map((sample, index) => ({
    temp: round(sample.temp + jitter(0.12)),
    ph: round(sample.ph + jitter(0.025)),
    do: round(sample.do + jitter(0.10)),
    turbidity: round(sample.turbidity + jitter(0.45)),
    water: round(sample.water + jitter(0.015)),
    feed: round(sample.feed + jitter(0.08)),
  }));

  const batch = db.batch();

  for (let index = 0; index < samples.length; index++) {
    const sample = samples[index];
    const captured = now - (samples.length - 1 - index) * 10 * 60 * 1000;
    const dateKey = manilaDateKey(captured);
    const entryId = `r_${captured}`;
    const ref = tankRef
      .collection('sensor_readings_history').doc(dateKey)
      .collection('entries').doc(entryId);
    const range = (value, spread) => ({
      min: parseFloat((value - spread).toFixed(2)),
      avg: value,
      max: parseFloat((value + spread).toFixed(2)),
    });
    const temp = range(sample.temp, 0.15);
    const ph = range(sample.ph, 0.03);
    const dissolvedOxygen = range(sample.do, 0.12);
    const turbidity = range(sample.turbidity, 0.35);
    batch.set(ref, {
      hardwareId: 'MOCK_TEST_TOOL',
      source_tank_id: tankId,
      source_owner_uid: ownerUid,
      source_assignment_at_ms: assignmentAtMs,
      captured_at_ms: captured,
      temp_min: temp.min, temp_max: temp.max, temp_avg: temp.avg,
      pH_min: ph.min, pH_max: ph.max, pH_avg: ph.avg,
      DO_min: dissolvedOxygen.min, DO_max: dissolvedOxygen.max, DO_avg: dissolvedOxygen.avg,
      turbidity_min: turbidity.min, turbidity_max: turbidity.max, turbidity_avg: turbidity.avg,
      water_level: sample.water,
      feed_level: sample.feed,
      recorded_at: Timestamp.fromMillis(captured),
    });
  }
  await batch.commit();
  console.log(`✅ Replaced ${removed} recent synthetic test records and seeded twelve fresh, varied 10-minute records for tank ${tankId}.`);
  console.log('The demo pattern includes normal sensor variation and a gradual turbidity increase in the latest samples.');
  console.log('This writes sensor history only; it does not change sensor_readings/latest or the dashboard live tiles.');
  console.log('Water and feed levels are single scalar fields; no threshold fields were changed.');
  console.log('Run npm run ml:run-now to analyze the fresh history immediately; automatic analysis runs every 30 minutes.');
}

seedHistory().catch(error => { console.error(error); process.exit(1); });
