---
name: ML pipeline architecture (current schema)
description: XGBoost classifier flow, Firestore paths, output schema, model file, and Cloud Function trigger
---

## Rule
The ML pipeline is event-driven — do not add polling or cron triggers.

**Why:** ESP32 writes `sensorIngestion/current` → Cloud Function
(`functions/notifications/index.js`) routes it to
`tanks/{tankId}/sensor_readings/latest` → this triggers the Python Cloud Function
(`functions/ml/main.py`) via Firestore onWrite. Adding a cron would duplicate predictions.

## Flow (current schema)
```
ESP32 (anonymous)
  → writes sensorIngestion/current (every ~5s) + history (every ~10 min)
      → CF routes to tanks/{tankId}/sensor_readings/latest
          → CF (functions/ml/main.py, _predict_wqc) triggers on that doc
              → fetches last 24h from tanks/{tankId}/sensor_readings_history/{date}/entries
                (needs ≥5 readings, single-field where on recorded_at)
              → loads wqc_model.joblib, calls features.predict_wqc()
              → writes result to tanks/{tankId}/health_risk/current
                  → Flutter HealthRiskService (real-time snapshot listener)
                      → dashboard card + AI insights sheet
```

## Firestore output schema (tanks/{tankId}/health_risk/current)
```
level       String   "Low" | "Moderate" | "High" | "Critical" | "Insufficient"
confidence  int      0–100
driver      String   sensor name e.g. "pH", "DO", "temperature"
problem     String   short human-readable problem description
insight     String   detailed analysis with regulatory citations
action      String   recommended corrective action
source      String   "ml" | "insufficient_data" | "rule_based"
timestamp   String   ISO 8601
tank_id     String   stamped by Cloud Function
```

> NO `score` field — was removed. See wqc-rename.md.

## Model details
- File: `functions/ml/wqc_model.joblib`
- Algorithm: XGBoost classifier
- Features: 45 engineered features from 5 sensors
- Training rows: 11,664 (90 days × 10-min intervals, 8 fault types)
- Trained with: `python functions/ml/train_model.py`
- Verified with: `python functions/ml/predict.py`

## Insufficient data fallback
If fewer than 5 readings exist in the last 24h, main.py returns:
```
{ level: "Insufficient", confidence: 0, driver: "N/A", source: "insufficient_data", ... }
```

## How to apply
- To retrain: run `generate_dataset.py` then `train_model.py` then `predict.py` to verify
- Never hardcode the model filename in new code — always use the `wqc_model.joblib` path constant
- Reference: `docs/FIRESTORE_STRUCTURE_ACTUAL.md` (updated 2026-08-01)
