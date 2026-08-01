---
name: Firestore index requirements (current schema)
description: Queries against the current nested tank schema and their index needs
---

## Rule
The ML Cloud Function (`functions/ml/main.py`) reads history from the NESTED path
`tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries` using a single-field
`.where("recorded_at", ">=", cutoff)` filter — **no composite index required**.
(Indexes needed for the app queries live in `firestore.indexes.json`; see the
`actuator_logs` entries — `actuator_type + timestamp DESC` and
`actuator_type + logged_at DESC`.)

## When to add an index
- Add a composite index to `firestore.indexes.json` ONLY when a new query combines
  `.where(...)` with `.orderBy(...)` on different fields.
- Deploy indexes with: `firebase deploy --only firestore:indexes`
- If the ML pipeline returns `insufficient_data` unexpectedly, check the Cloud
  Function logs for `FAILED_PRECONDITION` — but note the current ML query is a
  single-field filter, so a missing index is unlikely for it.

## Reference
Full canonical structure: `docs/FIRESTORE_STRUCTURE_ACTUAL.md` (updated 2026-08-01).
