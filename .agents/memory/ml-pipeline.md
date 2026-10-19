---
name: WQAD pipeline architecture (current schema)
description: History-triggered Machine Learning-Based Water Quality Anomaly Detection flow, Firestore paths, output schema, and minimum data

---

## Canonical flow

WQAD runs once per fresh ten-minute history record, in Asia/Manila. It is
event-driven on the history collection, not on a fixed schedule.

```text
ESP32
  → tanks/{tankId}/sensor_readings/latest (live snapshot)
  → tanks/{tankId}/sensor_readings_history/{date}/entries/{id} (ten-minute mean)
  → Node Cloud Functions route readings to the current CrayCare tank
  → Python run_wqad_analysis triggers on each new history entry
  → anomaly_window keeps the current continuous two-hour pattern
  → requires at least six valid readings spanning 110 minutes
  → IsolationForest evaluates multivariate rarity
  → anomaly_interpreter adds ranked contributors, insight, and recommendation
  → tanks/{tankId}/water_quality_anomaly_detection_history/{YYYYMMDDTHHMMSS}
  → WaterQualityAnomalyDetectionService snapshot listeners
```

Window rules, from `anomaly_window.py`:

- The window uses actual capture times, not an assumed record count.
- The observed cadence must be between 480 and 1800 seconds.
- A gap larger than 2.2 times the observed cadence restarts the window.
- Missing readings are never interpolated.
- A newest record older than 20 minutes is reported as stale.

Trigger guards, from `main.py`:

- A record with a missing, future, or offline-backfilled timestamp is skipped.
- The record must match the active hardware assignment, tank id, owner uid, and
  assignment timestamp.
- The result document id is source-keyed, so a retried event creates one record.
- An older event never replaces a newer result.

## Output contract

- `status`: Normal | Unusual | Insufficient
- `is_anomaly`
- `anomaly_score`: statistical reference-pattern percentile, not a biological risk score
- `contributors`: ranked array of sensor, value, direction, contribution_score
- `insight`, `recommendation`
- `source`
- `processed_at` (Timestamp), `tank_id`, optional `uid`
- `source_recorded_at` (Timestamp): newest reading used for the result

There is no separate `current` document. The app treats the newest
`processed_at` record in the history collection as the latest result.
`data_status` is not persisted in the result document.

The former `water_quality_anomaly_detections` collection is legacy-only. Its
timestamped documents stay readable during transition, but its old `current`
document is ignored and no longer updated.

## Model

- `functions/ml/trained_wqad_model.joblib`
- scikit-learn `IsolationForest`, feature version 3, 300 trees
- Unsupervised sensor-derived features only
- Safety thresholds are not ML inputs or labels
- Four water-quality sensors only: temperature, pH, dissolved oxygen, turbidity
- Water level and feed level are outside the ML input
- Decision basis: independent chronological calibration percentile, fixed at the
  98th percentile, with a purged holdout
- Training provenance: external real freshwater fishpond dataset used as a proxy
  for CrayCare
- Target-tank field claims require prospective validation using calibrated real
  CrayCare tank history
