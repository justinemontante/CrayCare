"""Export canonical 10-minute Firestore history into the training CSV schema.

Usage:
  CRAYCARE_TANK_ID=<tank-id> \
  GOOGLE_APPLICATION_CREDENTIALS=/path/serviceAccountKey.json \
  python functions/ml/export_firestore.py
"""
import math
import os
from pathlib import Path

import firebase_admin
from firebase_admin import firestore
import pandas as pd

TANK_ID = os.environ.get("CRAYCARE_TANK_ID")
if not TANK_ID:
    raise SystemExit("Set CRAYCARE_TANK_ID to the tank document ID before exporting.")

# initialize_app() uses GOOGLE_APPLICATION_CREDENTIALS or the current gcloud ADC.
firebase_admin.initialize_app()
db = firestore.client()

rows = []
date_docs = (
    db.collection("tanks").document(TANK_ID)
    .collection("sensor_readings_history").stream()
)
for date_doc in date_docs:
    for entry in date_doc.reference.collection("entries").stream():
        data = entry.to_dict()
        recorded_at = data.get("recorded_at")
        if recorded_at is None:
            continue
        rows.append({
            "timestamp": recorded_at,
            "temperature": data.get("temperature", data.get("temp_avg")),
            "ph_level": data.get("ph_level", data.get("pH_avg")),
            "dissolved_oxygen": data.get("dissolved_oxygen", data.get("DO_avg")),
            "turbidity": data.get("turbidity", data.get("turbidity_avg")),
            "water_level": data.get("water_level", data.get("waterLevel_avg")),
        })

columns = ["timestamp", "temperature", "ph_level", "dissolved_oxygen", "turbidity", "water_level"]
df = pd.DataFrame(rows, columns=columns)
if not df.empty:
    for column in columns[1:]:
        df[column] = pd.to_numeric(df[column], errors='coerce')
    df = df.dropna(subset=columns)

    df = df[
        df[columns[1:]].applymap(lambda value: math.isfinite(float(value)) and float(value) >= 0).all(axis=1)
    ].sort_values("timestamp")
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True).dt.tz_localize(None)

out_path = Path(__file__).with_name("real_sensor_history.csv")
df.to_csv(out_path, index=False)
print(f"Exported {len(df):,} complete readings for tank {TANK_ID} -> {out_path}")
