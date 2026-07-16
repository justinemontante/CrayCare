"""Train CSI-XGBoost -> csi_model.joblib

Uses TimeSeriesSplit for honest evaluation, then trains final model on
all available data for maximum generalization in production.

Uses shared feature engineering from features.py.
"""

import os
import pandas as pd
import numpy as np
import joblib
from xgboost import XGBClassifier
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score

from features import SENSORS, build_features, compute_csi_score, classify

_DIR = os.path.dirname(os.path.abspath(__file__))

df = (
    pd.read_csv(os.path.join(_DIR, "sensor_labeled.csv"), parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

# Build shared features
feat, _ = build_features(df)
X, y = feat, df["csi_class"]

# ── Stage 1: Honest time-series cross-validation ──
print("=" * 60)
print("STAGE 1: Time-Series Cross-Validation (honest estimate)")
print("=" * 60)

tscv = TimeSeriesSplit(n_splits=4, test_size=len(X) // 5)
cv_scores = []

for fold, (train_idx, test_idx) in enumerate(tscv.split(X), 1):
    Xtr_fold, Xte_fold = X.iloc[train_idx], X.iloc[test_idx]
    ytr_fold, yte_fold = y.iloc[train_idx], y.iloc[test_idx]

    # Class-weighting
    class_counts = ytr_fold.value_counts().sort_index()
    weights = len(ytr_fold) / (len(class_counts) * class_counts)
    sample_weight = ytr_fold.map(weights).values

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
    fold_model.fit(Xtr_fold, ytr_fold, sample_weight=sample_weight, verbose=False)

    fold_pred = fold_model.predict(Xte_fold)
    # XGBoost ≥3.x with multi:softprob returns (n, n_classes) probabilities
    if len(fold_pred.shape) == 2 and fold_pred.shape[1] > 1:
        fold_pred = fold_pred.argmax(axis=1)
    acc = accuracy_score(yte_fold, fold_pred)
    cv_scores.append(acc)
    print(f"  Fold {fold}: train={len(Xtr_fold)}, test={len(Xte_fold)}, accuracy={acc:.3f}")

print(f"\n  Mean CV accuracy: {np.mean(cv_scores):.3f} (+/- {np.std(cv_scores):.3f})")

# ── Stage 2: Train final model on ALL data ──
print("\n" + "=" * 60)
print("STAGE 2: Training final model on ALL data")
print("=" * 60)

# Class-weighting on full dataset
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
# For the full-data fit, use a 90/10 holdout from the END for early stopping
split_idx = int(len(X) * 0.9)
Xtr_full, Xval = X.iloc[:split_idx], X.iloc[split_idx:]
ytr_full, yval = y.iloc[:split_idx], y.iloc[split_idx:]

model.fit(
    Xtr_full, ytr_full,
    sample_weight=sample_weight[:split_idx],
    eval_set=[(Xval, yval)],
    verbose=False,
)

pred_full = model.predict(Xval)
# XGBoost ≥3.x with multi:softprob returns (n, n_classes) probas
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
csi_val = compute_csi_score(df.iloc[split_idx:])
rule_pred = csi_val.apply(lambda v: classify(v)[0])
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
    os.path.join(_DIR, "csi_model.joblib"),
)
print("\nSaved csi_model.joblib")
