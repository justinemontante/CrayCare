"""Local CLI test script for the Water Quality Assessment.

Runs the current classification model and recommendations on the latest row of
sensor_dataset.csv, then prints the complete Water Quality Assessment result.

Uses the exact same features.assess_water_quality() that the deployed Cloud
Function (main.py) uses, so this is a true preview of what production
would output for that row -- not a separate reimplementation.

Usage: python predict.py
"""

import os
import sys
import json
import joblib
import pandas as pd

from features import assess_water_quality

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

_DIR = os.path.dirname(os.path.abspath(__file__))

bundle = joblib.load(os.path.join(_DIR, "wqc_model.joblib"))

with open(os.path.join(_DIR, "recommendations.json"), encoding="utf-8") as f:
    recs = json.load(f)

df = (
    pd.read_csv(os.path.join(_DIR, "sensor_dataset.csv"), parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

result = assess_water_quality(df, bundle, recs)

print(f"Water Quality Assessment: {result['level']} (confidence={result['confidence']}%)")
print(f"Primary driver: {result['driver']}")
print(f"Problem: {result['problem']}")
print(f"Insight: {result['insight']}")
print(f"Recommended action: {result['action']}")
print(f"Basis: {result['source']}")
