import pandas as pd
import numpy as np
import pickle
import os
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import accuracy_score, classification_report

# ── Load dataset ──────────────────────────────────────────────
df = pd.read_csv("dataset/craycare_dataset.csv")
print(f"[OK] Loaded {len(df):,} rows")
print(f"\nhealth_status distribution:")
print(df["health_status"].value_counts().to_string())

# ── Feature columns (NO ratios, NO per-sensor status) ─────────
# The model learns from raw sensor values + rates + stage + thresholds
FEATURE_COLS = [
    "temperature", "phLevel", "dissolvedOxygen", "turbidity", "waterLevel",
    "temp_rate", "ph_rate", "do_rate", "turb_rate", "wl_rate",
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

# ── Train / test split ────────────────────────────────────────
X = df[FEATURE_COLS]
y = df[TARGET]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)
print(f"\n[OK] Train: {len(X_train):,} | Test: {len(X_test):,}")

# ── Train ONE Random Forest model ─────────────────────────────
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

print(f"\n[Results] Overall accuracy: {acc * 100:.2f}%")
print(classification_report(
    y_test, y_pred,
    target_names=le_target.classes_,
    zero_division=0,
))

# ── Feature importance ────────────────────────────────────────
print("[Feature Importance] Top 10:")
importances = pd.Series(model.feature_importances_, index=FEATURE_COLS)
print(importances.sort_values(ascending=False).head(10).to_string())

# ── Save model + encoders + feature list ─────────────────────
os.makedirs("models", exist_ok=True)

with open("models/overall_model.pkl", "wb") as f:
    pickle.dump(model, f)

with open("models/encoders.pkl", "wb") as f:
    pickle.dump(encoders, f)

with open("models/feature_cols.pkl", "wb") as f:
    pickle.dump(FEATURE_COLS, f)

print("\n[OK] Saved:")
print("  models/overall_model.pkl   ← the ONE Random Forest model")
print("  models/encoders.pkl        ← stage + health_status encoders")
print("  models/feature_cols.pkl    ← feature column list")
print("\nDone! 🎉")
print("\n--- Defense Note ---")
print("One model predicts overall tank health (OPTIMAL/WARNING/CRITICAL).")
print("Per-sensor insight, prediction, recommendation → expert system in app.py")
print("No data leakage: ratios and per-sensor labels are NOT in the training features.")