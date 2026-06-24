"""
CrayCare ML Training Pipeline v2
=================================
Simplified, defendable architecture:
  Model 1: craycare_health_prediction_model.pkl  → predicts overall health (Healthy / Moderate Risk / High Risk)
  Model 2: craycare_sensor_risk_model.pkl         → predicts primary risk sensor

Insight  → rule-based (NOT ML)
Recommendation → rule-based (NOT ML)

Output files (saved to models/):
  - craycare_dataset_v2.csv
  - craycare_health_prediction_model.pkl
  - craycare_sensor_risk_model.pkl
  - label_encoders.pkl
  - training_summary.json
"""

import os, json, random, math
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score
import joblib

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "models")
os.makedirs(OUTPUT_DIR, exist_ok=True)

random.seed(42)
np.random.seed(42)

N_SAMPLES = 10000

STAGES = ["early_juvenile", "advanced_juvenile", "pre_adult", "market_size"]

STAGE_RANGES = {
    "early_juvenile": {
        "temp": (26.0, 28.0),
        "ph": (7.5, 8.0),
        "do": (5.0, 999.0),
        "turb": (0.0, 25.0),
        "waterlevel": (120.0, 160.0),
    },
    "advanced_juvenile": {
        "temp": (25.0, 30.0),
        "ph": (7.0, 8.5),
        "do": (5.0, 999.0),
        "turb": (0.0, 30.0),
        "waterlevel": (120.0, 170.0),
    },
    "pre_adult": {
        "temp": (24.0, 30.0),
        "ph": (7.0, 8.5),
        "do": (4.5, 999.0),
        "turb": (0.0, 35.0),
        "waterlevel": (130.0, 180.0),
    },
    "market_size": {
        "temp": (24.0, 28.0),
        "ph": (7.0, 8.0),
        "do": (4.0, 999.0),
        "turb": (0.0, 40.0),
        "waterlevel": (130.0, 180.0),
    },
}

SENSOR_INFO = [
    ("temp", 15.0, 40.0),
    ("ph", 5.0, 10.0),
    ("do", 0.0, 12.0),
    ("turb", 0.0, 200.0),
    ("waterlevel", 50.0, 250.0),
]

STAGE_WEIGHTS = [0.15, 0.30, 0.40, 0.15]


def pick_stage():
    return random.choices(STAGES, weights=STAGE_WEIGHTS, k=1)[0]


def clip(val, lo, hi):
    return max(lo, min(hi, val))


def generate_sensor_value(sensor_name, stage, anomaly_chance=0.08):
    lo, hi = SENSOR_INFO[[s[0] for s in SENSOR_INFO].index(sensor_name)][1:]
    s_lo, s_hi = STAGE_RANGES[stage].get(sensor_name, (lo, hi))
    if sensor_name == "do":
        s_lo = STAGE_RANGES[stage]["do"][0]
        s_hi = 999.0
    is_anomaly = random.random() < anomaly_chance

    if is_anomaly:
        if sensor_name == "do":
            val = random.uniform(1.0, max(s_lo - 1.5, 0.5))
        elif sensor_name == "turb":
            val = random.uniform(s_hi + 5.0, min(s_hi + 60.0, hi))
        elif sensor_name == "ph":
            if random.random() < 0.5:
                val = random.uniform(5.0, s_lo - 0.3)
            else:
                val = random.uniform(s_hi + 0.3, 9.5)
        elif sensor_name == "temp":
            if random.random() < 0.5:
                val = random.uniform(lo, s_lo - 1.0)
            else:
                val = random.uniform(s_hi + 1.0, hi)
        else:
            if random.random() < 0.5:
                val = random.uniform(lo, s_lo - 5.0)
            else:
                val = random.uniform(s_hi + 5.0, hi)
        return clip(round(val, 2), lo, hi)

    center = (s_lo + s_hi) / 2 if s_hi < 900 else s_lo * 1.3
    spread = (s_hi - s_lo) / 4 if s_hi < 900 else s_lo * 0.3
    if sensor_name == "do":
        center = s_lo * 1.4
        spread = s_lo * 0.3
    elif sensor_name == "turb":
        center = s_hi * 0.4
        spread = s_hi * 0.2
    val = np.random.normal(center, spread)
    return clip(round(val, 2), lo, hi)


def generate_rate():
    return round(np.random.uniform(-0.3, 0.3), 4)


def compute_health_status(row, stage):
    ranges = STAGE_RANGES[stage]
    issues = 0
    criticals = 0

    for sn, (s_lo, s_hi) in ranges.items():
        val = row[sn]
        if sn == "do":
            if val < 3.0:
                criticals += 1
            elif val < s_lo:
                issues += 1
        elif sn == "turb":
            if val > s_hi * 1.5:
                criticals += 1
            elif val > s_hi:
                issues += 1
        else:
            if val < s_lo * 0.7 or val > s_hi * 1.3:
                criticals += 1
            elif val < s_lo or val > s_hi:
                issues += 1

    if criticals >= 1 or issues >= 3:
        return "High Risk"
    elif issues >= 1 or criticals > 0:
        return "Moderate Risk"
    return "Healthy"


def compute_primary_risk(row, stage):
    ranges = STAGE_RANGES[stage]
    deviations = []

    for sn, (s_lo, s_hi) in ranges.items():
        val = row[sn]
        if sn == "do":
            if val < 3.0:
                dev = 999.0
            elif val < s_lo:
                dev = (s_lo - val) / max(s_lo, 0.1)
            else:
                dev = 0.0
        elif sn == "turb":
            if val > s_hi * 1.5:
                dev = 999.0
            elif val > s_hi:
                dev = (val - s_hi) / max(s_hi, 0.1)
            else:
                dev = 0.0
        else:
            if val < s_lo * 0.7 or val > s_hi * 1.3:
                dev = 999.0
            elif val < s_lo:
                dev = (s_lo - val) / max(s_lo, 0.1)
            elif val > s_hi:
                dev = (val - s_hi) / max(s_hi, 0.1)
            else:
                dev = 0.0
        deviations.append((sn, dev))

    deviations.sort(key=lambda x: -x[1])
    top_dev = deviations[0][1]
    if top_dev == 0.0:
        return "None"

    tied = [d for d in deviations if d[1] >= top_dev * 0.8 and d[1] > 0]
    if len(tied) >= 2:
        return "Multiple Risks"

    risk_map = {
        "temp": "Temperature Risk",
        "ph": "PH Risk",
        "do": "DO Risk",
        "turb": "Turbidity Risk",
        "waterlevel": "Water Level Risk",
    }
    return risk_map.get(deviations[0][0], "Multiple Risks")


print("=" * 60)
print("CrayCare ML Training v2")
print("=" * 60)
print(f"\nGenerating {N_SAMPLES} synthetic records...")

FEATURE_COLS = [
    "temperature",
    "phLevel",
    "dissolvedOxygen",
    "turbidity",
    "waterLevel",
    "temp_rate",
    "ph_rate",
    "do_rate",
    "turb_rate",
    "wl_rate",
]
SENSOR_SHORT = ["temp", "ph", "do", "turb", "waterlevel"]

records = []
for i in range(N_SAMPLES):
    stage = pick_stage()
    row = {"stage": stage}
    raw = {}
    for sn in SENSOR_SHORT:
        raw[sn] = generate_sensor_value(sn, stage)
    row["temperature"] = raw["temp"]
    row["phLevel"] = raw["ph"]
    row["dissolvedOxygen"] = raw["do"]
    row["turbidity"] = raw["turb"]
    row["waterLevel"] = raw["waterlevel"]
    row["temp_rate"] = generate_rate()
    row["ph_rate"] = generate_rate()
    row["do_rate"] = generate_rate()
    row["turb_rate"] = generate_rate()
    row["wl_rate"] = generate_rate()
    row["health_status"] = compute_health_status(raw, stage)
    row["primary_risk"] = compute_primary_risk(raw, stage)
    records.append(row)

df = pd.DataFrame(records)

print(f"\nHealth status distribution:")
print(df["health_status"].value_counts())
print(f"\nPrimary risk distribution:")
print(df["primary_risk"].value_counts())
print(f"\nStage distribution:")
print(df["stage"].value_counts())

csv_path = os.path.join(OUTPUT_DIR, "craycare_dataset_v2.csv")
df.to_csv(csv_path, index=False)
print(f"\n[OK] Dataset saved -> {csv_path}")

print("\n" + "=" * 60)
print("Training Models")
print("=" * 60)

stage_map = {s: i for i, s in enumerate(STAGES)}
df["stage_enc"] = df["stage"].map(stage_map)

risk_map = {r: i for i, r in enumerate(sorted(df["primary_risk"].unique()))}
df["risk_enc"] = df["primary_risk"].map(risk_map)

health_map = {h: i for i, h in enumerate(sorted(df["health_status"].unique()))}
df["health_enc"] = df["health_status"].map(health_map)

MODEL_FEATURES = FEATURE_COLS + ["stage_enc"]

X = df[MODEL_FEATURES]
y_health = df["health_enc"]
y_risk = df["risk_enc"]

X_train, X_test, yh_train, yh_test = train_test_split(
    X, y_health, test_size=0.20, random_state=42
)
_, _, yr_train, yr_test = train_test_split(X, y_risk, test_size=0.20, random_state=42)

# ── Model 1: Health Prediction ───────────────────────────────────────────────
print("\n[1/2] Training craycare_health_prediction_model.pkl ...")
health_clf = RandomForestClassifier(
    n_estimators=200, max_depth=14, random_state=42, n_jobs=-1, class_weight="balanced"
)
health_clf.fit(X_train, yh_train)
yh_pred = health_clf.predict(X_test)
health_acc = accuracy_score(yh_test, yh_pred)
inv_health_map = {v: k for k, v in health_map.items()}
yh_test_labels = [inv_health_map[y] for y in yh_test]
yh_pred_labels = [inv_health_map[y] for y in yh_pred]
print(f"  Accuracy: {health_acc:.4f}")
print(classification_report(yh_test_labels, yh_pred_labels, zero_division=0))

health_model_path = os.path.join(OUTPUT_DIR, "craycare_health_prediction_model.pkl")
joblib.dump(
    {
        "model": health_clf,
        "feature_cols": MODEL_FEATURES,
        "health_map": health_map,
        "inv_health_map": inv_health_map,
        "stage_map": stage_map,
    },
    health_model_path,
)
print(f"  [OK] Saved -> {health_model_path}")

# ── Model 2: Sensor Risk ─────────────────────────────────────────────────────
print("\n[2/2] Training craycare_sensor_risk_model.pkl ...")
risk_clf = RandomForestClassifier(
    n_estimators=200, max_depth=14, random_state=42, n_jobs=-1, class_weight="balanced"
)
risk_clf.fit(X_train, yr_train)
yr_pred = risk_clf.predict(X_test)
risk_acc = accuracy_score(yr_test, yr_pred)
inv_risk_map = {v: k for k, v in risk_map.items()}
yr_test_labels = [inv_risk_map[y] for y in yr_test]
yr_pred_labels = [inv_risk_map[y] for y in yr_pred]
print(f"  Accuracy: {risk_acc:.4f}")
print(classification_report(yr_test_labels, yr_pred_labels, zero_division=0))

risk_model_path = os.path.join(OUTPUT_DIR, "craycare_sensor_risk_model.pkl")
joblib.dump(
    {
        "model": risk_clf,
        "feature_cols": MODEL_FEATURES,
        "risk_map": risk_map,
        "inv_risk_map": inv_risk_map,
        "stage_map": stage_map,
    },
    risk_model_path,
)
print(f"  [OK] Saved -> {risk_model_path}")

# ── Label encoders ───────────────────────────────────────────────────────────
le_path = os.path.join(OUTPUT_DIR, "label_encoders.pkl")
joblib.dump(
    {
        "stage_map": stage_map,
        "health_map": health_map,
        "inv_health_map": inv_health_map,
        "risk_map": risk_map,
        "inv_risk_map": inv_risk_map,
    },
    le_path,
)
print(f"  [OK] Saved -> {le_path}")

# ── Training summary ─────────────────────────────────────────────────────────
summary = {
    "dataset": {"samples": N_SAMPLES, "features": MODEL_FEATURES},
    "health_prediction": {
        "accuracy": round(health_acc, 4),
        "labels": list(health_map.keys()),
    },
    "sensor_risk": {
        "accuracy": round(risk_acc, 4),
        "labels": list(risk_map.keys()),
    },
}
summary_path = os.path.join(OUTPUT_DIR, "training_summary.json")
with open(summary_path, "w") as f:
    json.dump(summary, f, indent=2)
print(f"  [OK] Saved -> {summary_path}")

print("\n" + "=" * 60)
print("Training Complete!")
print("=" * 60)
print(f"\nFiles created in {OUTPUT_DIR}/:")
for fname in [
    "craycare_dataset_v2.csv",
    "craycare_health_prediction_model.pkl",
    "craycare_sensor_risk_model.pkl",
    "label_encoders.pkl",
    "training_summary.json",
]:
    path = os.path.join(OUTPUT_DIR, fname)
    size = os.path.getsize(path)
    print(f"  {fname:45s} {size:>8,} bytes")
