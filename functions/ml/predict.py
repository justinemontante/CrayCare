"""Run trained model on latest data + attach recommendation."""

import pandas as pd
import numpy as np
import joblib
import json

bundle = joblib.load("csi_model.joblib")
model, FEATURES = bundle["model"], bundle["features"]

with open("recommendations.json") as f:
    recs = json.load(f)

LABELS = ["Low", "Moderate", "High", "Critical"]

df = (
    pd.read_csv("sensor_labeled.csv", parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

SENSORS = ["temp", "pH", "DO", "turbidity", "waterLevel"]
feat = pd.DataFrame()
for s in SENSORS:
    a = df[f"{s}_avg"]
    feat[f"{s}_avg"] = a
    feat[f"{s}_min"] = df[f"{s}_min"]
    feat[f"{s}_max"] = df[f"{s}_max"]
    feat[f"{s}_volatility"] = df[f"{s}_max"] - df[f"{s}_min"]
    feat[f"{s}_roll6h"] = a.rolling(36, min_periods=1).mean()
    feat[f"{s}_roll24h"] = a.rolling(144, min_periods=1).mean()
    feat[f"{s}_trend"] = a.diff().rolling(6, min_periods=1).mean()

feat["DO_hrs_low"] = (df["DO_min"] < 5.0).rolling(36, min_periods=1).sum() / 6.0
feat["temp_hrs_hi"] = (df["temp_max"] > 31.0).rolling(36, min_periods=1).sum() / 6.0
feat["pH_hrs_bad"] = ((df["pH_min"] < 6.5) | (df["pH_max"] > 8.5)).rolling(
    36, min_periods=1
).sum() / 6.0

feat = feat.bfill().fillna(0)[FEATURES]

latest = feat.iloc[[-1]]
cls = int(model.predict(latest)[0])
proba = model.predict_proba(latest)[0]

imp = pd.Series(model.feature_importances_, index=FEATURES)
driver = max(SENSORS, key=lambda s: imp[[c for c in FEATURES if c.startswith(s)]].sum())
rec = recs.get(driver, recs["DO"])

print(f"Health Risk: {LABELS[cls]} (confidence {proba[cls] * 100:.0f}%)")
print(f"Primary driver: {rec['problem']}")
print(f"Recommended action: {rec['action']}")
print(f"Basis: {rec['source']}")
