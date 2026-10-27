# CrayCare — Project Overview

Flutter + Firebase smart-aquaculture app for crayfish farming. The system
monitors water conditions from ESP32 sensors, controls actuators and feeding,
and produces event-triggered Machine Learning-Based Water Quality Anomaly Detection.

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
  → each eligible new sensor-history entry triggers Python run_wqad_analysis_on_sensor_record
  → Machine Learning-Based Water Quality Anomaly Detection
  → one timestamped result in tanks/{tankId}/water_quality_anomaly_detection_history
  → app uses the newest processed_at history record as latest
  → WaterQualityAnomalyDetectionService
  → dashboard card, history, reports, and CrayAI insights
```

## Water Quality Anomaly Detection

WQAD learns the usual combined pattern of four water-quality sensors and their recent
temporal features without class labels. It returns `Normal`, `Unusual`, or
`Insufficient`, together with an anomaly percentile, ranked contributors, an
insight, and a verification-focused recommendation. The statistical anomaly
boundary is not a biological safety threshold. Immediate alerts and actuator
decisions remain in the separate sensor-threshold layer.

The local model artifact is `functions/ml/trained_wqad_model.joblib`. Its bundle
metadata records that it was trained from an external freshwater fishpond proxy
dataset, which has not been validated for crayfish. The training workflow does
not deploy this local candidate. New model-backed results include compact
`model_metadata` (algorithm, feature version, training-data origin and time,
whether labels were used, and the decision percentile) so the artifact used for
an inference can be identified. Older results and results without model inference
do not contain this field.

The Firebase project was checked on 2026-10-19: it still has an active scheduled
function named `run_wqad_analysis`, while this source exports the Firestore
trigger as `run_wqad_analysis_on_sensor_record`. Firebase does not change a
function's trigger type in place; the new function must be deployed first, then
the old scheduled function removed. Confirm the model artifact included in that
deployment before replacing the live function.

Important files:

| File | Role |
|---|---|
| `functions/ml/train_model.py` | Trains and saves the WQAD model artifact |
| `functions/ml/Dataset.csv` | Four-sensor source dataset used for model training |
| `functions/ml/anomaly_features.py` | Builds 36 multivariate and temporal features and runs anomaly inference |
| `functions/ml/anomaly_interpreter.py` | Produces insights and verification-focused recommendations |
| `functions/ml/main.py` | Exports the Firestore-triggered `run_wqad_analysis_on_sensor_record` Cloud Function |
| `functions/ml/test_anomaly_detection.py` | Unsupervised-contract and detection tests |
| `functions/ml/test_anomaly_window.py` | Freshness and continuous-history tests |

WQAD checks a rolling two-hour window. It requires at least six valid readings
spanning 110 minutes; at the usual 10-minute cadence this is normally about 12
readings, and one missed interval can be tolerated. Missing sensor values are
rejected rather than converted to physically meaningful zeroes.

## Flutter integration

- Service/result: `lib/services/water_quality_anomaly_detection_service.dart`
- Dashboard card: `lib/widgets/dashboard/water_quality_anomaly_detection_card.dart`
- History/export sheet:
  `lib/widgets/dashboard/water_quality_anomaly_detection_history_sheet.dart`
- AI insight sheet: `lib/widgets/analytics/movable_ai_logo.dart`

WQAD listens to the canonical `water_quality_anomaly_detection_history`
collection. For compatibility, it also reads timestamped documents once from
the legacy `water_quality_anomaly_detections` collection; it ignores that
collection's old `current` document. Current results use the `Normal`,
`Unusual`, and `Insufficient` status contract.

## Naming rule

Use **WQAD — Water Quality Anomaly Detection** everywhere. Do not restore retired
earlier module names.

## Current limitations

- The external training data has no anomaly outcome labels. Its holdout alert
  rate is not an accuracy measure. Synthetic checks exercise software behavior
  only; they do not establish detection accuracy. WQAD is not yet field-validated
  using calibrated sensor history from the target crayfish tank.
- Sensor calibration and physical hardware verification remain required before
  unsupervised production operation.
- Node.js 20 notification functions must be migrated before runtime
  decommissioning.
