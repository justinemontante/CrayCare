import sys, os, json, time

sys.path.insert(0, os.path.dirname(__file__))

import firebase_admin
from firebase_admin import db, credentials
from app import models, build_per_sensor_response

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

INTERNAL_TO_FB = {v: k for k, v in SENSOR_MAP.items()}
INTERNAL_TO_FB["waterlevel"] = "waterLevel"

DATABASE_URL = (
    "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app"
)

cred = credentials.Certificate(SERVICE_ACCOUNT)
firebase_admin.initialize_app(cred, {"databaseURL": DATABASE_URL})

latest_ref = db.reference("sensor_readings/latest")
config_ref = db.reference("sensor_readings/config")
prediction_ref = db.reference("ml_predictions/latest")


def get_current_stage_ranges():
    """Read current stage and its sensor ranges from sensor_readings/config."""
    config = config_ref.get() or {}

    stage = config.get("selectedStage") or config.get("currentStage", "pre_adult")

    if stage not in models:
        print(f"[ML Worker] No model for stage '{stage}', falling back to pre_adult")
        stage = "pre_adult"

    raw_ranges = config.get("ranges", {})
    if not raw_ranges:
        stage_data = config.get(stage, {})
        raw_ranges = {}
        for sensor_key in ["temp", "ph", "do", "turb", "waterlevel"]:
            sr = stage_data.get(sensor_key)
            if sr and isinstance(sr, dict):
                raw_ranges[sensor_key] = {"min": sr.get("min"), "max": sr.get("max")}

    ranges = {}
    for internal_key, fb_key in INTERNAL_TO_FB.items():
        sr = raw_ranges.get(internal_key)
        if sr and isinstance(sr, dict):
            ranges[fb_key] = {"min": sr.get("min"), "max": sr.get("max")}

    return stage, ranges


def on_sensor_change(event):
    data = event.data
    if not data:
        return

    stage, stage_ranges = get_current_stage_ranges()

    if stage not in models:
        print(f"[ML Worker] No model for stage '{stage}', falling back to pre_adult")
        stage = "pre_adult"

    model = models[stage]

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

    result = build_per_sensor_response(status, confidence, full_input, stage_ranges)
    result["timestamp"] = int(time.time() * 1000)
    result["stage"] = stage

    print(
        f"[ML Worker] Stage={stage} Status={result['predictedStatus']} ({confidence})"
    )
    prediction_ref.set(result)


print("[ML Worker] Listening to sensor_readings/latest...")
latest_ref.listen(on_sensor_change)

while True:
    time.sleep(1)
