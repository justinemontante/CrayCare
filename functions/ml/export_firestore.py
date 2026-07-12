"""Export Firestore 10-min logs -> sensor_dataset.csv"""

import firebase_admin
from firebase_admin import credentials, firestore
import pandas as pd

cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

docs = db.collection("sensor_logs").order_by("timestamp").stream()
rows = [d.to_dict() for d in docs]

df = pd.DataFrame(rows)
df.to_csv("sensor_dataset.csv", index=False)
print(f"Exported {len(df):,} rows from Firestore")
