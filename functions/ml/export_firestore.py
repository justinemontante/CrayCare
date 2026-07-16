"""Export Firestore 10-min logs -> sensor_dataset.csv"""

import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd

cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# Sensor history is stored as date-named subcollections under
# sensorReadings/history/{date_str}, not a top-level "sensor_logs"
# collection (see functions/ml/main.py's _fetch_sensor_history).
rows = []
date_docs = db.collection("sensorReadings").document("history").collections()
for date_collection in date_docs:
    docs = date_collection.order_by("timestamp").stream()
    rows.extend(d.to_dict() for d in docs)

df = pd.DataFrame(rows)
if not df.empty and "timestamp" in df.columns:
    df = df.sort_values("timestamp")
df.to_csv("sensor_dataset.csv", index=False)
print(f"Exported {len(df):,} rows from Firestore")
