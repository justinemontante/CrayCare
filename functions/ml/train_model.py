"""CrayCare — WQRI XGBoost Classifier
=====================================

Trains a Water Quality Risk Index (WQRI) classifier on sensor_dataset.csv
and saves the bundle to wqri_model.joblib.

All thresholds used in label generation are aligned with:
  DENR DAO 2016-08 (Class C Inland Waters)
  DA-BFAR Freshwater Aquaculture Standards
  FAO Fisheries Technical Paper 458
  Boyd & Tucker (1998); Holdich (2002)

See features.py and agency_standards.py for threshold details and citations.

READ BEFORE QUOTING ACCURACY IN A DEFENSE:
──────────────────────────────────────────
1. DATASET IS SYNTHETIC (see generate_dataset.py). Report all metrics as
   "prototype/development-stage validation on synthetic data," NOT field validation.
   Field validation requires real historical sensor data from Firestore.

2. LABELS ARE AUTO-DERIVED from the deterministic compute_wqri_score() formula,
   not independent biological labeling. High accuracy means the model reproduces a
   known formula using richer temporal features — see Stage 1.5 ablation for the
   honest number to cite (temporal features vs. raw readings alone).

3. TimeSeriesSplit uses a `gap` (CV_GAP ticks) so rolling-window features cannot
   "see across" the split boundary — prevents inflated accuracy from autocorrelation.

Usage:
  python train_model.py
  -> wqri_model.joblib  (model bundle)
"""

import os
import numpy as np
import pandas as pd
import joblib
from xgboost import XGBClassifier
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import (
    classification_report, confusion_matrix, accuracy_score, balanced_accuracy_score
)

from features import SENSORS, CLASS_NAMES, build_features, compute_wqri_score, classify

_DIR = os.path.dirname(os.path.abspath(__file__))

# ── Load and label dataset ─────────────────────────────────────────────────────
df = (
    pd.read_csv(os.path.join(_DIR, "sensor_dataset.csv"), parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

# Auto-label via deterministic WQRI formula (see docstring note 2 above)
wqri_score      = compute_wqri_score(df)
df["wqri_score"] = wqri_score.round(1)
df["wqri_class"] = wqri_score.apply(lambda v: classify(v)[0])

print("=" * 65)
print("CrayCare WQRI Classifier — Training")
print("=" * 65)
print(f"Dataset: {len(df):,} rows × {len(df.columns)} columns")
print(f"Date range: {df['timestamp'].min().date()} → {df['timestamp'].max().date()}\n")
print("Label distribution (DENR/DA-BFAR/FAO agency-aligned):")
dist = df["wqri_class"].value_counts().sort_index()
for cls_int, count in dist.items():
    pct  = count / len(df) * 100
    name = CLASS_NAMES[cls_int]
    print(f"  {cls_int} — {name:10s}: {count:6,} rows ({pct:.1f}%)")

# ── Build features ─────────────────────────────────────────────────────────────
feat, _ = build_features(df)
X, y    = feat, df["wqri_class"]

RAW_BASE_COLS = [f"{s}_{stat}" for s in SENSORS for stat in ("avg", "min", "max")]

# CV gap = 36 ticks (6 hours) = rolling-window size, prevents look-ahead leakage
CV_GAP = 36


# ── XGBoost hyperparameters ────────────────────────────────────────────────────
XGB_PARAMS = dict(
    n_estimators        = 500,
    max_depth           = 6,
    learning_rate       = 0.05,
    subsample           = 0.85,
    colsample_bytree    = 0.85,
    min_child_weight    = 3,
    gamma               = 0.1,
    objective           = "multi:softprob",
    num_class           = 4,
    eval_metric         = "mlogloss",
    random_state        = 42,
)


def class_weights(y_series):
    counts  = y_series.value_counts().sort_index()
    weights = len(y_series) / (len(counts) * counts)
    return y_series.map(weights).values


def run_cv(X_subset, label, n_splits=4):
    tscv   = TimeSeriesSplit(n_splits=n_splits, test_size=len(X_subset) // 5, gap=CV_GAP)
    scores = []
    bal_scores = []
    for fold, (train_idx, test_idx) in enumerate(tscv.split(X_subset), 1):
        Xtr, Xte = X_subset.iloc[train_idx], X_subset.iloc[test_idx]
        ytr, yte = y.iloc[train_idx], y.iloc[test_idx]
        sw       = class_weights(ytr)

        m = XGBClassifier(**{k: v for k, v in XGB_PARAMS.items() if k != "early_stopping_rounds"},
                          early_stopping_rounds=20)
        m.fit(Xtr, ytr, sample_weight=sw,
              eval_set=[(Xte, yte)], verbose=False)

        pred  = m.predict(Xte)
        if len(pred.shape) == 2 and pred.shape[1] > 1:
            pred = pred.argmax(axis=1)
        acc  = accuracy_score(yte, pred)
        bacc = balanced_accuracy_score(yte, pred)
        scores.append(acc)
        bal_scores.append(bacc)
        print(f"  [{label}] Fold {fold}: train={len(Xtr):,}  test={len(Xte):,}  "
              f"acc={acc:.3f}  balanced-acc={bacc:.3f}")
    return scores, bal_scores


# ── Stage 1: Time-series CV (full engineered features) ────────────────────────
print("\n" + "=" * 65)
print("STAGE 1 — Time-Series CV (full features, gap=36)")
print("  Thresholds: DENR DAO 2016-08 / DA-BFAR / FAO TP-458")
print("=" * 65)
cv_scores, cv_bal = run_cv(X, "full")
print(f"\n  Mean accuracy         (full): {np.mean(cv_scores):.3f}  ±{np.std(cv_scores):.3f}")
print(f"  Mean balanced-accuracy(full): {np.mean(cv_bal):.3f}  ±{np.std(cv_bal):.3f}")

# ── Stage 1.5: Ablation — raw readings only ───────────────────────────────────
print("\n" + "=" * 65)
print("STAGE 1.5 — Ablation: raw readings only (no rolling/trend features)")
print("=" * 65)
X_raw = X[RAW_BASE_COLS]
cv_raw, cv_raw_bal = run_cv(X_raw, "raw")
gap_pp = (np.mean(cv_scores) - np.mean(cv_raw)) * 100
print(f"\n  Mean accuracy         (raw):  {np.mean(cv_raw):.3f}  ±{np.std(cv_raw):.3f}")
print(f"  Mean accuracy         (full): {np.mean(cv_scores):.3f}  ±{np.std(cv_scores):.3f}")
print(f"  Temporal-feature contribution: {gap_pp:+.1f} percentage points")
print(
    "  -> Cite BOTH in the defense: if gap is small, the model mainly\n"
    "     re-derives the same thresholds the rule-based formula uses;\n"
    "     that is still a valid, honest framing for an early-warning system."
)

# ── Stage 2: Final model on ALL data ──────────────────────────────────────────
print("\n" + "=" * 65)
print("STAGE 2 — Final model: training on full dataset")
print("=" * 65)

split_idx  = int(len(X) * 0.90)
Xtr_f, Xval = X.iloc[:split_idx], X.iloc[split_idx + CV_GAP:]
ytr_f, yval  = y.iloc[:split_idx], y.iloc[split_idx + CV_GAP:]
sw_f         = class_weights(y.iloc[:split_idx])

model = XGBClassifier(**XGB_PARAMS, early_stopping_rounds=20)
model.fit(
    Xtr_f, ytr_f,
    sample_weight=sw_f,
    eval_set=[(Xval, yval)],
    verbose=False,
)

pred_val = model.predict(Xval)
if len(pred_val.shape) == 2 and pred_val.shape[1] > 1:
    pred_val = pred_val.argmax(axis=1)

print("\n── Classification Report (holdout slice, last 10% of timeline) ──")
print(classification_report(
    yval, pred_val,
    labels=[0, 1, 2, 3],
    target_names=CLASS_NAMES,
    zero_division=0.0,
))
print("Confusion matrix (rows=actual, cols=predicted):")
print(pd.DataFrame(
    confusion_matrix(yval, pred_val, labels=[0, 1, 2, 3]),
    index=[f"Actual {n}" for n in CLASS_NAMES],
    columns=[f"Pred {n}" for n in CLASS_NAMES],
).to_string())

# ── Feature importance ─────────────────────────────────────────────────────────
imp = pd.Series(model.feature_importances_, index=X.columns).sort_values(ascending=False)
print(f"\n── Top 15 Features ──")
for fname, fval in imp.head(15).items():
    print(f"  {fname:<35s}: {fval:.4f}")

print("\n── Per-sensor feature importance (grouped sum) ──")
for s in SENSORS:
    s_imp = imp[[c for c in imp.index if c.startswith(s)]].sum()
    print(f"  {s:<15s}: {s_imp:.4f}")

# ── Rule-based baseline comparison ────────────────────────────────────────────
wqri_val   = compute_wqri_score(df.iloc[split_idx + CV_GAP:])
rule_pred  = wqri_val.apply(lambda v: classify(v)[0])
print("\n── Rule-based baseline (same validation slice) ──")
print(classification_report(
    yval, rule_pred,
    labels=[0, 1, 2, 3],
    target_names=CLASS_NAMES,
    zero_division=0.0,
))

# ── Save model bundle ──────────────────────────────────────────────────────────
bundle = {
    "model":    model,
    "features": list(X.columns),
    "type":     "classifier",
    "class_names": CLASS_NAMES,
    "agencies": [
        "DENR DAO 2016-08 (Class C Inland Waters)",
        "DA-BFAR Freshwater Aquaculture Water Quality Standards",
        "FAO Fisheries Technical Paper 458 (Schmittou et al., 2001)",
        "Boyd & Tucker (1998) Pond Aquaculture Water Quality Management",
        "Holdich (2002) Biology of Freshwater Crayfish",
    ],
    "threshold_summary": {
        "DO_min_mgl":       5.0,
        "pH_range":         "6.5–8.5",
        "temp_range_C":     "20–30",
        "turbidity_max_ntu": 50.0,
        "waterLevel_cm":    "120–160",
    },
}
out_path = os.path.join(_DIR, "wqri_model.joblib")
joblib.dump(bundle, out_path)
print(f"\nSaved: wqri_model.joblib")
print(f"  Features:      {len(X.columns)}")
print(f"  Training rows: {len(Xtr_f):,}")
print(f"  Agencies cited: {len(bundle['agencies'])}")
print("\nDone.")
