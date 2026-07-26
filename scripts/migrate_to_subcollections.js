/**
 * migrate_to_subcollections.js
 *
 * One-time migration: moves data from flat root collections
 *   batches/{docId}      { uid, batchId, ... }
 *   sampling/{docId}     { uid, batchId, ... }
 *   mortality/{docId}    { uid, batchId, ... }
 *   activities/{docId}   { uid, batchId, ... }
 *   harvests/{docId}     { uid, batchId, ... }
 *
 * into nested subcollections:
 *   users/{uid}/batches/{batchId}
 *   users/{uid}/batches/{batchId}/sampling/{docId}
 *   users/{uid}/batches/{batchId}/mortality/{docId}
 *   users/{uid}/batches/{batchId}/activities/{docId}
 *   users/{uid}/batches/{batchId}/harvests/{docId}
 *
 * SAFE BY DEFAULT: this script only READS from the old collections and
 * WRITES to the new ones. It never deletes the old data. Run it, verify
 * the new structure in the Firebase console / emulator, THEN run the
 * separate cleanup step (see bottom of file) once you're confident.
 *
 * USAGE:
 *   1. Put a service account key at ./serviceAccountKey.json
 *      (Firebase console > Project settings > Service accounts > Generate new private key)
 *   2. node migrate_to_subcollections.js            # dry run (default) — logs only, no writes
 *   3. node migrate_to_subcollections.js --write     # actually writes to the new structure
 *   4. node migrate_to_subcollections.js --write --delete-old   # also deletes old flat docs
 *      (only run --delete-old after you've verified the migrated data!)
 */

const admin = require("firebase-admin");
const path = require("path");

const args = process.argv.slice(2);
const DRY_RUN = !args.includes("--write");
const DELETE_OLD = args.includes("--delete-old");

const serviceAccountPath = path.join(__dirname, "serviceAccountKey.json");
admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

const db = admin.firestore();

// Collections that are children of a specific batch.
const BATCH_CHILD_COLLECTIONS = ["sampling", "mortality", "activities", "harvests"];

const BATCH_WRITE_LIMIT = 400; // stay comfortably under Firestore's 500-op batch limit

async function commitInChunks(ops) {
  // ops: array of () => void functions that call batch.set/delete etc.
  // We build actual WriteBatch objects here in chunks.
  let batch = db.batch();
  let count = 0;
  let totalCommitted = 0;

  for (const op of ops) {
    op(batch);
    count++;
    totalCommitted++;
    if (count >= BATCH_WRITE_LIMIT) {
      if (!DRY_RUN) await batch.commit();
      batch = db.batch();
      count = 0;
    }
  }
  if (count > 0 && !DRY_RUN) {
    await batch.commit();
  }
  return totalCommitted;
}

async function migrateBatches() {
  console.log("\n=== Migrating batches/ ===");
  const snap = await db.collection("batches").get();
  console.log(`Found ${snap.size} batch documents.`);

  const skipped = [];
  const ops = [];

  snap.forEach((doc) => {
    const data = doc.data();
    const uid = data.uid;
    const batchId = data.batchId || doc.id;

    if (!uid) {
      skipped.push({ docId: doc.id, reason: "missing uid" });
      return;
    }

    const { uid: _uid, ...rest } = data; // drop uid, it's implicit in the path now
    const newRef = db.collection("users").doc(uid).collection("batches").doc(batchId);

    ops.push((batch) => batch.set(newRef, rest, { merge: true }));
  });

  const written = await commitInChunks(ops);
  console.log(`${DRY_RUN ? "[DRY RUN] Would write" : "Wrote"} ${written} batch docs.`);
  if (skipped.length) {
    console.warn(`Skipped ${skipped.length} docs (missing uid):`, skipped);
  }
}

async function migrateChildCollection(name) {
  console.log(`\n=== Migrating ${name}/ ===`);
  const snap = await db.collection(name).get();
  console.log(`Found ${snap.size} ${name} documents.`);

  const skipped = [];
  const ops = [];

  snap.forEach((doc) => {
    const data = doc.data();
    const uid = data.uid;
    const batchId = data.batchId;

    if (!uid || !batchId) {
      skipped.push({ docId: doc.id, reason: !uid ? "missing uid" : "missing batchId" });
      return;
    }

    const { uid: _uid, batchId: _batchId, ...rest } = data; // both now implicit in the path

    const newRef = db
      .collection("users")
      .doc(uid)
      .collection("batches")
      .doc(batchId)
      .collection(name)
      .doc(doc.id); // keep original doc id for traceability

    ops.push((batch) => batch.set(newRef, rest, { merge: true }));
  });

  const written = await commitInChunks(ops);
  console.log(`${DRY_RUN ? "[DRY RUN] Would write" : "Wrote"} ${written} ${name} docs.`);
  if (skipped.length) {
    console.warn(
      `Skipped ${skipped.length} ${name} docs (orphaned — no matching batch):`,
      skipped
    );
  }
  return skipped;
}

async function deleteOldCollections() {
  console.log("\n=== Deleting old flat collections ===");
  const names = ["batches", ...BATCH_CHILD_COLLECTIONS];
  for (const name of names) {
    const snap = await db.collection(name).get();
    const ops = snap.docs.map((doc) => (batch) => batch.delete(doc.ref));
    const count = await commitInChunks(ops);
    console.log(`Deleted ${count} docs from ${name}/`);
  }
}

async function main() {
  console.log(`Mode: ${DRY_RUN ? "DRY RUN (no writes)" : "LIVE WRITE"}`);

  // Batches first — child collections nest under them.
  await migrateBatches();

  const allSkipped = [];
  for (const name of BATCH_CHILD_COLLECTIONS) {
    const skipped = await migrateChildCollection(name);
    allSkipped.push(...skipped.map((s) => ({ collection: name, ...s })));
  }

  console.log("\n=== Summary ===");
  console.log(`Orphaned docs found (no matching uid/batchId): ${allSkipped.length}`);
  if (allSkipped.length) {
    console.log(
      "Review these manually before deleting old data — they were NOT migrated:"
    );
    console.table(allSkipped);
  }

  if (DRY_RUN) {
    console.log(
      "\nThis was a dry run. Re-run with --write to actually copy data to the new structure."
    );
  } else if (DELETE_OLD) {
    if (allSkipped.length > 0) {
      console.log(
        "\nRefusing to auto-delete old collections because orphaned docs were found. " +
        "Resolve them manually, then re-run with just --delete-old separately."
      );
    } else {
      await deleteOldCollections();
    }
  } else {
    console.log(
      "\nMigration written. Old flat collections were left untouched. " +
      "Verify the new users/{uid}/batches/... data, then run again with --write --delete-old to clean up."
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Migration failed:", err);
    process.exit(1);
  });
