const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');
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

async function check() {
  const assignment = await db.collection('hardware_system').doc('currentOwner').get();
  const tankId = assignment.exists ? assignment.data().tank_id : null;
  if (!tankId) throw new Error('No hardware owner/tank is currently assigned.');

  const collectionPath = `tanks/${tankId}/water_quality_anomaly_detection_history`;
  const snapshot = await db.collection('tanks').doc(tankId)
    .collection('water_quality_anomaly_detection_history')
    .orderBy('processed_at', 'desc').limit(1).get();
  if (!snapshot.empty) {
    console.log(`✅ Latest result from ${collectionPath}:\n`);
    console.log(JSON.stringify(snapshot.docs[0].data(), null, 2));
  } else {
    console.log(`❌ No detection history exists in ${collectionPath} yet.`);
    console.log('The WQAD scheduler needs twelve complete 10-minute sensor-history records.');
  }
}

check().catch(error => { console.error(error); process.exit(1); });
