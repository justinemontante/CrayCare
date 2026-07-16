"""Run trained model on latest data + attach recommendation.

Uses shared feature engineering from features.py.
Handles both regressor and classifier model formats.
"""

import pandas as pd
import numpy as np
import joblib
import json

from features import build_features, SENSORS, classify

bundle = joblib.load("csi_model.joblib")
model, FEATURES = bundle["model"], bundle["features"]
model_type = bundle.get("type", "classifier")

with open("recommendations.json") as f:
    recs = json.load(f)

df = (
    pd.read_csv("sensor_labeled.csv", parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

feat, _ = build_features(df)
feat = feat[FEATURES]
latest = feat.iloc[[-1]]

if model_type == "regressor":
    pred_score = float(model.predict(latest)[0])
    pred_score = max(0.0, min(100.0, pred_score))
    cls, level = classify(pred_score)[0], classify(pred_score)[1]
    print(f"Predicted CSI score: {pred_score:.1f}")
    print(f"Health Risk: {level}")
else:
    raw_pred = model.predict(latest)
    pred_1d = raw_pred.argmax(axis=1) if len(raw_pred.shape) == 2 else raw_pred
    cls = int(pred_1d[0])
    level = ["Low", "Moderate", "High", "Critical"][cls]
    proba = model.predict_proba(latest)[0]
    print(f"Health Risk: {level} (confidence {proba[cls] * 100:.0f}%)")

imp = pd.Series(model.feature_importances_, index=FEATURES)
driver = max(
    SENSORS, key=lambda s: imp[[c for c in FEATURES if c.startswith(s)]].sum()
)
rec = recs.get(driver, recs["DO"])

print(f"Primary driver: {rec['problem']}")
print(f"Recommended action: {rec['action']}")
print(f"Basis: {rec['source']}")
