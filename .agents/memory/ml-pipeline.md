---
name: WQAD pipeline architecture (current schema)
description: Hourly Machine Learning-Based Water Quality Anomaly Detection flow, Firestore paths, output schema, and minimum data
---

## Canonical flow

WQAD runs once per hour in Asia/Manila.

```text
ESP32
  → sensorIngestion/current every ~5s
  → sensorIngestion/current/history every ~10min
  → Node Cloud Functions route readings to the assigned tank
  → tanks/{tankId}/sensor_readings/latest
  → tanks/{tankId}/sensor_readings_history/{date}/entries/{id}
  → Python run_hourly_wqad reads recent history
  → anomaly_window keeps the current continuous two-hour pattern
  → requires at least 12 complete ten-minute records
  → IsolationForest evaluates multivariate rarity
  → anomaly_interpreter adds ranked contributors, insight, and recommendation
  → tanks/{tankId}/water_quality_anomaly_detections/current and timestamped history
  → WaterQualityAnomalyDetectionService snapshot listeners
```

## Output contract

- `status`: Normal | Unusual | Insufficient
- `is_anomaly`
- `anomaly_score`: statistical reference-pattern percentile, not a biological risk score
- `driver`, `driver_label`, `driver_value`, `driver_unit`
- `contributors`
- `insight`, `recommendation`
- `source`, `data_status`
- `model_algorithm`, `model_version`, `model_feature_count`
- `training_data_origin`, `training_label_origin`
- `analysis_window_minutes`
- `source_recorded_at`, `source_age_seconds`
- `ts_epoch`, `timestamp`, `tank_id`, optional `uid`

## Model

- `functions/ml/wqad_model.joblib`
- scikit-learn `IsolationForest`
- Unsupervised sensor-derived features only
- Safety thresholds are not ML inputs or labels
- Bundled training provenance: synthetic bootstrap / integration prototype
- Field claims require retraining and validation using calibrated real tank history
