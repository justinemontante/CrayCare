const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');
const fs = require('fs');
const path = require('path');

function loadServiceAccount() {
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
  }

  const candidates = [
    path.join(__dirname, 'serviceAccountKey.json'),
    path.join(__dirname, '..', 'serviceAccountKey.json'),
  ];
  const keyPath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!keyPath) {
    throw new Error(
      'No Firebase credentials found. Keep serviceAccountKey.json in test_tools or set FIREBASE_SERVICE_ACCOUNT locally.',
    );
  }
  return require(keyPath);
}

function manilaDateKey(date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Manila',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const value = Object.fromEntries(parts.map(({ type, value }) => [type, value]));
  return `${value.year}-${value.month}-${value.day}`;
}

function timestampDate(value) {
  if (value && typeof value.toDate === 'function') return value.toDate();
  if (value instanceof Date) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function firstNumber(data, keys) {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'number' && Number.isFinite(value)) return value;
  }
  return null;
}

function display(value, digits = 2) {
  return value == null ? '--' : value.toFixed(digits);
}

async function main() {
  const serviceAccount = loadServiceAccount();
  admin.initializeApp({ credential: admin.cert(serviceAccount) });
  const db = getFirestore();

  const assignment = await db.collection('hardware_system').doc('currentOwner').get();
  const tankId = assignment.data()?.tank_id;
  if (typeof tankId !== 'string' || !tankId.trim()) {
    throw new Error('No tank is currently assigned in hardware_system/currentOwner.');
  }

  const tank = db.collection('tanks').doc(tankId.trim());
  const now = new Date();
  const dateKeys = [manilaDateKey(now), manilaDateKey(new Date(now.getTime() - 86400000))];
  const snapshots = await Promise.all(dateKeys.map((dateKey) =>
    tank.collection('sensor_readings_history')
      .doc(dateKey)
      .collection('entries')
      .orderBy('recorded_at', 'desc')
      .limit(24)
      .get(),
  ));

  const byTimestamp = new Map();
  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) {
      const data = doc.data();
      const recordedAt = timestampDate(data.recorded_at);
      if (!recordedAt) continue;
      byTimestamp.set(recordedAt.getTime(), { recordedAt, data });
    }
  }
  const readings = [...byTimestamp.values()]
    .sort((a, b) => a.recordedAt - b.recordedAt)
    .slice(-24);

  console.log('CrayCare sensor history (read-only)');
  console.log(`Assigned tank: ${tankId.trim()}`);
  console.log(`Records found: ${readings.length} (showing up to the latest 24)`);
  console.log('Times shown in Asia/Manila. Sensor values are read from history only.\n');

  if (readings.length === 0) {
    console.log('No timestamped history entries found for today or yesterday.');
    return;
  }

  console.log('RECORDED AT                 GAP       TEMP     pH       DO       TURB     WATER    FEED');
  let continuousTail = 1;
  for (let i = 0; i < readings.length; i += 1) {
    const { recordedAt, data } = readings[i];
    const gapSeconds = i === 0
      ? null
      : Math.round((recordedAt.getTime() - readings[i - 1].recordedAt.getTime()) / 1000);
    if (i > 0 && gapSeconds >= 480 && gapSeconds <= 720) continuousTail += 1;
    else if (i > 0) continuousTail = 1;

    const time = new Intl.DateTimeFormat('en-PH', {
      timeZone: 'Asia/Manila',
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: true,
    }).format(recordedAt);
    const gap = gapSeconds == null ? '--' : `${Math.floor(gapSeconds / 60)}m ${gapSeconds % 60}s`;
    const temp = firstNumber(data, ['temperature', 'temp_avg']);
    const ph = firstNumber(data, ['ph_level', 'pH_avg']);
    const oxygen = firstNumber(data, ['dissolved_oxygen', 'DO_avg']);
    const turbidity = firstNumber(data, ['turbidity', 'turbidity_avg']);
    const water = firstNumber(data, ['water_level', 'waterLevel', 'waterLevel_avg']);
    const feed = firstNumber(data, ['feed_level', 'feedLevel']);

    console.log(
      `${time.padEnd(27)} ${gap.padEnd(9)} ${display(temp).padEnd(8)} ${display(ph).padEnd(8)} ${display(oxygen).padEnd(8)} ${display(turbidity).padEnd(8)} ${display(water).padEnd(8)} ${display(feed, 1)}`,
    );
  }

  const newest = readings[readings.length - 1].recordedAt;
  const ageMinutes = (now.getTime() - newest.getTime()) / 60000;
  const enoughContinuous = continuousTail >= 12;
  const fresh = ageMinutes <= 20;
  console.log('\nML window check:');
  console.log(`  Continuous 10-minute readings at the end: ${continuousTail}/12`);
  console.log(`  Latest reading age: ${ageMinutes.toFixed(1)} minutes`);
  console.log(`  Result: ${enoughContinuous && fresh ? 'READY' : 'INSUFFICIENT'}`);
  if (!fresh) console.log('  Reason: latest reading is more than 20 minutes old.');
  else if (!enoughContinuous) {
    console.log('  Reason: the latest continuous run has fewer than 12 readings spaced 8–12 minutes apart.');
  }
}

main().catch((error) => {
  console.error(`Could not read sensor history: ${error.message}`);
  process.exitCode = 1;
});
