---
name: ML pipeline architecture
description: XGBoost classifier flow, Firestore paths, output schema, model file, and Cloud Function trigger
---

## Rule
The ML pipeline is event-driven — do not add polling or cron triggers.

**Why:** ESP32 writes `sensorReadings/latest` every ~10 min → triggers Python Cloud Function automatically via Firestore onCreate/onUpdate. Adding a cron would duplicate predictions.

## Flow
```
ESP32 (unauthenticated)
  → writes sensorReadings/latest
      → Cloud Function: functions/ml/main.py (_predict_wqc)
          → fetches last 24h from sensorReadings/history/{date}  (needs ≥5 readings)
          → loads wqc_model.joblib
          → calls features.predict_wqc()
          → writes result to healthRisk/latest
              → Flutter HealthRiskService (real-time snapshot listener)
                  → updates dashboard card + AI insights sheet
```

## Firestore output schema (healthRisk/latest)
```
level       String   "Low" | "Moderate" | "High" | "Critical"
confidence  int      0–100
driver      String   sensor name e.g. "pH", "DO", "temperature"
problem     String   short human-readable problem description
insight     String   detailed analysis with regulatory citations
action      String   recommended corrective action
source      String   "ml" | "insufficient_data" | "rule_based"
timestamp   String   ISO 8601
ownerUid    String   stamped by Cloud Function from config/deviceOwner
```

> NO `score` field — was removed. See wqc-rename.md.

## Model details
- File: `functions/ml/wqc_model.joblib`
- Algorithm: XGBoost classifier
- Features: 45 engineered features from 5 sensors
- Training rows: 11,664 (90 days × 10-min intervals, 8 fault types)
- Holdout accuracy: 92–99% depending on run
- Trained with: `python functions/ml/train_model.py`
- Verified with: `python functions/ml/predict.py`

## Insufficient data fallback
If fewer than 5 readings exist in the last 24h, main.py returns:
```
{ level: "Insufficient", confidence: 0, driver: "N/A", source: "insufficient_data", ... }
```
No score, no model call.

## How to apply
- To retrain: run `generate_dataset.py` then `train_model.py` then `predict.py` to verify
- Never hardcode the model filename in new code — always use the `wqc_model.joblib` path constant
- The composite Firestore index on `sensorReadings/history/{date}` `timestamp ASC` must exist (see firestore-index.md)
