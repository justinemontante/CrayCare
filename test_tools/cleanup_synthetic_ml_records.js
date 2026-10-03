const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const fs = require('fs');
const path = require('path');

const keyPaths = [
  path.join(__dirname, 'serviceAccountKey.json'),
  path.join(__dirname, '..', 'serviceAccountKey.json'),
];
const keyPath = keyPaths.find((candidate) => fs.existsSync(candidate));
if (!keyPath) throw new Error('Firebase service-account key not found.');

const serviceAccount = require(keyPath);
initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();
const confirmDelete = process.argv.includes('--confirm-delete');

function millis(value) {
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

async function main() {
  const assignment = await db.collection('hardware_system').doc('currentOwner').get();
  const assigned = assignment.data() || {};
  const tankId = typeof assigned.tank_id === 'string' ? assigned.tank_id.trim() : '';
  if (!tankId) throw new Error('No active assigned tank; no records were changed.');

  const tankRef = db.collection('tanks').doc(tankId);
  const tankSnapshot = await tankRef.get();
  if (!tankSnapshot.exists || tankSnapshot.data()?.owner_uid !== assigned.uid) {
    throw new Error('Assigned tank ownership check failed; no records were changed.');
  }

  const testEntries = [];
  const testLiveRefs = [];
  const latestRef = tankRef.collection('sensor_readings').doc('latest');
  const latestSnapshot = await latestRef.get();
  if (latestSnapshot.exists && latestSnapshot.data()?.hardwareId === 'MOCK_TEST_TOOL') {
    testLiveRefs.push(latestRef);
  }
  for (const dayDoc of await tankRef.collection('sensor_readings_history').listDocuments()) {
    const entries = await dayDoc.collection('entries').listDocuments();
    for (const entryRef of entries) {
      const snapshot = await entryRef.get();
      const data = snapshot.data() || {};
      if (
        entryRef.id.startsWith('ml_test_') ||
        data.hardwareId === 'MOCK_TEST_TOOL' ||
        data.is_synthetic === true
      ) {
        testEntries.push({ ref: entryRef, capturedAt: millis(data.recorded_at) ?? data.captured_at_ms ?? null });
      }
    }
  }

  const syntheticTimes = new Set(testEntries.map(({ capturedAt }) => capturedAt).filter(Number.isFinite));
  const detectionRefs = [];
  const detectionCollections = [
    tankRef.collection('water_quality_anomaly_detections'),
    tankRef.collection('water_quality_anomaly_detection_history'),
  ];
  for (const collection of detectionCollections) {
    for (const docRef of await collection.listDocuments()) {
      const snapshot = await docRef.get();
      const processedSource = millis(snapshot.data()?.source_recorded_at);
      if (processedSource != null && syntheticTimes.has(processedSource)) detectionRefs.push(docRef);
    }
  }

  console.log(`Assigned tank: ${tankId}`);
  console.log(`Explicitly marked synthetic latest-reading documents: ${testLiveRefs.length}`);
  console.log(`Explicitly marked synthetic sensor-history records: ${testEntries.length}`);
  console.log(`WQAD result records tied to those exact source timestamps: ${detectionRefs.length}`);
  if (!confirmDelete) {
    console.log('DRY RUN ONLY. Rerun with --confirm-delete to delete only these marked sensor records and linked WQAD results.');
    return;
  }

  const refs = [...testLiveRefs, ...testEntries.map(({ ref }) => ref), ...detectionRefs];
  for (let start = 0; start < refs.length; start += 450) {
    const batch = db.batch();
    for (const ref of refs.slice(start, start + 450)) batch.delete(ref);
    await batch.commit();
  }
  console.log(`Deleted ${testLiveRefs.length} marked latest records, ${testEntries.length} marked history records, and ${detectionRefs.length} linked WQAD results.`);
}

main().catch((error) => {
  console.error(`Synthetic-record cleanup stopped safely: ${error.message}`);
  process.exitCode = 1;
});
