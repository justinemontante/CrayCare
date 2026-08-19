---
name: ML pipeline architecture (current schema)
description: Hourly Machine Learning-Based Water Quality Assessment flow, Firestore paths, output schema, and minimum data
---

## Canonical flow

The Water Quality Assessment runs once per hour in Asia/Manila.

```text
ESP32
  → sensorIngestion/current every ~5s
  → sensorIngestion/current/history every ~10min
  → Node Cloud Functions route readings to the assigned tank
  → tanks/{tankId}/sensor_readings/latest
  → tanks/{tankId}/sensor_readings_history/{date}/entries/{id}
  → Python run_hourly_wqa reads the last 24h
  → requires at least 6 complete 10-minute records
  → XGBoost assessment model determines Good/Moderate/Poor/Critical
  → assessment_interpreter adds concerns, insights, and recommendations
  → tanks/{tankId}/machine_learning_assessments/current and history
  → WaterQualityAssessmentService snapshot listeners
```

## Output contract

- `level`: Good | Moderate | Poor | Critical | Insufficient
- `model_level`, `rule_level`, `safety_override`
- `confidence`: 0–100 when the model is the assessment basis
- `driver`, `driver_label`, `driver_value`, `driver_unit`, `driver_min`, `driver_max`
- `problem`, `insight`, `action`
- `concerns`, `secondary_concerns`
- `ts_epoch`, `timestamp`, `tank_id`, optional `uid`
- No public numeric hazard score

The ML assessment uses 45 engineered temporal features. The deterministic
rolling assessment is a safety floor beneath the ML result. An independently
critical current reading also forces the final condition to Critical.

## Model

- `functions/ml/wqa_model.joblib`
- XGBoost multiclass Water Quality Assessment model
- Synthetic development dataset; not field validation
- Latest local retraining validation (2026-08-19): 12,960 synthetic rows;
  time-series CV accuracy 0.955; effective holdout accuracy 0.981;
  balanced accuracy 0.977
