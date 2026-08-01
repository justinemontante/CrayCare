"""Export one tank's canonical 10-minute Firestore history to sensor_dataset.csv.

Usage: CRAYCARE_TANK_ID=tank_juan_001 python export_firestore.py
"""
import os
import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd

TANK_ID = os.environ.get("CRAYCARE_TANK_ID")
if not TANK_ID:
    raise SystemExit("Set CRAYCARE_TANK_ID to the tank document ID before exporting.")

cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# Final path: tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{id}
rows = []
date_docs = (
    db.collection("tanks").document(TANK_ID)
    .collection("sensor_readings_history").stream()
)
for date_doc in date_docs:
    entries = date_doc.reference.collection("entries").stream()
    rows.extend(d.to_dict() for d in entries)

df = pd.DataFrame(rows)
if not df.empty and "recorded_at" in df.columns:
    df = df.sort_values("recorded_at")
df.to_csv("sensor_dataset.csv", index=False)
print(f"Exported {len(df):,} readings for tank {TANK_ID}")
