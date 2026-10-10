---
name: Water Quality Anomaly Detection naming
description: WQAD is the canonical name across the current runtime and documentation
---

## Rule

Use **WQAD — Machine Learning-Based Water Quality Anomaly Detection** for the
current ML feature. Do not restore the retired WQA/XGBoost classifier contract.

WQAD is an unsupervised multivariate anomaly detector. It reports `Normal`,
`Unusual`, or `Insufficient`; it does not classify water quality as
Good/Moderate/Poor/Critical and it does not expose a biological risk score.
Immediate safety thresholds remain a separate app/firmware feature.

## Canonical implementation

- Firebase function: `run_wqad_analysis`
- Model artifact: `functions/ml/trained_wqad_model.joblib`
- Algorithm: `IsolationForest`
- Flutter service: `WaterQualityAnomalyDetectionService`
- Flutter result: `WaterQualityAnomalyDetectionResult`
- Firestore: `tanks/{tankId}/water_quality_anomaly_detections`
- Current document: `tanks/{tankId}/water_quality_anomaly_detections/current`
- UI terminology: `Water Quality Anomaly Detection` / `WQAD`

The bundled model is trained from an external real freshwater fishpond dataset
used as a proxy for CrayCare. It must not be described as field-validated for
the target crayfish tank until it is prospectively checked against calibrated
real CrayCare tank history.
