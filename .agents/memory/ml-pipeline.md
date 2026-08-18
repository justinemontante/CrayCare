---
name: ML pipeline architecture (current schema)
description: Hourly XGBoost WQC flow, Firestore paths, output schema, and minimum data
---

## Canonical flow

The ML pipeline is scheduled once per hour in Asia/Manila.

```
ESP32
  → sensorIngestion/current every ~5s
  → sensorIngestion/current/history every ~10min
      → Node Cloud Functions route to the assigned tank
          → tanks/{tankId}/sensor_readings/latest
          → tanks/{tankId}/sensor_readings_history/{date}/entries/{id}
              → Python run_hourly_wqc reads the last 24h
              → requires at least 6 complete 10-minute records
              → XGBoost WQC (or rule fallback if artifact cannot load)
              → tanks/{tankId}/machine_learning_assessments/current
                  → HealthRiskService snapshot listeners
```

## Output contract

- `level`: Low | Moderate | High | Critical | Insufficient
- `confidence`: 0–100
- `driver`, `driver_label`, `driver_value`, `driver_unit`, `driver_min`, `driver_max`
- `problem`, `insight`, `action`
- `ts_epoch`, `timestamp`, `tank_id`, optional `uid`
- No public numeric risk score.

The pipeline still requires at least six complete 10-minute records internally before producing a full assessment. Incomplete records are skipped; missing sensors must never be converted to zero.

## Model

- `functions/ml/wqc_model.joblib`
- XGBoost multiclass classifier
- 45 engineered features from five sensors
- Synthetic development dataset; not field validation
