---
name: Firestore composite index requirement
description: sensorReadings/history subcollection needs a composite index on timestamp ASC for the ML Cloud Function query
---

## Rule
`sensorReadings/history/{date}` must have a composite index on `timestamp ASC` in `firestore.indexes.json`.

**Why:** The ML Cloud Function (`functions/ml/main.py`) queries this subcollection with `.where('ownerUid', '==', uid).order_by('timestamp')`. Firestore requires a composite index for combined filter + order_by queries. Without it, the query throws a `FAILED_PRECONDITION` error and the ML pipeline silently returns `insufficient_data`.

## Index definition (already in firestore.indexes.json)
```json
{
  "collectionGroup": "history",
  "queryScope": "COLLECTION_GROUP",
  "fields": [
    { "fieldPath": "ownerUid", "order": "ASCENDING" },
    { "fieldPath": "timestamp", "order": "ASCENDING" }
  ]
}
```

## How to apply
- After any changes to the ML query in `main.py` (new `.where()` or `.order_by()` clauses), check that a matching index exists in `firestore.indexes.json`
- Deploy indexes with: `firebase deploy --only firestore:indexes`
- If the ML pipeline returns `insufficient_data` unexpectedly, check the Cloud Function logs for `FAILED_PRECONDITION` — missing index is the usual cause
