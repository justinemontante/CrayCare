import sys, os, json, time

sys.path.insert(0, os.path.dirname(__file__))

import firebase_admin
from firebase_admin import db, credentials
from app import model, build_per_sensor_response

SERVICE_ACCOUNT = os.path.join(
    os.path.dirname(__file__), "..", "notification_worker", "serviceAccountKey.json"
)

SENSOR_MAP = {
    "temperature": "temp",
    "phLevel": "ph",
    "dissolvedOxygen": "do",
    "turbidity": "turb",
    "waterLevelPercent": "waterlevel",
}

DATABASE_URL = (
    "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app"
)

cred = credentials.Certificate(SERVICE_ACCOUNT)
firebase_admin.initialize_app(cred, {"databaseURL": DATABASE_URL})

latest_ref = db.reference("sensor_readings/latest")
thresholds_ref = db.reference("sensor_readings/thresholds")
prediction_ref = db.reference("ml_predictions/latest")


def on_sensor_change(event):
    data = event.data
    if not data:
        return

    thresholds = thresholds_ref.get() or {}
    thresholds_data = thresholds.get("ranges", {})

    mapped_data = {}
    for fb_key, svc_key in SENSOR_MAP.items():
        val = data.get(fb_key)
        if val is not None and val >= 0:
            mapped_data[svc_key] = val

    if not mapped_data:
        return

    full_input = {
        "temperature": mapped_data.get("temp", 0),
        "phLevel": mapped_data.get("ph", 0),
        "dissolvedOxygen": mapped_data.get("do", 0),
        "turbidity": mapped_data.get("turb", 0),
        "waterLevel": mapped_data.get("waterlevel", 0),
    }

    import pandas as pd

    X = pd.DataFrame(
        [
            {
                "temperature": float(full_input["temperature"]),
                "phLevel": float(full_input["phLevel"]),
                "dissolvedOxygen": float(full_input["dissolvedOxygen"]),
                "turbidity": float(full_input["turbidity"]),
                "waterLevel": float(full_input["waterLevel"]),
            }
        ]
    )

    status = model.predict(X)[0]
    probabilities = model.predict_proba(X)[0]
    confidence = round(float(max(probabilities)), 2)

    result = build_per_sensor_response(status, confidence, full_input, thresholds_data)
    result["timestamp"] = int(time.time() * 1000)

    print(f"[ML Worker] Status changed to {result['predictedStatus']} ({confidence})")
    prediction_ref.set(result)


print("[ML Worker] Listening to sensor_readings/latest...")
latest_ref.listen(on_sensor_change)

while True:
    time.sleep(1)
