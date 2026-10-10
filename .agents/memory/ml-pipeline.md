---
name: WQAD pipeline architecture (current schema)
description: 15-minute Machine Learning-Based Water Quality Anomaly Detection flow, Firestore paths, output schema, and minimum data
---

## Canonical flow

WQAD runs every 15 minutes in Asia/Manila.

```text
ESP32
  → sensorIngestion/current every ~5s
  → sensor history every ~10min
  → Node Cloud Functions route readings to the current CrayCare tank
  → tanks/{tankId}/sensor_readings/latest
  → tanks/{tankId}/sensor_readings_history/{date}/entries/{id}
  → Python run_wqad_analysis reads recent history
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
- `contributors`
- `insight`, `recommendation`
- `source`, `data_status`
- `processed_at` (Timestamp), `tank_id`, optional `uid`

## Model

- `functions/ml/trained_wqad_model.joblib`
- scikit-learn `IsolationForest`
- Unsupervised sensor-derived features only
- Safety thresholds are not ML inputs or labels
- Training provenance: external real freshwater fishpond dataset used as a proxy for CrayCare
- Target-tank field claims require prospective validation using calibrated real CrayCare tank history
