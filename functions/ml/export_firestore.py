"""Export one tank's canonical Firestore history for later model training.

Usage:
  CRAYCARE_TANK_ID=<tank-id> \
  GOOGLE_APPLICATION_CREDENTIALS=/path/serviceAccountKey.json \
  python functions/ml/export_firestore.py
"""

import os
from pathlib import Path

import pandas as pd

from sensor_history import SENSOR_VALUE_FIELDS, normalize_history


def export_tank_history(db, tank_id):
    """Include day paths even when their parent summary document is missing."""
    rows = []
    day_collection = (
        db.collection("tanks").document(tank_id)
        .collection("sensor_readings_history")
    )
    # .stream() returns only existing parent documents. The ESP writes entries
    # directly, so a day can have entries before its summary parent is created.
    for day_ref in day_collection.list_documents():
        for entry in day_ref.collection("entries").stream():
            data = entry.to_dict() or {}
            row = {"timestamp": data.get("recorded_at")}
            for aliases in SENSOR_VALUE_FIELDS.values():
                row[aliases[0]] = next(
                    (data[name] for name in aliases if data.get(name) is not None),
                    None,
                )
            rows.append(row)

    columns = ["timestamp", *(aliases[0] for aliases in SENSOR_VALUE_FIELDS.values())]
    if not rows:
        return pd.DataFrame(columns=columns)
    # Match the trainer's validation: incomplete and impossible observations
    # are removed, timestamps are sorted, and duplicate captures keep the last.
    frame = normalize_history(pd.DataFrame(rows, columns=columns))
    frame["timestamp"] = pd.to_datetime(frame["timestamp"], unit="s", utc=True)
    return frame[columns]


def main():
    tank_id = os.environ.get("CRAYCARE_TANK_ID")
    if not tank_id:
        raise SystemExit("Set CRAYCARE_TANK_ID to the tank document ID before exporting.")

    import firebase_admin
    from firebase_admin import firestore

    # initialize_app() uses GOOGLE_APPLICATION_CREDENTIALS or current gcloud ADC.
    firebase_admin.initialize_app()
    frame = export_tank_history(firestore.client(), tank_id)
    out_path = Path(__file__).with_name("real_sensor_history.csv")
    frame.to_csv(out_path, index=False)
    print(f"Exported {len(frame):,} complete readings for tank {tank_id} -> {out_path}")


if __name__ == "__main__":
    main()
