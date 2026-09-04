"""Preview the deployed WQAD inference contract on the generated dataset."""

import json
import os
import joblib
import pandas as pd

from anomaly_features import detect_water_quality_anomaly

ROOT = os.path.dirname(os.path.abspath(__file__))
bundle = joblib.load(os.path.join(ROOT, "wqad_model.joblib"))
with open(os.path.join(ROOT, "anomaly_recommendations.json"), encoding="utf-8") as handle:
    recommendations = json.load(handle)
frame = pd.read_csv(os.path.join(ROOT, "sensor_dataset.csv"), parse_dates=["timestamp"])
frame["timestamp"] = frame["timestamp"].astype("int64") / 1e9
result = detect_water_quality_anomaly(frame.tail(12), bundle, recommendations)
print(f"WQAD status: {result['status']} (anomaly score={result['anomaly_score']}/100)")
print(f"Main contributor: {result['driver_label']}")
print(f"Insight: {result['insight']}")
print(f"Suggested action: {result['recommendation']}")
print(f"Model: {result['source']}")
