"""Local CLI test script for the Water Quality Assessment.

Runs the current assessment model and recommendations on the latest row of
sensor_dataset.csv, then prints the complete Water Quality Assessment result.

Uses the same features.assess_water_quality() model core as the deployed
Cloud Function. Production additionally applies main.py enrichment and the
deterministic safety floor, so this script previews the model core rather than
claiming to reproduce the final Firestore document byte-for-byte.

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

bundle = joblib.load(os.path.join(_DIR, "wqa_model.joblib"))

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
