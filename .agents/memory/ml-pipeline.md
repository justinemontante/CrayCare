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
              → XGBoost WQC classifies Low/Moderate/High/Critical
              → assessment_interpreter evaluates the latest 1-hour window
                   → primary concern
                   → secondary concerns
                   → recovering conditions
                   → parameter-specific recommendations
                   → safety floor for immediate critical/current abnormalities
              → tanks/{tankId}/machine_learning_assessments/current
                  → HealthRiskService snapshot listeners
```

## Output contract

- `level`: Low | Moderate | High | Critical | Insufficient
- `confidence`: 0–100
- `driver`, `driver_label`, `driver_value`, `driver_unit`, `driver_min`, `driver_max`
- `problem`, `insight`, `action`
- `concerns`: array of structured concern maps containing sensor, label, status, current value/range, recent bad-window count, severity, problem, insight, and action
- `secondary_concerns`: readable labels for all detected concerns after the primary concern
- `ts_epoch`, `timestamp`, `tank_id`, optional `uid`
- No public numeric risk score.

The pipeline still requires at least six complete 10-minute records internally before producing a full assessment. Incomplete records are skipped; missing sensors must never be converted to zero.

## Interpretation behavior

The ML class remains trend-aware and is based on the engineered temporal feature set. The post-ML interpreter does not retrain or replace the class model. It uses the latest six 10-minute windows to explain the class and can identify multiple simultaneous issues. A sensor that has returned to range but was abnormal in at least half of the recent one-hour window is marked `recovering` instead of being immediately forgotten.

For safety, a current sensor condition that crosses an independently defined critical boundary forces the displayed assessment to `Critical`. Likewise, an actively abnormal sensor prevents a `Low` display and raises it to at least `Moderate`.

## Model

- `functions/ml/wqc_model.joblib`
- XGBoost multiclass classifier
- 45 engineered features from five sensors
- Synthetic development dataset; not field validation
- Latest local retraining validation (2026-08-18): 12,960 synthetic rows; holdout accuracy 0.896; balanced accuracy 0.916
