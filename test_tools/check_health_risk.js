const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');
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
if (!serviceAccount) { console.error('No SA'); process.exit(1); }

admin.initializeApp({ credential: admin.cert(serviceAccount) });
const db = getFirestore();

const TANK_OWNER_UID = process.env.TANK_OWNER_UID || 'test-owner';

async function check() {
  const snap = await db.collection('healthRisk').doc(TANK_OWNER_UID).get();
  if (snap.exists) {
    const data = snap.data();
    console.log(`✅ healthRisk/${TANK_OWNER_UID} EXISTS:\n`);
    console.log(JSON.stringify(data, null, 2));
  } else {
    console.log(`❌ healthRisk/${TANK_OWNER_UID} does NOT exist yet`);
    console.log('   The ML function may not have triggered yet.');
    console.log('   Try writing to sensorReadings/{ownerUid} again.');
  }
  process.exit(0);
}
check().catch(e => { console.error(e); process.exit(1); });
