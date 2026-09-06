---
name: WaterQualityAnomalyDetectionResult Flutter model
description: Canonical Flutter result fields for Machine Learning-Based Water Quality Anomaly Detection
---

## Rule

`WaterQualityAnomalyDetectionResult` in
`lib/services/water_quality_anomaly_detection_service.dart` is the canonical
Flutter model for the current WQAD feature.

## Current fields

- `status`: Normal | Unusual | Insufficient
- `isAnomaly`
- `anomalyScore`
- `source`, `modelAlgorithm`, `modelVersion`
- `trainingDataOrigin`, `trainingLabelOrigin`
- `modelFeatureCount`, `analysisWindowMinutes`
- `driver`, `driverLabel`, `driverValue`, `driverUnit`
- `insight`, `recommendation`
- `contributors`
- `timestamp`

`anomalyScore` is a statistical percentile relative to learned reference
patterns. It is not a biological safety or hazard score. Immediate safety
thresholds are handled separately by the app/firmware.
