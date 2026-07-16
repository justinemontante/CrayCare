"""Train WQRI-XGBoost -> wqri_model.joblib

Water Quality Risk Index (WQRI) — formerly called "CSI" (Crayfish Stress
Index). Renamed because the score is a water-quality hazard proxy derived
purely from sensor deviations, not a direct physiological stress measurement.

READ BEFORE QUOTING ACCURACY NUMBERS IN A PAPER/DEFENSE:

1. DATASET IS SYNTHETIC (see generate_dataset.py) — sine-wave diurnal
   patterns + injected fault events, not real pond sensor data. Report all
   metrics below as prototype/development-stage validation, not field
   validation. Real-sensor data validation is needed before claiming this
   works in production.

2. THE LABEL IS AUTO-DERIVED, not independently/biologically labeled
   (see features.py). High accuracy mostly shows the model can reproduce a
   known deterministic formula using richer temporal features than the
   formula itself uses — it does not by itself prove biological validity.
   Stage 1.5 below measures how much the temporal/trend engineering adds
   over raw instantaneous readings, so you have an honest number to defend
   instead of just the full-feature accuracy.

3. TimeSeriesSplit now uses a `gap` between train and test folds so that
   rolling-window features can't "see across" the split boundary. Without
   this, samples straddling the boundary are highly autocorrelated
   (10-minute intervals barely change) and inflate reported accuracy.

Uses shared feature engineering from features.py.
"""

import os
import pandas as pd
import numpy as np
import joblib
from xgboost import XGBClassifier
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score

from features import SENSORS, build_features, compute_wqri_score, classify

_DIR = os.path.dirname(os.path.abspath(__file__))
RAW_BASE_COLS = [f"{s}_{stat}" for s in SENSORS for stat in ("avg", "min", "max")]

df = (
    pd.read_csv(os.path.join(_DIR, "sensor_labeled.csv"), parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

# Build shared features
feat, _ = build_features(df)
X, y = feat, df["wqri_class"]

# Gap = 36 ticks (6 hours) = the rolling-window size used by build_features,
# so no test-fold row can have a rolling feature that reaches back into the
# training fold on the other side of the boundary.
CV_GAP = 36


def run_cv(X_subset, label, n_splits=4):
    """Run TimeSeriesSplit CV (with gap) on X_subset, return fold accuracies."""
    tscv = TimeSeriesSplit(n_splits=n_splits, test_size=len(X_subset) // 5, gap=CV_GAP)
    scores = []
    for fold, (train_idx, test_idx) in enumerate(tscv.split(X_subset), 1):
        Xtr, Xte = X_subset.iloc[train_idx], X_subset.iloc[test_idx]
        ytr, yte = y.iloc[train_idx], y.iloc[test_idx]

        class_counts = ytr.value_counts().sort_index()
        weights = len(ytr) / (len(class_counts) * class_counts)
        sample_weight = ytr.map(weights).values

        fold_model = XGBClassifier(
            n_estimators=200,
            max_depth=5,
            learning_rate=0.05,
            subsample=0.9,
            colsample_bytree=0.9,
            objective="multi:softprob",
            num_class=4,
            eval_metric="mlogloss",
            random_state=42,
        )
        fold_model.fit(Xtr, ytr, sample_weight=sample_weight, verbose=False)

        pred = fold_model.predict(Xte)
        if len(pred.shape) == 2 and pred.shape[1] > 1:
            pred = pred.argmax(axis=1)
        acc = accuracy_score(yte, pred)
        scores.append(acc)
        print(f"  [{label}] Fold {fold}: train={len(Xtr)}, test={len(Xte)}, accuracy={acc:.3f}")
    return scores


# ── Stage 1: Honest time-series cross-validation (full engineered features) ──
print("=" * 60)
print("STAGE 1: Time-Series CV - full engineered features (gap=36)")
print("=" * 60)
cv_scores = run_cv(X, "full")
print(f"\n  Mean CV accuracy (full features): {np.mean(cv_scores):.3f} (+/- {np.std(cv_scores):.3f})")

# ── Stage 1.5: Ablation - raw instantaneous readings only ──
print("\n" + "=" * 60)
print("STAGE 1.5: Ablation - raw readings only (no rolling/trend features)")
print("=" * 60)
X_raw = X[RAW_BASE_COLS]
cv_scores_raw = run_cv(X_raw, "raw-only")
gap_pp = (np.mean(cv_scores) - np.mean(cv_scores_raw)) * 100
print(f"\n  Mean CV accuracy (raw-only):      {np.mean(cv_scores_raw):.3f} (+/- {np.std(cv_scores_raw):.3f})")
print(f"  Mean CV accuracy (full features):  {np.mean(cv_scores):.3f} (+/- {np.std(cv_scores):.3f})")
print(f"  Temporal-feature contribution:     {gap_pp:+.1f} percentage points")
print(
    "  -> Report BOTH numbers in the defense. If the gap is small, most of\n"
    "     the accuracy comes from the model re-deriving the same\n"
    "     instantaneous thresholds the rule-based formula already uses, not\n"
    "     from new temporal signal -- that's an honest, defensible framing."
)

# ── Stage 2: Train final model on ALL data ──
print("\n" + "=" * 60)
print("STAGE 2: Training final model on ALL data")
print("=" * 60)

class_counts = y.value_counts().sort_index()
weights = len(y) / (len(class_counts) * class_counts)
sample_weight = y.map(weights).values

model = XGBClassifier(
    n_estimators=500,
    max_depth=5,
    learning_rate=0.05,
    subsample=0.9,
    colsample_bytree=0.9,
    objective="multi:softprob",
    num_class=4,
    eval_metric="mlogloss",
    early_stopping_rounds=20,
    random_state=42,
)
# 90/10 holdout from the END for early stopping, with the same gap applied
# so the holdout isn't artificially easy either.
split_idx = int(len(X) * 0.9)
Xtr_full, Xval = X.iloc[:split_idx], X.iloc[split_idx + CV_GAP:]
ytr_full, yval = y.iloc[:split_idx], y.iloc[split_idx + CV_GAP:]

model.fit(
    Xtr_full, ytr_full,
    sample_weight=sample_weight[:split_idx],
    eval_set=[(Xval, yval)],
    verbose=False,
)

pred_full = model.predict(Xval)
if len(pred_full.shape) == 2 and pred_full.shape[1] > 1:
    pred_full = pred_full.argmax(axis=1)
print(
    classification_report(
        yval,
        pred_full,
        labels=[0, 1, 2, 3],
        target_names=["Low", "Moderate", "High", "Critical"],
        zero_division=0.0,
    )
)
print("Confusion matrix:\n", confusion_matrix(yval, pred_full, labels=[0, 1, 2, 3]))

# Feature importance
imp = pd.Series(model.feature_importances_, index=X.columns).sort_values(
    ascending=False
)
print("\nTop 10 features:\n", imp.head(10))

# Compare with rule-based baseline on the same validation slice
wqri_val = compute_wqri_score(df.iloc[split_idx + CV_GAP:])
rule_pred = wqri_val.apply(lambda v: classify(v)[0])
print("\n--- Rule-based baseline (validation slice) ---")
print(
    classification_report(
        yval,
        rule_pred,
        labels=[0, 1, 2, 3],
        target_names=["Low", "Moderate", "High", "Critical"],
        zero_division=0.0,
    )
)

# Save
joblib.dump(
    {"model": model, "features": list(X.columns)},
    os.path.join(_DIR, "wqri_model.joblib"),
)
print("\nSaved wqri_model.joblib")
