# CrayCare — Project Overview

Flutter + Firebase smart-aquaculture app for crayfish farming. The system
monitors water conditions from ESP32 sensors, controls actuators and feeding,
and produces an hourly Machine Learning-Based Water Quality Assessment.

## Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (Android/iOS/Web) |
| Backend | Firebase Auth, Firestore, Cloud Functions, FCM, Storage |
| Assessment | Python 3.12 + XGBoost |
| Hardware | ESP32 with pH, DO, temperature, turbidity, and water-level sensors |
| Repository | `justinemontante/CrayCare`, branch `main` |

## Canonical data flow

```text
ESP32
  → sensorIngestion/current and 10-minute history
  → notification Cloud Functions route readings to the assigned tank
  → tanks/{tankId}/sensor_readings/latest
  → tanks/{tankId}/sensor_readings_history/{date}/entries/{id}
  → hourly Python run_hourly_wqa
  → Machine Learning-Based Water Quality Assessment
  → tanks/{tankId}/machine_learning_assessments/current + timestamped history
  → WaterQualityAssessmentService
  → dashboard card, history, reports, and CrayAI insights
```

## Water Quality Assessment

The assessment combines five sensor parameters and their recent temporal
features to determine one of four public conditions:

- Good
- Moderate
- Poor
- Critical

The model artifact is `functions/ml/wqa_model.joblib`. The internal numeric
hazard score is used only for training targets and the deterministic safety
floor; it is not written as a public assessment result.

Important files:

| File | Role |
|---|---|
| `functions/ml/generate_dataset.py` | Generates the synthetic development dataset |
| `functions/ml/train_model.py` | Trains and saves the WQA model artifact |
| `functions/ml/features.py` | Builds 45 temporal features and the safety floor |
| `functions/ml/assessment_interpreter.py` | Produces concerns, insights, and recommendations |
| `functions/ml/main.py` | Exports the hourly `run_hourly_wqa` Cloud Function |
| `functions/ml/predict.py` | Runs a local end-to-end assessment preview |
| `functions/ml/test_assessment.py` | Assessment label and safety regression tests |

At least six complete 10-minute records are required. Missing sensor values are
rejected rather than converted to physically meaningful zeroes.

## Flutter integration

- Service/result: `lib/services/water_quality_assessment_service.dart`
- Dashboard card: `lib/widgets/dashboard/water_quality_assessment_card.dart`
- History/export sheet:
  `lib/widgets/dashboard/water_quality_assessment_history_sheet.dart`
- AI insight sheet: `lib/widgets/analytics/movable_ai_logo.dart`

Legacy Firestore `Low` and `High` values are normalized to `Good` and `Poor`
when read, so old assessment history remains usable.

## Naming rule

Use **WQA — Water Quality Assessment** everywhere. Do not restore retired
earlier module names.

## Current limitations

- The assessment model is prototype-validated on synthetic, formula-labeled
  data; it is not yet field-validated biological ground truth.
- Sensor calibration and physical hardware verification remain required before
  unsupervised production operation.
- Node.js 20 notification functions must be migrated before runtime
  decommissioning.
