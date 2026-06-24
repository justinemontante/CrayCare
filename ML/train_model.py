import pandas as pd
import numpy as np
import pickle
import os
from sklearn.ensemble import RandomForestClassifier
from sklearn.multioutput import MultiOutputClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import accuracy_score, classification_report

# ─────────────────────────────────────────────────────────────
# LOAD DATASET
# ─────────────────────────────────────────────────────────────
df = pd.read_csv("dataset/craycare_dataset.csv")
print(f"[OK] Loaded {len(df):,} rows")

# ─────────────────────────────────────────────────────────────
# FEATURES & TARGETS
# ─────────────────────────────────────────────────────────────
FEATURE_COLS = [
    "temperature", "phLevel", "dissolvedOxygen", "turbidity", "waterLevel",
    "temp_rate", "ph_rate", "do_rate", "turb_rate", "wl_rate",
    "temp_min", "temp_max", "ph_min", "ph_max",
    "do_min", "do_max", "turb_min", "turb_max", "wl_min", "wl_max",
    "temp_ratio", "ph_ratio", "do_ratio", "turb_ratio", "wl_ratio",
    "stage"
]

SENSOR_TARGETS = [
    "temp_status", "ph_status", "do_status", "turb_status", "wl_status"
]

OVERALL_TARGET = "status"

# ─────────────────────────────────────────────────────────────
# ENCODE CATEGORICAL COLUMNS
# ─────────────────────────────────────────────────────────────
encoders = {}

# Encode stage
le_stage = LabelEncoder()
df["stage"] = le_stage.fit_transform(df["stage"])
encoders["stage"] = le_stage

# Encode sensor status targets
for col in SENSOR_TARGETS + [OVERALL_TARGET]:
    le = LabelEncoder()
    df[col] = le.fit_transform(df[col])
    encoders[col] = le

print(f"[OK] Label classes:")
for col in SENSOR_TARGETS + [OVERALL_TARGET]:
    print(f"  {col}: {list(encoders[col].classes_)}")

# ─────────────────────────────────────────────────────────────
# PREPARE X and Y
# ─────────────────────────────────────────────────────────────
X = df[FEATURE_COLS]
Y_sensor  = df[SENSOR_TARGETS]
Y_overall = df[OVERALL_TARGET]

# Train/test split
X_train, X_test, Ys_train, Ys_test, Yo_train, Yo_test = train_test_split(
    X, Y_sensor, Y_overall, test_size=0.2, random_state=42
)

print(f"\n[OK] Train: {len(X_train):,} | Test: {len(X_test):,}")

# ─────────────────────────────────────────────────────────────
# MODEL 1 — MULTI-OUTPUT (5 sensor statuses simultaneously)
# ─────────────────────────────────────────────────────────────
print("\n[Training] Sensor Status Model (multi-output)...")

sensor_model = MultiOutputClassifier(
    RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)
)
sensor_model.fit(X_train, Ys_train)

Ys_pred = sensor_model.predict(X_test)

print("[Results] Per-sensor accuracy:")
for i, col in enumerate(SENSOR_TARGETS):
    acc = accuracy_score(Ys_test.iloc[:, i], Ys_pred[:, i])
    print(f"  {col}: {acc*100:.2f}%")
    print(classification_report(
        Ys_test.iloc[:, i], Ys_pred[:, i],
        target_names=encoders[col].classes_,
        zero_division=0
    ))

# ─────────────────────────────────────────────────────────────
# MODEL 2 — OVERALL HEALTH STATUS
# ─────────────────────────────────────────────────────────────
print("\n[Training] Overall Health Model...")

overall_model = RandomForestClassifier(
    n_estimators=100, random_state=42, n_jobs=-1
)
overall_model.fit(X_train, Yo_train)

Yo_pred = overall_model.predict(X_test)
overall_acc = accuracy_score(Yo_test, Yo_pred)

print(f"[Results] Overall accuracy: {overall_acc*100:.2f}%")
print(classification_report(
    Yo_test, Yo_pred,
    target_names=encoders[OVERALL_TARGET].classes_,
    zero_division=0
))

# ─────────────────────────────────────────────────────────────
# SAVE MODELS + ENCODERS
# ─────────────────────────────────────────────────────────────
os.makedirs("models", exist_ok=True)

with open("models/sensor_model.pkl", "wb") as f:
    pickle.dump(sensor_model, f)

with open("models/overall_model.pkl", "wb") as f:
    pickle.dump(overall_model, f)

with open("models/encoders.pkl", "wb") as f:
    pickle.dump(encoders, f)

with open("models/feature_cols.pkl", "wb") as f:
    pickle.dump(FEATURE_COLS, f)

print("\n[OK] Saved:")
print("  models/sensor_model.pkl")
print("  models/overall_model.pkl")
print("  models/encoders.pkl")
print("  models/feature_cols.pkl")
print("\nDone! 🎉")