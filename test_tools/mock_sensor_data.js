const admin = require('firebase-admin');
const { getDatabase, ServerValue } = require('firebase-admin/database');
const path = require('path');
const fs = require('fs');

// ─── 1. Load service account ──────────────────────────────────
const keyPaths = [
  path.join(__dirname, 'serviceAccountKey.json'),
  path.join(__dirname, '..', 'serviceAccountKey.json'),
  path.join(__dirname, '..', 'functions', 'serviceAccountKey.json'),
];

let serviceAccount;
if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  try {
    serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    console.log('✅ Using FIREBASE_SERVICE_ACCOUNT env variable.');
  } catch (err) {
    console.error('❌ Failed to parse FIREBASE_SERVICE_ACCOUNT env:', err.message);
    process.exit(1);
  }
} else {
  for (const kp of keyPaths) {
    if (fs.existsSync(kp)) {
      serviceAccount = require(kp);
      break;
    }
  }
}
if (!serviceAccount) {
  console.error('❌ serviceAccountKey.json not found.');
  console.error('   Download it from Firebase Console → Project Settings → Service Accounts → Generate New Private Key');
  console.error('   Then save as test_tools/serviceAccountKey.json');
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

let OPTIMAL_MODE = false; // --optimal flag

// Config thresholds (pre_adult default — matched sa writeDefaultConfig)
const CONFIG_RANGES = {
  temperature:     { min: 24, max: 30 },
  phLevel:         { min: 7.0, max: 8.5 },
  dissolvedOxygen: { min: 4.5, max: 999 },
  turbidity:       { min: 0,   max: 35 },
  waterLevel:      { min: 5, max: 10 },
};

const RANGES = {
  temperature:     { min: 24, max: 34 },
  phLevel:         { min: 6.5, max: 9.0 },
  dissolvedOxygen: { min: 2.5, max: 7.0 },
  turbidity:       { min: 3,   max: 55 },
  waterLevel:      { min: 3, max: 23 },
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
  temperature:     26.0,  // 🟢 optimal (24-30)
  dissolvedOxygen: 6.0,   // 🟢 optimal (>5.0)
  phLevel:         7.8,   // 🟢 optimal
  turbidity:       33.0,  // 🟡 warning (31.5-35)
  waterLevel:      7.5,   // 🟢 optimal (5-10)
};

const OPTIMAL_IDEAL = {
  temperature:     27.0,  // 🟢 optimal mid
  dissolvedOxygen: 6.5,   // 🟢 optimal mid
  phLevel:         7.5,   // 🟢 optimal mid
  turbidity:       15.0,  // 🟢 optimal mid (0-35)
  waterLevel:      7.5,   // 🟢 optimal mid (5-10)
};

// Max na paggalaw per second (sapat para may pagbabago, hindi drastic)
const DRIFT_SPEED = {
  temperature:     0.15,
  dissolvedOxygen: 0.08,
  phLevel:         0.03,
  turbidity:       0.4,
  waterLevel:      0.05,
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

// ─── Temperature Phase Cycle ──────────────────────────────────
// Para ma-demo ang iba't ibang trend: stable, rising, falling, etc.
const TEMP_PHASES = [
  { label: 'Stable (26-28)',        target: 27.0, speed: 0.02, ticks: 20 },
  { label: 'Slow Rise (→30)',       target: 30.5, speed: 0.08, ticks: 25 },
  { label: 'Fast Rise (→critical)', target: 33.0, speed: 0.25, ticks: 15 },
  { label: 'Slow Fall (←28)',       target: 28.0, speed: 0.06, ticks: 30 },
  { label: 'Stable (28)',           target: 28.0, speed: 0.02, ticks: 20 },
  { label: 'Fast Fall (→26)',       target: 26.0, speed: 0.20, ticks: 12 },
  { label: 'Slow Rise (→29)',       target: 29.0, speed: 0.05, ticks: 25 },
  { label: 'Stable (29)',           target: 29.0, speed: 0.02, ticks: 15 },
  { label: 'Fast Rise (→34)',       target: 34.0, speed: 0.30, ticks: 15 },
  { label: 'Fast Fall (→25)',       target: 25.0, speed: 0.25, ticks: 18 },
];
let _tempPhaseIdx = 0;
let _tempTick = 0;

function _updateTemperature() {
  if (OPTIMAL_MODE) {
    _state.temperature += (Math.random() - 0.5) * 0.05;
    _state.temperature = Math.max(26.5, Math.min(27.5, _state.temperature));
    return;
  }

  const phase = TEMP_PHASES[_tempPhaseIdx];
  const current = _state.temperature;
  const diff = phase.target - current;
  const absDiff = Math.abs(diff);

  if (absDiff > phase.speed) {
    _state.temperature += Math.sign(diff) * phase.speed;
  } else {
    // Near target — micro-wobble to look natural
    _state.temperature += (Math.random() - 0.5) * phase.speed * 0.3;
  }

  _tempTick++;
  if (_tempTick >= phase.ticks) {
    _tempPhaseIdx = (_tempPhaseIdx + 1) % TEMP_PHASES.length;
    _tempTick = 0;
    console.log(`  🔄 Temp phase: ${TEMP_PHASES[_tempPhaseIdx].label}`);
  }
}

function generateReading() {
  _updateTemperature();

  if (OPTIMAL_MODE) {
    for (const key of ['dissolvedOxygen', 'phLevel', 'turbidity', 'waterLevel']) {
      _state[key] += (Math.random() - 0.5) * 0.05;
      _state[key] = Math.max(
        OPTIMAL_IDEAL[key] - 2,
        Math.min(OPTIMAL_IDEAL[key] + 2, _state[key])
      );
    }
  } else {
    for (const key of ['dissolvedOxygen', 'phLevel', 'turbidity', 'waterLevel']) {
      _state[key] = _driftTo(IDEAL[key], _state[key], DRIFT_SPEED[key]);
      const r = RANGES[key];
      _state[key] = Math.max(r.min, Math.min(r.max, _state[key]));
    }
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
    const status = OPTIMAL_MODE ? ' 🟢 OPTIMAL' : _checkStatus(data);
    console.log(`[${ts}]  ${vals}${status}`);
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
    // 'ranges' structure is what the Flutter app writes via
    // DatabaseService.saveSensorThresholds. The Cloud Function
    // onSensorUpdate reads from here to detect threshold crossings.
    ranges: {
      temp: { min: 24, max: 30 },
      ph: { min: 7.0, max: 8.5 },
      do: { min: 4.5, max: 999 },
      turb: { min: 0, max: 35 },
      waterlevel: { min: 5, max: 10 },
    },
  });
  console.log('📋 Default sensor thresholds written to config/ranges.');
}

// ─── 9a. Status check helper ────────────────────────────────────
function _checkStatus(data) {
  const c = CONFIG_RANGES;
  const critical = LATEST_KEYS.filter(k => data[k] < c[k].min || data[k] > c[k].max);
  const warning = LATEST_KEYS.filter(k => {
    if (critical.includes(k)) return false;
    const range = c[k].max - c[k].min;
    const warnThreshold = range * 0.10;
    return (data[k] - c[k].min < warnThreshold) || (c[k].max - data[k] < warnThreshold);
  });
  if (critical.length) return ` 🔴 CRITICAL (${critical.join(', ')})`;
  if (warning.length) return ` 🟡 WARNING (${warning.join(', ')})`;
  return ' 🟢 OPTIMAL';
}

// ─── 9. Main ──────────────────────────────────────────────────
process.on('SIGINT', () => { console.log('\nStopping mock...'); process.exit(); });
process.on('SIGTERM', () => process.exit());

async function main() {
  const args = process.argv.slice(2);
  const doBackfill = args.includes('--backfill');

  OPTIMAL_MODE = args.includes('--optimal');

  if (args.includes('--config')) {
    await writeDefaultConfig();
  }

  if (doBackfill) {
    if (OPTIMAL_MODE) {
      console.log('\n🟢 Optimal mode active — backfill will use optimal values.');
    }
    await backfillHistory({ hours: 24,  label: '24 hours' });
    await backfillHistory({ hours: 168, label: '7 days' });
    await backfillHistory({ hours: 720, label: '30 days' });
    console.log('\n✅ Backfill complete!\n');
  }

  if (!doBackfill && !args.includes('--no-live')) {
    const modeLabel = OPTIMAL_MODE
      ? '🟢 OPTIMAL MODE — all sensors within ideal range'
      : '🌡️  Temperature cycles: stable → slow rise → fast rise → fall → ...';
    console.log('\n🚀 Starting real-time simulation…');
    console.log(`   ${modeLabel}`);
    console.log('   Every 5s  → sensor_readings/latest');
    console.log('   Every 30m → sensor_readings/history');
    console.log('   Press Ctrl+C to stop.\n');

    await writeLatest();
    setInterval(() => writeLatest(), 5000);

    await appendHistory();
    setInterval(() => appendHistory(), 30 * 60 * 1000);
  }
}



main().catch(console.error);