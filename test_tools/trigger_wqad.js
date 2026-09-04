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

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = getFirestore();

function manilaDateKey(milliseconds) {
  const manila = new Date(milliseconds + 8 * 60 * 60 * 1000);
  return [
    manila.getUTCFullYear(),
    String(manila.getUTCMonth() + 1).padStart(2, '0'),
    String(manila.getUTCDate()).padStart(2, '0'),
  ].join('-');
}

async function seedHistory() {
  const assignment = await db.collection('hardware_system').doc('currentOwner').get();
  const tankId = assignment.exists ? assignment.data().tank_id : null;
  if (!tankId) throw new Error('No hardware owner/tank is currently assigned.');

  const batch = db.batch();
  const now = Date.now();
  for (let i = 11; i >= 0; i--) {
    const captured = now - i * 10 * 60 * 1000;
    const dateKey = manilaDateKey(captured);
    const ref = db.collection('tanks').doc(tankId)
      .collection('sensor_readings_history').doc(dateKey)
      .collection('entries').doc(`ml_test_${captured}`);
    batch.set(ref, {
      temp_min: 25.8, temp_max: 26.4, temp_avg: 26.1,
      pH_min: 7.3, pH_max: 7.6, pH_avg: 7.45,
      DO_min: 5.8, DO_max: 6.4, DO_avg: 6.1,
      turbidity_min: 10, turbidity_max: 15, turbidity_avg: 12.5,
      waterLevel_min: 17.5, waterLevel_max: 18.5, waterLevel_avg: 18.0,
      recorded_at: Timestamp.fromMillis(captured),
    });
  }
  await batch.commit();
  console.log(`✅ Seeded twelve complete 10-minute records for tank ${tankId}.`);
  console.log('The production WQAD function is hourly; wait for the next scheduler run, then run check_water_quality_anomaly_detection.js.');
}

seedHistory().catch(error => { console.error(error); process.exit(1); });
