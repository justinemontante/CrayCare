# CrayCare — Project Overview

Flutter + Firebase smart-aquaculture app for crayfish farming. The system
monitors water conditions from ESP32 sensors, controls actuators and feeding,
and produces an hourly Machine Learning-Based Water Quality Anomaly Detection.

## Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (Android/iOS/Web) |
| Backend | Firebase Auth, Firestore, Cloud Functions, FCM, Storage |
| WQAD | Python 3.12 + scikit-learn Isolation Forest |
| Hardware | ESP32 with pH, DO, temperature, turbidity, and water-level sensors |
| Repository | `justinemontante/CrayCare`, branch `main` |

## Canonical data flow

```text
ESP32
  → sensorIngestion/current and 10-minute history
  → notification Cloud Functions route readings to the assigned tank
  → tanks/{tankId}/sensor_readings/latest
  → tanks/{tankId}/sensor_readings_history/{date}/entries/{id}
  → hourly Python run_hourly_wqad
  → Machine Learning-Based Water Quality Anomaly Detection
  → tanks/{tankId}/water_quality_anomaly_detections/current + timestamped history
  → WaterQualityAnomalyDetectionService
  → dashboard card, history, reports, and CrayAI insights
```

## Water Quality Anomaly Detection

WQAD learns the usual combined pattern of five water sensors and their recent
temporal features without class labels. It returns `Normal`, `Unusual`, or
`Insufficient`, together with an anomaly percentile, ranked contributors, an
insight, and a verification-focused recommendation. The statistical anomaly
boundary is not a biological safety threshold. Immediate alerts and actuator
decisions remain in the separate sensor-threshold layer.

The model artifact is `functions/ml/wqad_model.joblib`. Its provenance is stored
with every result so the synthetic bootstrap artifact cannot be mistaken for a
field-validated Cherax model.

Important files:

| File | Role |
|---|---|
| `functions/ml/generate_dataset.py` | Generates the synthetic development dataset |
| `functions/ml/train_model.py` | Trains and saves the WQAD model artifact |
| `functions/ml/anomaly_features.py` | Builds 52 multivariate and temporal features and runs anomaly inference |
| `functions/ml/anomaly_interpreter.py` | Produces insights and verification-focused recommendations |
| `functions/ml/main.py` | Exports the hourly `run_hourly_wqad` Cloud Function |
| `functions/ml/predict.py` | Runs a local end-to-end WQAD preview |
| `functions/ml/test_anomaly_detection.py` | Unsupervised-contract and detection tests |
| `functions/ml/test_anomaly_window.py` | Freshness and continuous-history tests |

Twelve complete 10-minute records are required. Missing sensor values are
rejected rather than converted to physically meaningful zeroes.

## Flutter integration

- Service/result: `lib/services/water_quality_anomaly_detection_service.dart`
- Dashboard card: `lib/widgets/dashboard/water_quality_anomaly_detection_card.dart`
- History/export sheet:
  `lib/widgets/dashboard/water_quality_anomaly_detection_history_sheet.dart`
- AI insight sheet: `lib/widgets/analytics/movable_ai_logo.dart`

WQAD reads only the `Normal`, `Unusual`, and `Insufficient` result contract from
`water_quality_anomaly_detections`. Retired classification documents are not
treated as current anomaly-detection results.

## Naming rule

Use **WQAD — Water Quality Anomaly Detection** everywhere. Do not restore retired
earlier module names.

## Current limitations

- The WQAD model is bootstrap-tested on synthetic operating patterns and
  holdout events; event labels are evaluation-only. It is not yet field-validated
  using actual calibrated Cherax RAS history.
- Sensor calibration and physical hardware verification remain required before
  unsupervised production operation.
- Node.js 20 notification functions must be migrated before runtime
  decommissioning.
