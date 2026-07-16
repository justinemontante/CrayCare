const admin = require('firebase-admin');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
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
});

const firestore = getFirestore();

// ─── 2. Sensor field names ────────────────────────────────────
const LATEST_KEYS = [
  'temperature',
  'phLevel',
  'dissolvedOxygen',
  'turbidity',
  'waterLevel',
];

let OPTIMAL_MODE = false; // --optimal flag
let CRITICAL_MODE = false; // --critical flag

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

// ─── Critical Phase Cycles (per sensor) ──────────────────────
// Each sensor cycles through phases: optimal → warning → critical → recovery
// Config thresholds for reference:
//   temp: 24-30,  pH: 7.0-8.5,  DO: 4.5+,  turb: 0-35,  water: 5-10

const CRIT_PHASES = {
  phLevel: [
    { label: 'Optimal (7.8)',       target: 7.8,  speed: 0.20, ticks: 3 },
    { label: 'Warning low (6.9)',   target: 6.9,  speed: 0.30, ticks: 3 },
    { label: 'Critical low (6.3)',  target: 6.3,  speed: 0.30, ticks: 5 },
    { label: 'Recovery (7.5)',      target: 7.5,  speed: 0.30, ticks: 4 },
    { label: 'Warning high (8.6)',  target: 8.6,  speed: 0.30, ticks: 4 },
    { label: 'Critical high (9.2)', target: 9.2,  speed: 0.30, ticks: 5 },
    { label: 'Recovery (7.6)',      target: 7.6,  speed: 0.30, ticks: 4 },
  ],
  dissolvedOxygen: [
    { label: 'Optimal (6.5)',       target: 6.5,  speed: 0.30, ticks: 3 },
    { label: 'Warning low (4.4)',   target: 4.4,  speed: 0.40, ticks: 5 },
    { label: 'Critical low (3.2)',  target: 3.2,  speed: 0.30, ticks: 5 },
    { label: 'Recovery (6.0)',      target: 6.0,  speed: 0.40, ticks: 6 },
    { label: 'High (7.5)',         target: 7.5,  speed: 0.30, ticks: 5 },
    { label: 'Stable (6.2)',       target: 6.2,  speed: 0.20, ticks: 3 },
  ],
  temperature: [
    { label: 'Optimal (27)',        target: 27.0, speed: 0.50, ticks: 3 },
    { label: 'Warning (31)',        target: 31.0, speed: 0.80, ticks: 5 },
    { label: 'Critical high (34)',  target: 34.0, speed: 0.60, ticks: 5 },
    { label: 'Recovery (27)',       target: 27.0, speed: 0.70, ticks: 6 },
    { label: 'Low warning (23)',    target: 23.0, speed: 0.80, ticks: 5 },
    { label: 'Critical low (21)',   target: 21.0, speed: 0.50, ticks: 5 },
    { label: 'Recovery (26)',       target: 26.0, speed: 0.70, ticks: 5 },
  ],
  turbidity: [
    { label: 'Optimal (15)',        target: 15.0, speed: 3.0,  ticks: 3 },
    { label: 'Warning (36)',        target: 36.0, speed: 5.0,  ticks: 5 },
    { label: 'Critical high (50)',  target: 50.0, speed: 4.0,  ticks: 5 },
    { label: 'Recovery (20)',       target: 20.0, speed: 5.0,  ticks: 6 },
    { label: 'Critical low (5)',    target: 5.0,  speed: 3.0,  ticks: 5 },
    { label: 'Recovery (18)',       target: 18.0, speed: 3.0,  ticks: 4 },
  ],
  waterLevel: [
    { label: 'Optimal (7.5)',       target: 7.5,  speed: 0.20, ticks: 3 },
    { label: 'Warning low (4.8)',   target: 4.8,  speed: 0.40, ticks: 5 },
    { label: 'Critical low (3.5)',  target: 3.5,  speed: 0.30, ticks: 5 },
    { label: 'Recovery (7.0)',      target: 7.0,  speed: 0.40, ticks: 6 },
    { label: 'Warning high (10.5)', target: 10.5, speed: 0.40, ticks: 5 },
    { label: 'Critical high (12)',  target: 12.0, speed: 0.30, ticks: 5 },
    { label: 'Recovery (7.5)',      target: 7.5,  speed: 0.40, ticks: 6 },
  ],
};

const _critPhaseIdx = {};
const _critTick = {};
for (const key of LATEST_KEYS) {
  _critPhaseIdx[key] = 0;
  _critTick[key] = 0;
}

function _updateCriticalSensor(key) {
  const phases = CRIT_PHASES[key];
  if (!phases) return;

  const phase = phases[_critPhaseIdx[key]];
  const current = _state[key];
  const diff = phase.target - current;

  if (Math.abs(diff) > phase.speed) {
    _state[key] += Math.sign(diff) * phase.speed;
  } else {
    _state[key] += (Math.random() - 0.5) * phase.speed * 0.3;
  }

  _critTick[key]++;
  if (_critTick[key] >= phase.ticks) {
    _critPhaseIdx[key] = (_critPhaseIdx[key] + 1) % phases.length;
    _critTick[key] = 0;
    const next = phases[_critPhaseIdx[key]];
    console.log(`  🔄 ${key} phase: ${next.label}`);
  }
}

function generateReading() {
  if (CRITICAL_MODE) {
    for (const key of LATEST_KEYS) {
      _updateCriticalSensor(key);
    }

    const reading = {};
    for (const key of LATEST_KEYS) {
      reading[key] = parseFloat(_state[key].toFixed(2));
    }
    return reading;
  }

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

function generateAggregatedReading() {
  const readings = [];
  for (let i = 0; i < 5; i++) {
    readings.push(generateReading());
  }

  const result = {};
  const keysMap = {
    temperature: 'temp',
    phLevel: 'pH',
    dissolvedOxygen: 'DO',
    turbidity: 'turbidity',
    waterLevel: 'waterLevel'
  };

  for (const [rtdbKey, mlKey] of Object.entries(keysMap)) {
    const vals = readings.map(r => r[rtdbKey]);
    const min = Math.min(...vals);
    const max = Math.max(...vals);
    const avg = vals.reduce((a, b) => a + b, 0) / vals.length;

    result[`${mlKey}_min`] = parseFloat(min.toFixed(2));
    result[`${mlKey}_max`] = parseFloat(max.toFixed(2));
    result[`${mlKey}_avg`] = parseFloat(avg.toFixed(2));
  }
  return result;
}

// ─── 4. Write latest (Firestore only) ─────────────────────────
async function writeLatest() {
  try {
    const data = generateReading();

    await firestore.collection('sensorReadings').doc('latest').set({
      temperature: data.temperature,
      phLevel: data.phLevel,
      dissolvedOxygen: data.dissolvedOxygen,
      turbidity: data.turbidity,
      waterLevel: data.waterLevel,
      timestamp: FieldValue.serverTimestamp(),
    });

    const ts = new Date().toLocaleTimeString();
    const vals = LATEST_KEYS.map(k => `${data[k]}`).join(' | ');
    const status = OPTIMAL_MODE ? ' 🟢 OPTIMAL' : _checkStatus(data);
    console.log(`[${ts}]  ${vals}${status}`);
  } catch (err) {
    console.error('❌ Write error:', err.message);
  }
}

// ─── 5. Append history (Firestore only) ───────────────────────
let historyCount = 0;

async function appendHistory() {
  try {
    const now = new Date();
    const dateStr = now.toISOString().slice(0, 10);
    const reading = generateAggregatedReading();
    reading.timestamp = Math.floor(Date.now() / 1000);

    await firestore.collection('sensorReadings').doc('history').collection(dateStr).add(reading);

    historyCount++;
    if (historyCount % 6 === 0) {
      console.log(`📝 HISTORY #${historyCount} written to Firestore: ${dateStr}`);
    }
  } catch (err) {
    console.error('❌ History write error:', err.message);
  }
}

// NOTE: Tinanggal na natin ang Section 6 (Write test notification) 
// para maiwasan ang pagsusulat ng kalat sa root ng database niyo.

// ─── 7. Backfill history (Firestore only) ─────────────────────
async function backfillHistory({ hours, label }) {
  console.log(`\n⏳ Backfilling ${label} to Firestore…`);
  const now = Date.now();
  const intervalMs = 10 * 60 * 1000; // 10 minutes
  const total = Math.floor((hours * 3600 * 1000) / intervalMs);
  let written = 0;

  for (let i = total; i >= 0; i--) {
    const ts = now - i * intervalMs;
    const date = new Date(ts);
    const dateStr = date.toISOString().slice(0, 10);
    const reading = generateAggregatedReading();
    reading.timestamp = Math.floor(ts / 1000);

    await firestore.collection('sensorReadings').doc('history').collection(dateStr).add(reading);

    written++;
    if (written % 100 === 0) process.stdout.write('.');
  }
  console.log(` ✅ ${written} entries for ${label}`);
}

// ─── 8. Write sensor config (Firestore only) ──────────────────
async function writeDefaultConfig() {
  await firestore.collection('config').doc('default').set({
    ranges: {
      temp: { min: 24, max: 30 },
      ph: { min: 7.0, max: 8.5 },
      do: { min: 4.5, max: 999 },
      turb: { min: 0, max: 35 },
      waterlevel: { min: 5, max: 10 },
    },
  }, { merge: true });
  console.log('📋 Default sensor thresholds written to Firestore config/default.');
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
  CRITICAL_MODE = args.includes('--critical');

  if (CRITICAL_MODE && OPTIMAL_MODE) {
    console.error('❌ Cannot use --critical and --optimal together.');
    process.exit(1);
  }

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
    const modeLabel = CRITICAL_MODE
      ? '🔴 CRITICAL MODE — all sensors cycling: optimal → warning → critical → recovery'
      : OPTIMAL_MODE
      ? '🟢 OPTIMAL MODE — all sensors within ideal range'
      : '🌡️  Temperature cycles: stable → slow rise → fast rise → fall → ...';
    console.log('\n🚀 Starting real-time simulation…');
    console.log(`   ${modeLabel}`);
    console.log('   Every 5s  → Firestore sensorReadings/latest');
    console.log('   Every 10m → Firestore sensorReadings/history (min/max/avg)');
    console.log('   Press Ctrl+C to stop.\n');

    await writeLatest();
    setInterval(() => writeLatest(), 5000);

    await appendHistory();
    setInterval(() => appendHistory(), 10 * 60 * 1000);
  }
}



main().catch(console.error);