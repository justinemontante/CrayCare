const admin = require('firebase-admin');
const { getDatabase } = require('firebase-admin/database');
const path = require('path');
const fs = require('fs');

// ─── 1. Load service account ──────────────────────────────────
const keyPaths = [
  path.join(__dirname, '..', 'notification_worker', 'serviceAccountKey.json'),
  path.join(__dirname, '..', 'serviceAccountKey.json'),
];

let serviceAccount;
for (const kp of keyPaths) {
  if (fs.existsSync(kp)) {
    serviceAccount = require(kp);
    break;
  }
}
if (!serviceAccount) {
  console.error('❌ serviceAccountKey.json not found in notification_worker/ or root.');
  process.exit(1);
}

const app = admin.initializeApp({
  credential: admin.cert(serviceAccount),
  databaseURL:
    'https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app',
});

const db = getDatabase(app);

// ─── 2. Sensor field names ────────────────────────────────────
const LATEST_KEYS = [
  'temperature',
  'phLevel',
  'dissolvedOxygen',
  'turbidity',
  'waterLevel',
];

const RANGES = {
  temperature:     { min: 24, max: 34 },
  phLevel:         { min: 6.5, max: 9.0 },
  dissolvedOxygen: { min: 2.5, max: 7.0 },
  turbidity:       { min: 3,   max: 55 },
  waterLevel:      { min: 110, max: 195 },
};

const HOUR_CYCLE = (hour) => ({
  temperature:     3 * Math.sin(((hour - 14) / 24) * 2 * Math.PI),
  phLevel:         0.3 * Math.sin(((hour - 6) / 24) * 2 * Math.PI),
  dissolvedOxygen: -0.5 * Math.sin(((hour - 14) / 24) * 2 * Math.PI),
  turbidity:       8 * Math.sin(((hour - 10) / 24) * 2 * Math.PI),
  waterLevel:      15 * Math.sin(((hour - 8) / 24) * 2 * Math.PI),
});

// ─── 3. Generate reading ──────────────────────────────────────
function generateReading(date = new Date(), critical = false) {
  const hour = date.getHours() + date.getMinutes() / 60;
  const cycle = HOUR_CYCLE(hour);
  const reading = {};
  for (const key of LATEST_KEYS) {
    const r = RANGES[key];
    const mid = (r.min + r.max) / 2;
    const amp = (r.max - r.min) / 2;
    let val = mid + cycle[key] + (Math.random() - 0.5) * amp * 0.3;
    // Critical mode forces extreme values
    if (critical) {
      if (key === 'temperature') val = r.max + 5 + Math.random() * 3;
      else if (key === 'phLevel') val = r.min - 0.8 - Math.random() * 0.5;
      else if (key === 'dissolvedOxygen') val = r.min - 0.5 - Math.random();
      else val = r.max + 10 + Math.random() * 10;
    }
    reading[key] = parseFloat(Math.max(r.min, Math.min(r.max, val)).toFixed(1));
  }
  return reading;
}

// ─── 4. Write latest ──────────────────────────────────────────
const latestRef = db.ref('sensor_readings/latest');

async function writeLatest(critical = false) {
  const data = generateReading(new Date(), critical);
  await latestRef.set(data);
  const ts = new Date().toLocaleTimeString();
  const vals = LATEST_KEYS.map(k => `${data[k]}`).join(' | ');
  console.log(`[${ts}] LATEST  →  ${vals}`);
}

// ─── 5. Append history ────────────────────────────────────────
let historyCount = 0;

async function appendHistory() {
  const now = new Date();
  const dateStr = now.toISOString().slice(0, 10);
  const reading = generateReading(now);
  reading.timestamp = Math.floor(now.getTime() / 1000);
  const ref = db.ref(`sensor_readings/history/${dateStr}`).push();
  await ref.set(reading);
  historyCount++;
  console.log(`[${now.toLocaleTimeString()}] HISTORY #${historyCount}  →  ${dateStr}`);
}

// ─── 6. Write test notification ───────────────────────────────
async function writeNotification(type, title, message) {
  const notifRef = db.ref('notifications').push();
  await notifRef.set({
    type,
    title,
    message,
    timestamp: Date.now(),
    unread: true,
  });
  console.log(`🔔 NOTIF: "${title}"`);
}

// ─── 7. Backfill history ──────────────────────────────────────
async function backfillHistory({ hours, label }) {
  console.log(`\n⏳ Backfilling ${label}…`);
  const now = Date.now();
  const intervalMs = 10 * 60 * 1000; // 10 minutes
  const total = Math.floor((hours * 3600 * 1000) / intervalMs);
  let written = 0;

  for (let i = total; i >= 0; i--) {
    const ts = now - i * intervalMs;
    const date = new Date(ts);
    const dateStr = date.toISOString().slice(0, 10);
    const reading = generateReading(date);
    reading.timestamp = Math.floor(ts / 1000);
    await db.ref(`sensor_readings/history/${dateStr}`).push().set(reading);
    written++;
    if (written % 100 === 0) process.stdout.write('.');
  }
  console.log(` ✅ ${written} entries for ${label}`);
}

// ─── 8. Write sensor config (thresholds) ──────────────────────
async function writeDefaultConfig() {
  await db.ref('sensor_readings/config').update({
    selectedStage: 'pre_adult',
    pre_adult: {
      temp: { min: 24, max: 30 },
      ph: { min: 7.0, max: 8.5 },
      do: { min: 4.5, max: 999 },
      turb: { min: 0, max: 35 },
      waterlevel: { min: 130, max: 180 },
    },
    early_juvenile: {
      temp: { min: 26, max: 32 },
      ph: { min: 7.0, max: 8.5 },
      do: { min: 4.0, max: 999 },
      turb: { min: 0, max: 40 },
      waterlevel: { min: 120, max: 170 },
    },
    advanced_juvenile: {
      temp: { min: 25, max: 31 },
      ph: { min: 7.0, max: 8.5 },
      do: { min: 4.0, max: 999 },
      turb: { min: 0, max: 40 },
      waterlevel: { min: 120, max: 170 },
    },
    market_size: {
      temp: { min: 22, max: 28 },
      ph: { min: 7.0, max: 8.5 },
      do: { min: 4.0, max: 999 },
      turb: { min: 0, max: 30 },
      waterlevel: { min: 100, max: 150 },
    },
  });
  console.log('📋 Default sensor thresholds written to config.');
}

// ─── 9. Main ──────────────────────────────────────────────────
async function main() {
  const args = process.argv.slice(2);
  const doBackfill = args.includes('--backfill');
  const criticalMode = args.includes('--critical');

  if (args.includes('--config')) {
    await writeDefaultConfig();
  }

  if (doBackfill) {
    await backfillHistory({ hours: 24,  label: '24 hours' });
    await backfillHistory({ hours: 168, label: '7 days' });
    await backfillHistory({ hours: 720, label: '30 days' });
    console.log('\n✅ Backfill complete!\n');
  }

  if (!doBackfill && !args.includes('--no-live')) {
    console.log('\n🚀 Starting real-time simulation…');
    console.log('   Every 5s  → sensor_readings/latest');
    console.log('   Every 10m → sensor_readings/history');
    if (criticalMode) console.log('   ⚠️  CRITICAL MODE — values will exceed thresholds');
    console.log('   Press Ctrl+C to stop.\n');

    await writeLatest(criticalMode);
    setInterval(() => writeLatest(criticalMode), 5000);

    await appendHistory();
    setInterval(appendHistory, 10 * 60 * 1000);

    setTimeout(() => writeNotification('operational', 'System Online', 'Mock data generator started.'), 2000);
    setTimeout(() => writeNotification('critical', '⚠️ Critical: Temperature', 'Sensor values exceeded safe range!'), 15000);
  }
}

main().catch(console.error);
