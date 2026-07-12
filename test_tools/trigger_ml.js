const admin = require('firebase-admin');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const path = require('path');
const fs = require('fs');

const keyPaths = [
  path.join(__dirname, 'serviceAccountKey.json'),
  path.join(__dirname, '..', 'serviceAccountKey.json'),
];
let serviceAccount;
for (const kp of keyPaths) {
  if (fs.existsSync(kp)) { serviceAccount = require(kp); break; }
}
if (!serviceAccount) { console.error('No service account found'); process.exit(1); }

admin.initializeApp({ credential: admin.cert(serviceAccount) });
const db = getFirestore();

async function trigger() {
  await db.collection('sensorReadings').doc('latest').set({
    temperature: 26.5,
    phLevel: 7.8,
    dissolvedOxygen: 6.0,
    turbidity: 15.0,
    waterLevel: 7.5,
    timestamp: FieldValue.serverTimestamp(),
  });
  console.log('✅ sensorReadings/latest written — ML Cloud Function should trigger now.');
  console.log('   Check logs: firebase functions:log --only on_sensor_update');
  process.exit(0);
}
trigger().catch(e => { console.error(e); process.exit(1); });
