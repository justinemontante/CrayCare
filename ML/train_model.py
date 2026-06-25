import pandas as pd
import numpy as np
import pickle
import os
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import GroupShuffleSplit, GroupKFold, cross_val_score
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix

# ── Load dataset ──────────────────────────────────────────────
df = pd.read_csv("dataset/craycare_dataset_v2.csv")
print(f"[OK] Loaded {len(df):,} rows")
print(f"\nhealth_status distribution:")
print(df["health_status"].value_counts().to_string())
print(f"\nhealth_status distribution (%):")
print((df["health_status"].value_counts(normalize=True) * 100).round(1).to_string())

# ── Feature columns ────────────────────────────────────────────
# NEW vs v1: includes *_minutes_in_zone duration features. These are
# what let the model learn an interaction pattern (severity x duration x
# stage) instead of memorizing a single-snapshot threshold comparison.
FEATURE_COLS = [
    "temperature", "phLevel", "dissolvedOxygen", "turbidity", "waterLevel",
    "temp_rate", "ph_rate", "do_rate", "turb_rate", "wl_rate",
    "temp_minutes_in_zone", "ph_minutes_in_zone", "do_minutes_in_zone",
    "turb_minutes_in_zone", "wl_minutes_in_zone",
    "temp_min", "temp_max",
    "ph_min",   "ph_max",
    "do_min",   "do_max",
    "turb_min", "turb_max",
    "wl_min",   "wl_max",
    "growth_stage",
]

TARGET = "health_status"

# ── Encode categorical columns ────────────────────────────────
encoders = {}

le_stage = LabelEncoder()
df["growth_stage"] = le_stage.fit_transform(df["growth_stage"])
encoders["growth_stage"] = le_stage

le_target = LabelEncoder()
df[TARGET] = le_target.fit_transform(df[TARGET])
encoders[TARGET] = le_target

print(f"\n[OK] Target classes: {list(le_target.classes_)}")

# ── Train / test split — GROUPED BY seq_id ─────────────────────
# IMPORTANT: rows from the same seq_id are highly correlated (they're
# consecutive readings of the same simulated tank event — similar sensor
# values, similar duration-in-zone trajectory). A plain random row split
# leaks information: the model can see "siblings" of a test row during
# training and the test score becomes artificially inflated.
#
# GroupShuffleSplit instead keeps each whole seq_id together in EITHER
# train OR test, never split across both. This gives an honest estimate
# of how the model performs on a genuinely unseen tank event.
X = df[FEATURE_COLS]
y = df[TARGET]
groups = df["seq_id"]

gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)
train_idx, test_idx = next(gss.split(X, y, groups=groups))

X_train, X_test = X.iloc[train_idx], X.iloc[test_idx]
y_train, y_test = y.iloc[train_idx], y.iloc[test_idx]

print(f"\n[OK] Train: {len(X_train):,} rows ({df['seq_id'].iloc[train_idx].nunique()} sequences)")
print(f"[OK] Test:  {len(X_test):,} rows ({df['seq_id'].iloc[test_idx].nunique()} sequences)")
print("[OK] Split is grouped by seq_id — no sequence appears in both train and test.")

# ── Train Random Forest model ─────────────────────────────────
print("\n[Training] Overall Health Status Model...")
model = RandomForestClassifier(
    n_estimators=200,
    max_depth=None,
    min_samples_split=5,
    random_state=42,
    n_jobs=-1,
)
model.fit(X_train, y_train)

# ── Evaluate ──────────────────────────────────────────────────
y_pred = model.predict(X_test)
acc    = accuracy_score(y_test, y_pred)

print(f"\n[Results] Overall accuracy (grouped, honest split): {acc * 100:.2f}%")
print(classification_report(
    y_test, y_pred,
    target_names=le_target.classes_,
    zero_division=0,
))

print("[Confusion Matrix] (rows=actual, cols=predicted)")
print(f"Classes order: {list(le_target.classes_)}")
print(confusion_matrix(y_test, y_pred))

# ── Cross-validation — ALSO grouped by seq_id ───────────────────
# Using GroupKFold instead of plain KFold for the same leakage reason
# as above. This is the number to actually quote in your defense.
print("\n[5-Fold GROUPED Cross-Validation] (honest estimate, no sequence leakage)")
gkf = GroupKFold(n_splits=5)
cv_scores = cross_val_score(model, X, y, cv=gkf, groups=groups, n_jobs=-1)
print(f"Accuracy: {cv_scores.mean()*100:.2f}% (+/- {cv_scores.std()*100:.2f}%)")
print(f"Individual fold scores: {[round(s*100, 2) for s in cv_scores]}")

# ── Feature importance ────────────────────────────────────────
print("\n[Feature Importance] All features, sorted:")
importances = pd.Series(model.feature_importances_, index=FEATURE_COLS)
print(importances.sort_values(ascending=False).to_string())

# ── Sanity check: how much do duration features matter? ────────
duration_cols = [c for c in FEATURE_COLS if "minutes_in_zone" in c]
duration_importance_sum = importances[duration_cols].sum()
print(f"\n[Sanity Check] Combined importance of duration-in-zone features: {duration_importance_sum*100:.2f}%")
print("(If this is near 0%, duration isn't actually being learned — investigate.")
print(" If this dominates everything else, the model may be overly reliant on it.)")

# ── Save model + encoders + feature list ─────────────────────
os.makedirs("models", exist_ok=True)

with open("models/overall_model.pkl", "wb") as f:
    pickle.dump(model, f)

with open("models/encoders.pkl", "wb") as f:
    pickle.dump(encoders, f)

with open("models/feature_cols.pkl", "wb") as f:
    pickle.dump(FEATURE_COLS, f)

print("\n[OK] Saved:")
print("  models/overall_model.pkl   <- the Random Forest model")
print("  models/encoders.pkl        <- stage + health_status encoders")
print("  models/feature_cols.pkl    <- feature column list")
