---
name: Water Quality Assessment naming
description: WQA is the canonical name across every runtime and documentation layer
---

## Rule

Use **WQA — Water Quality Assessment** for the feature, function, model artifact,
UI, Firestore output, reports, tests, and documentation. Do not restore retired
earlier module names.

The four public assessment conditions are Good, Moderate, Poor, and Critical.
The internal numeric hazard score exists only to generate training targets and
apply the deterministic safety floor. It is not a public assessment output.

## Canonical implementation

- Firebase function: `run_hourly_wqa`
- Model artifact: `functions/ml/wqa_model.joblib`
- Flutter service: `WaterQualityAssessmentService`
- Flutter result: `WaterQualityAssessmentResult`
- Firestore: `tanks/{tankId}/machine_learning_assessments`
- UI: `Water Quality Assessment`

If XGBoost parameters are edited, do not add `use_label_encoder`; it was removed
from XGBoost 2.x and later.
