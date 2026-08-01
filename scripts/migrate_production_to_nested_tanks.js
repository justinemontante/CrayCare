/**
 * migrate_production_to_nested_tanks.js
 *
 * One-time migration from the legacy flat production collections:
 *   batches/{docId}
 *   sampling_records/{docId}
 *   mortality_records/{docId}
 *   harvest_records/{docId}
 *   healthRisk/{tankId}
 *
 * into the nested tank-centric structure:
 *   tanks/{tankId}/batches/{batchId}
 *   tanks/{tankId}/batches/{batchId}/sampling_records/{docId}
 *   tanks/{tankId}/batches/{batchId}/mortality_records/{docId}
 *   tanks/{tankId}/batches/{batchId}/harvest_records/{docId}
 *   tanks/{tankId}/health_risk/current
 *
 * SAFE BY DEFAULT:
 *   - default run is DRY RUN (no writes)
 *   - use --write to actually copy data
 *   - use --write --delete-old to also delete legacy flat docs after copy
 *
 * Usage:
 *   1) Put a service account JSON at scripts/serviceAccountKey.json
 *   2) node scripts/migrate_production_to_nested_tanks.js
 *   3) node scripts/migrate_production_to_nested_tanks.js --write
 *   4) node scripts/migrate_production_to_nested_tanks.js --write --delete-old
 */

const admin = require("firebase-admin");
const path = require("path");

const args = process.argv.slice(2);
const DRY_RUN = !args.includes("--write");
const DELETE_OLD = args.includes("--delete-old");
const BATCH_LIMIT = 400;

const serviceAccountPath = path.join(__dirname, "serviceAccountKey.json");
admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

const db = admin.firestore();

async function commitInChunks(ops) {
  let batch = db.batch();
  let count = 0;
  let total = 0;

  for (const op of ops) {
    op(batch);
    count++;
    total++;
    if (count >= BATCH_LIMIT) {
      if (!DRY_RUN) await batch.commit();
      batch = db.batch();
      count = 0;
    }
  }

  if (count > 0 && !DRY_RUN) {
    await batch.commit();
  }
  return total;
}

function tankBatchRef(tankId, batchId) {
  return db.collection("tanks").doc(tankId).collection("batches").doc(batchId);
}

async function migrateBatches() {
  console.log("\n=== Migrating batches -> tanks/{tankId}/batches/{batchId} ===");
  const snap = await db.collection("batches").get();
  console.log(`Found ${snap.size} legacy batch docs.`);

  const skipped = [];
  const ops = [];

  snap.forEach((doc) => {
    const data = doc.data() || {};
    const tankId = data.tankId;
    const batchId = data.batchId || doc.id;
    if (!tankId || !batchId) {
      skipped.push({ docId: doc.id, reason: !tankId ? "missing tankId" : "missing batchId" });
      return;
    }

    const next = {
      ...data,
      batchId,
      tankId,
      migrated_from_doc_id: doc.id,
      migrated_at: admin.firestore.FieldValue.serverTimestamp(),
    };

    ops.push((batch) => batch.set(tankBatchRef(tankId, batchId), next, { merge: true }));

    if (data.status === "active") {
      const tankRef = db.collection("tanks").doc(tankId);
      ops.push((batch) => batch.set(tankRef, {
        current_batch_id: batchId,
        currentBatchId: batchId,
      }, { merge: true }));
    }
  });

  const written = await commitInChunks(ops);
  console.log(`${DRY_RUN ? "[DRY RUN] Would write" : "Wrote"} ${written} batch-related operations.`);
  if (skipped.length) console.table(skipped);
  return skipped;
}

async function migrateBatchChildren(collectionName) {
  console.log(`\n=== Migrating ${collectionName} -> nested batch subcollections ===`);
  const snap = await db.collection(collectionName).get();
  console.log(`Found ${snap.size} legacy ${collectionName} docs.`);

  const skipped = [];
  const ops = [];

  snap.forEach((doc) => {
    const data = doc.data() || {};
    const tankId = data.tankId;
    const batchId = data.batchId;
    if (!tankId || !batchId) {
      skipped.push({
        collection: collectionName,
        docId: doc.id,
        reason: !tankId ? "missing tankId" : "missing batchId",
      });
      return;
    }

    const target = tankBatchRef(tankId, batchId).collection(collectionName).doc(doc.id);
    const next = {
      ...data,
      tankId,
      batchId,
      migrated_from_doc_id: doc.id,
      migrated_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    ops.push((batch) => batch.set(target, next, { merge: true }));
  });

  const written = await commitInChunks(ops);
  console.log(`${DRY_RUN ? "[DRY RUN] Would write" : "Wrote"} ${written} ${collectionName} docs.`);
  if (skipped.length) console.table(skipped);
  return skipped;
}

async function migrateHealthRisk() {
  console.log("\n=== Migrating healthRisk -> tanks/{tankId}/health_risk/current ===");
  const snap = await db.collection("healthRisk").get();
  console.log(`Found ${snap.size} legacy healthRisk docs.`);

  const skipped = [];
  const ops = [];

  snap.forEach((doc) => {
    const data = doc.data() || {};
    const tankId = data.tank_id || data.tankId || doc.id;
    if (!tankId) {
      skipped.push({ docId: doc.id, reason: "missing tank id" });
      return;
    }

    const target = db.collection("tanks").doc(tankId).collection("health_risk").doc("current");
    const next = {
      ...data,
      tank_id: tankId,
      migrated_from_doc_id: doc.id,
      migrated_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    ops.push((batch) => batch.set(target, next, { merge: true }));
  });

  const written = await commitInChunks(ops);
  console.log(`${DRY_RUN ? "[DRY RUN] Would write" : "Wrote"} ${written} health-risk docs.`);
  if (skipped.length) console.table(skipped);
  return skipped;
}

async function deleteLegacyCollection(name) {
  const snap = await db.collection(name).get();
  const ops = snap.docs.map((doc) => (batch) => batch.delete(doc.ref));
  const count = await commitInChunks(ops);
  console.log(`Deleted ${count} legacy docs from ${name}/`);
}

async function main() {
  console.log(`Mode: ${DRY_RUN ? "DRY RUN (no writes)" : "LIVE WRITE"}`);

  const skipped = [];
  skipped.push(...await migrateBatches());
  skipped.push(...await migrateBatchChildren("sampling_records"));
  skipped.push(...await migrateBatchChildren("mortality_records"));
  skipped.push(...await migrateBatchChildren("harvest_records"));
  skipped.push(...await migrateHealthRisk());

  console.log("\n=== Summary ===");
  console.log(`Skipped/orphaned docs: ${skipped.length}`);
  if (skipped.length) console.table(skipped);

  if (DRY_RUN) {
    console.log("\nDry run only. Re-run with --write to apply the migration.");
    return;
  }

  if (!DELETE_OLD) {
    console.log("\nMigration copied data. Legacy flat collections were left untouched.");
    console.log("Verify the new nested data first, then re-run with --write --delete-old if you want cleanup.");
    return;
  }

  if (skipped.length) {
    console.log("\nRefusing to delete old docs because some records were skipped/orphaned. Review them first.");
    return;
  }

  await deleteLegacyCollection("sampling_records");
  await deleteLegacyCollection("mortality_records");
  await deleteLegacyCollection("harvest_records");
  await deleteLegacyCollection("batches");
  await deleteLegacyCollection("healthRisk");
  console.log("\nLegacy flat collections deleted.");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Migration failed:", err);
    process.exit(1);
  });
