"""Export canonical 10-minute Firestore history into the training CSV schema.

Usage:
  CRAYCARE_TANK_ID=<tank-id> \
  GOOGLE_APPLICATION_CREDENTIALS=/path/serviceAccountKey.json \
  python functions/ml/export_firestore.py
"""
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
            "temp_avg": data.get("temp_avg"),
            "temp_min": data.get("temp_min"),
            "temp_max": data.get("temp_max"),
            "pH_avg": data.get("pH_avg"),
            "pH_min": data.get("pH_min"),
            "pH_max": data.get("pH_max"),
            "DO_avg": data.get("DO_avg"),
            "DO_min": data.get("DO_min"),
            "DO_max": data.get("DO_max"),
            "turbidity_avg": data.get("turbidity_avg"),
            "turbidity_min": data.get("turbidity_min"),
            "turbidity_max": data.get("turbidity_max"),
            "waterLevel_avg": data.get("waterLevel_avg"),
            "waterLevel_min": data.get("waterLevel_min"),
            "waterLevel_max": data.get("waterLevel_max"),
        })

columns = [
    "timestamp",
    "temp_avg", "temp_min", "temp_max",
    "pH_avg", "pH_min", "pH_max",
    "DO_avg", "DO_min", "DO_max",
    "turbidity_avg", "turbidity_min", "turbidity_max",
    "waterLevel_avg", "waterLevel_min", "waterLevel_max",
]
df = pd.DataFrame(rows, columns=columns)
if not df.empty:
    df = df.dropna(subset=columns).sort_values("timestamp")
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True).dt.tz_localize(None)

out_path = Path(__file__).with_name("sensor_dataset.csv")
df.to_csv(out_path, index=False)
print(f"Exported {len(df):,} complete readings for tank {TANK_ID} -> {out_path}")
