"""Local CLI test script: run the current model + recommendations on the
latest row of sensor_dataset.csv and print the full WQRI result.

Uses the exact same features.predict_wqri() that the deployed Cloud
Function (main.py) uses, so this is a true preview of what production
would output for that row -- not a separate reimplementation.

Usage: python predict.py
"""

import os
import json
import joblib
import pandas as pd

from features import predict_wqri

_DIR = os.path.dirname(os.path.abspath(__file__))

bundle = joblib.load(os.path.join(_DIR, "wqri_model.joblib"))

with open(os.path.join(_DIR, "recommendations.json")) as f:
    recs = json.load(f)

df = (
    pd.read_csv(os.path.join(_DIR, "sensor_dataset.csv"), parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

result = predict_wqri(df, bundle, recs)

print(f"Water Quality Risk: {result['level']} (score={result['score']}, confidence={result['confidence']}%)")
print(f"Primary driver: {result['problem']}")
print(f"Insight: {result['insight']}")
print(f"Recommended action: {result['action']}")
print(f"Basis: {result['source']}")
