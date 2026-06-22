const admin = require('firebase-admin');
const { getDatabase, ServerValue } = require('firebase-admin/database');
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

// Always-critical sensors (laging lumalampas sa threshold)
const ALWAYS_CRITICAL = ['temperature'];
// Always-warning sensors (laging nasa 10% boundary ng threshold)
const ALWAYS_WARNING = ['turbidity'];

// Config thresholds (pre_adult default — matched sa writeDefaultConfig)
const CONFIG_RANGES = {
  temperature:     { min: 24, max: 30 },
  phLevel:         { min: 7.0, max: 8.5 },
  dissolvedOxygen: { min: 4.5, max: 999 },
  turbidity:       { min: 0,   max: 35 },
  waterLevel:      { min: 130, max: 180 },
};

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

// ─── 3. State-based gradual readings ──────────────────────────
// Bawat segundo, konting galaw lang — gaya ng totoong tubig

const IDEAL = {
  temperature:     32.0,  // 🔴 critical (>30)
  dissolvedOxygen: 6.0,   // 🟢 optimal (>5.0)
  phLevel:         7.8,   // 🟢 optimal
  turbidity:       33.0,  // 🟡 warning (31.5-35)
  waterLevel:      155.0, // 🟢 optimal
};

// Max na paggalaw per second (sapat para may pagbabago, hindi drastic)
const DRIFT_SPEED = {
  temperature:     0.15,
  dissolvedOxygen: 0.08,
  phLevel:         0.03,
  turbidity:       0.4,
  waterLevel:      0.2,
};

const _state = {};
for (const key of LATEST_KEYS) {
  _state[key] = IDEAL[key];
}

function _driftTo(target, current, speed) {
  const diff = target - current;
  // Pag malayo sa target, bumalik dahan-dahan
  if (Math.abs(diff) > speed * 2) {
    return current + Math.sign(diff) * speed * 0.4;
  }
  // Pag nasa target area, random walk lang
  return current + (Math.random() - 0.5) * speed * 0.9;
}

function generateReading() {
  for (const key of LATEST_KEYS) {
    _state[key] = _driftTo(IDEAL[key], _state[key], DRIFT_SPEED[key]);
    const r = RANGES[key];
    _state[key] = Math.max(r.min, Math.min(r.max, _state[key]));
  }

  const reading = {};
  for (const key of LATEST_KEYS) {
    reading[key] = parseFloat(_state[key].toFixed(2));
  }
  return reading;
}

// ─── 4. Write latest ──────────────────────────────────────────
const latestRef = db.ref('sensor_readings/latest');

async function writeLatest() {
  try {
    const data = generateReading();
    // Firebase server timestamp para walang clock mismatch
    data.timestamp = ServerValue.TIMESTAMP;
    await latestRef.set(data);
    const ts = new Date().toLocaleTimeString();
    const vals = LATEST_KEYS.map(k => `${data[k]}`).join(' | ');
    console.log(`[${ts}]  ${vals}`);
  } catch (err) {
    console.error('❌ Write error:', err.message);
  }
}

// ─── 5. Append history ────────────────────────────────────────
let historyCount = 0;

async function appendHistory() {
  try {
    const now = new Date();
    const dateStr = now.toISOString().slice(0, 10);
    const reading = generateReading();
    reading.timestamp = ServerValue.TIMESTAMP;
    const ref = db.ref(`sensor_readings/history/${dateStr}`).push();
    await ref.set(reading);
    historyCount++;
    if (historyCount % 6 === 0) { // every 3 hours
      console.log(`📝 HISTORY #${historyCount} written to ${dateStr}`);
    }
  } catch (err) {
    console.error('❌ History write error:', err.message);
  }
}

// NOTE: Tinanggal na natin ang Section 6 (Write test notification) 
// para maiwasan ang pagsusulat ng kalat sa root ng database niyo.

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
    const reading = generateReading();
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
process.on('SIGINT', () => { console.log('\nStopping mock...'); process.exit(); });
process.on('SIGTERM', () => process.exit());

async function main() {
  const args = process.argv.slice(2);
  const doBackfill = args.includes('--backfill');

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
    console.log('   Every 1s  → sensor_readings/latest');
    console.log('   Every 30m → sensor_readings/history');
    console.log(`   🔴 ${ALWAYS_CRITICAL.join(', ')}     ~${ALWAYS_CRITICAL.map(k => IDEAL[k]).join('/')} (critical)`);
    console.log(`   🟡 ${ALWAYS_WARNING.join(', ')}   ~${ALWAYS_WARNING.map(k => IDEAL[k]).join('/')} (warning)`);
    const optimal = LATEST_KEYS.filter(k => !ALWAYS_CRITICAL.includes(k) && !ALWAYS_WARNING.includes(k));
    console.log(`   🟢 ${optimal.join(', ')}  ~${optimal.map(k => IDEAL[k]).join('/')} (optimal)`);
    console.log('   Press Ctrl+C to stop.\n');

    await writeLatest();
    setInterval(() => writeLatest(), 1000);

    await appendHistory();
    setInterval(() => appendHistory(), 30 * 60 * 1000);
    
    // NOTE: Tinanggal na natin ang mga setTimeout ng writeNotification dito.
    // Ngayon, ang sensors na lang ang gagalaw, at ang Hugging Face worker 
    // ang awtomatikong gagawa ng totoong notifications kapag lumampas sa limits!
  }
}

main().catch(console.error);