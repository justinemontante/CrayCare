---
name: WQC model renaming
description: WQRI was renamed to WQC (Water Quality Classification) everywhere; score field fully removed from all layers
---

## Rule
Never use "WQRI" or "Water Quality Risk Index" anywhere in the codebase. The model is called **WQC — Water Quality Classification**.

**Why:** User confirmed the model classifies water quality level (Low/Moderate/High/Critical) — it is not a risk index. The 0–100 score was internal-only for label generation during training and was removed from all runtime output.

## What was changed
- `functions/ml/features.py` — `predict_wqri` → `predict_wqc`, `compute_wqri_score` → `compute_wqc_score`, `WQRI_NORM_REF` → `WQC_NORM_REF`; `"score"` key removed from returned dict
- `functions/ml/main.py` — `_predict_wqri` → `_predict_wqc`; model path → `wqc_model.joblib`; `"score": 0` removed from insufficient-data fallback; log tags `[WQRI]` → `[WQC]`
- `functions/ml/train_model.py` — saves to `wqc_model.joblib`; removed `use_label_encoder=False` (removed in XGBoost 2.x, crashes on 3.x)
- `functions/ml/predict.py` — updated function call and output
- `functions/ml/generate_dataset.py` — docstring only
- `lib/services/health_risk_service.dart` — `HealthRiskResult` has no `score` field
- `lib/widgets/analytics/movable_ai_logo.dart` — `_buildScoreCard` replaced with `_buildClassificationCard`
- `functions/ml/wqri_model.joblib` — **deleted**; `wqc_model.joblib` is the active model

## How to apply
- Any new ML output field, Flutter model field, or UI widget must NOT reference score or WQRI
- `wqc_model.joblib` is the only model file — do not create `wqri_model.joblib` again
- If XGBoost params are edited, do NOT add `use_label_encoder` — it was removed in XGBoost 2.x+
