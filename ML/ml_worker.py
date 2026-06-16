import sys, os, json, time

sys.path.insert(0, os.path.dirname(__file__))

import firebase_admin
from firebase_admin import db, credentials
import pandas as pd
import joblib

SERVICE_ACCOUNT = os.path.join(
    os.path.dirname(__file__), "..", "notification_worker", "serviceAccountKey.json"
)

DATABASE_URL = (
    "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app"
)

cred = credentials.Certificate(SERVICE_ACCOUNT)
firebase_admin.initialize_app(cred, {"databaseURL": DATABASE_URL})

latest_ref = db.reference("sensor_readings/latest")
config_ref = db.reference("sensor_readings/config")
prediction_ref = db.reference("ml_predictions/latest")

MODELS_DIR = os.path.join(os.path.dirname(__file__), "models")

SENSOR_KEYS = ["temp", "ph", "do", "turb", "wl"]

models = {}
for key in SENSOR_KEYS:
    path = os.path.join(MODELS_DIR, f"craycare_{key}_model.pkl")
    if os.path.exists(path):
        models[key] = joblib.load(path)
        print(f"[ML Worker] Loaded {key} model")
    else:
        models[key] = None
        print(f"[ML Worker] WARNING: {key} model not found at {path}")

status_path = os.path.join(MODELS_DIR, "craycare_status_model.pkl")
if os.path.exists(status_path):
    status_model = joblib.load(status_path)
    print("[ML Worker] Loaded overall status model")
else:
    status_model = None
    print("[ML Worker] WARNING: Overall status model not found")

SENSOR_CONFIGS = [
    {"key": "temperature", "name": "temp", "label": "Temperature", "unit": "\u00b0C"},
    {"key": "phLevel", "name": "ph", "label": "pH Level", "unit": ""},
    {
        "key": "dissolvedOxygen",
        "name": "do",
        "label": "Dissolved Oxygen",
        "unit": "mg/L",
    },
    {"key": "turbidity", "name": "turb", "label": "Turbidity", "unit": "NTU"},
    {"key": "waterLevel", "name": "waterlevel", "label": "Water Level", "unit": "cm"},
]


class SensorHistory:
    def __init__(self, max_len=5):
        self.max_len = max_len
        self.history = []

    def add(self, value):
        self.history.append(value)
        if len(self.history) > self.max_len:
            self.history.pop(0)

    def get_rate(self):
        if len(self.history) < 2:
            return 0.0
        delta = self.history[-1] - self.history[0]
        return delta / (len(self.history) - 1)


histories = {
    "temp": SensorHistory(),
    "do": SensorHistory(),
    "turb": SensorHistory(),
    "ph": SensorHistory(),
    "waterlevel": SensorHistory(),
}


def get_current_stage_ranges():
    config = config_ref.get() or {}
    stage = config.get("selectedStage") or "pre_adult"

    stage_config = config.get(stage, {})

    defaults = {
        "temp": {"min": 24.0, "max": 30.0},
        "ph": {"min": 7.0, "max": 8.5},
        "do": {"min": 4.5, "max": 999.0},
        "turb": {"min": 0.0, "max": 35.0},
        "waterlevel": {"min": 130.0, "max": 180.0},
    }

    ranges = {}
    for key in ["temp", "ph", "do", "turb", "waterlevel"]:
        sensor_range = (
            stage_config.get(key, {}) if isinstance(stage_config, dict) else {}
        )
        if not sensor_range:
            sensor_range = config.get("ranges", {}).get(key, {})

        if not sensor_range:
            sensor_range = defaults[key]

        ranges[key] = {
            "min": float(sensor_range["min"])
            if sensor_range.get("min") is not None
            else defaults[key]["min"],
            "max": float(sensor_range["max"])
            if sensor_range.get("max") is not None
            else defaults[key]["max"],
        }

    return stage, ranges


def generate_insight(label, val, unit, status, rate, r_min, r_max):
    is_max_bound = r_max < 999.0
    unit_str = unit if unit else ""
    sign = "+" if rate >= 0 else ""

    if status == "CRITICAL":
        if val < r_min:
            insight = f"{label} is critical at {val}{unit_str} (below ideal min of {r_min}{unit_str})."
            recommendation = f"Urgent action required: Increase {label.lower()}."
        else:
            insight = f"{label} is critical at {val}{unit_str} (above ideal max of {r_max}{unit_str})."
            recommendation = f"Urgent action required: Reduce {label.lower()}."
        prediction = (
            "Crayfish are under high physiological stress. Mortality risk if prolonged."
        )

    elif status == "WARNING":
        range_mid = (r_min + r_max) / 2 if is_max_bound else r_min * 1.5
        if val < range_mid:
            insight = f"{label} is warning-low at {val}{unit_str} (approaching {r_min}{unit_str})."
            recommendation = f"Adjust parameters: Raise {label.lower()} soon."
        else:
            max_display = r_max if is_max_bound else "\u221e"
            insight = f"{label} is warning-high at {val}{unit_str} (approaching {max_display}{unit_str})."
            recommendation = f"Adjust parameters: Lower {label.lower()} soon."

        prediction = f"Reading is warning-close to limits and moving at {sign}{rate:.3f}{unit_str}/rdg."

    else:
        max_display = r_max if is_max_bound else "\u221e"
        insight = f"{label} is optimal at {val}{unit_str} (Ideal: {r_min} - {max_display}{unit_str})."
        prediction = (
            f"Stable condition. Moving slowly at {sign}{rate:.3f}{unit_str}/rdg."
        )
        recommendation = "No action needed. Maintain current system setup."

    return insight, prediction, recommendation


def on_sensor_change(event):
    data = event.data
    if not data:
        return

    temp = data.get("temperature")
    ph = data.get("phLevel")
    d_o = data.get("dissolvedOxygen")
    turb = data.get("turbidity")
    wl = data.get("waterLevel")

    if any(v is None for v in [temp, ph, d_o, turb, wl]):
        return

    histories["temp"].add(temp)
    histories["ph"].add(ph)
    histories["do"].add(d_o)
    histories["turb"].add(turb)
    histories["waterlevel"].add(wl)

    temp_rate = histories["temp"].get_rate()
    ph_rate = histories["ph"].get_rate()
    do_rate = histories["do"].get_rate()
    turb_rate = histories["turb"].get_rate()
    wl_rate = histories["waterlevel"].get_rate()

    stage, ranges = get_current_stage_ranges()

    features = {
        "temperature": float(temp),
        "phLevel": float(ph),
        "dissolvedOxygen": float(d_o),
        "turbidity": float(turb),
        "waterLevel": float(wl),
        "temp_rate": float(temp_rate),
        "ph_rate": float(ph_rate),
        "do_rate": float(do_rate),
        "turb_rate": float(turb_rate),
        "wl_rate": float(wl_rate),
        "temp_min": float(ranges["temp"]["min"]),
        "temp_max": float(ranges["temp"]["max"]),
        "ph_min": float(ranges["ph"]["min"]),
        "ph_max": float(ranges["ph"]["max"]),
        "do_min": float(ranges["do"]["min"]),
        "turb_max": float(ranges["turb"]["max"]),
        "wl_min": float(ranges["waterlevel"]["min"]),
        "wl_max": float(ranges["waterlevel"]["max"]),
    }

    X = pd.DataFrame([features])

    FEATURE_ORDER = [
        "temperature",
        "phLevel",
        "dissolvedOxygen",
        "turbidity",
        "waterLevel",
        "temp_rate",
        "ph_rate",
        "do_rate",
        "turb_rate",
        "wl_rate",
        "temp_min",
        "temp_max",
        "ph_min",
        "ph_max",
        "do_min",
        "turb_max",
        "wl_min",
        "wl_max",
    ]
    X = X[FEATURE_ORDER]

    # --- Per-sensor predictions using ML models ---
    name_to_model_key = {
        "temperature": "temp",
        "phLevel": "ph",
        "dissolvedOxygen": "do",
        "turbidity": "turb",
        "waterLevel": "wl",
    }

    name_to_fb_name = {
        "temperature": "temp",
        "phLevel": "ph",
        "dissolvedOxygen": "do",
        "turbidity": "turb",
        "waterLevel": "waterlevel",
    }

    sensors_list = []

    for cfg in SENSOR_CONFIGS:
        key = cfg["key"]
        name = cfg["name"]
        model_key = name_to_model_key[key]
        fb_name = name_to_fb_name[key]
        val = float(features[key])
        r_min = ranges[fb_name]["min"]
        r_max = ranges[fb_name]["max"]
        unit = cfg["unit"]

        if name == "temp":
            rate = temp_rate
        elif name == "ph":
            rate = ph_rate
        elif name == "do":
            rate = do_rate
        elif name == "turb":
            rate = turb_rate
        else:
            rate = wl_rate

        model = models.get(model_key)
        if model is not None:
            pred = str(model.predict(X)[0])
            proba = model.predict_proba(X)[0]
            confidence = round(float(max(proba)), 2)
            sensor_status = pred
        else:
            sensor_status = "OPTIMAL"
            confidence = 1.0

        insight, prediction, recommendation = generate_insight(
            cfg["label"], val, unit, sensor_status, rate, r_min, r_max
        )

        if model_key == "do" and rate < -0.05:
            prediction = (
                f"CRITICAL PREDICTION: DO is dropping rapidly ({rate:.3f} mg/L per reading) "
                f"and will cross limit soon!"
            )
            recommendation = "Activate aerator/oxygen support immediately."
        elif model_key == "turb" and rate > 0.5:
            prediction = f"WARNING PREDICTION: Turbidity is rising fast (+{rate:.2f} NTU per reading)."
            recommendation = "Turn on water filter / recirculation pump to clear water."
        elif model_key == "wl" and rate < -0.5:
            recommendation = "Fill tank immediately. Do NOT run water pump if water level is too low to prevent motor damage."

        sensors_list.append(
            {
                "key": key,
                "label": cfg["label"],
                "status": sensor_status,
                "confidence": confidence,
                "insight": insight,
                "prediction": prediction,
                "recommendation": recommendation,
            }
        )

    # --- Overall status prediction using ML model ---
    if status_model is not None:
        overall_pred = str(status_model.predict(X)[0])
        overall_proba = status_model.predict_proba(X)[0]
        confidence = round(float(max(overall_proba)), 2)
    else:
        overall_pred = "OPTIMAL"
        confidence = 1.0

    overall_insights = [s["insight"] for s in sensors_list if s["status"] != "OPTIMAL"]
    overall_recs = [
        s["recommendation"] for s in sensors_list if s["status"] != "OPTIMAL"
    ]

    if not overall_insights:
        insight_text = "All water quality parameters are within their optimal ranges. The aquaculture system is healthy."
        rec_text = "Continue regular monitoring and routine maintenance."
    else:
        insight_text = " | ".join(overall_insights)
        rec_text = " | ".join(overall_recs)

    result = {
        "predictedStatus": overall_pred,
        "confidence": confidence,
        "sensors": sensors_list,
        "insight": insight_text,
        "prediction": (
            f"Machine Learning Model predicts a {overall_pred} overall status "
            f"({int(confidence * 100)}% confidence) based on sensor values and rates of change."
        ),
        "recommendation": rec_text,
        "timestamp": int(time.time() * 1000),
        "stage": stage,
    }

    print(f"[ML Worker] Stage={stage} Status={overall_pred} (Conf={confidence})")
    for s in sensors_list:
        print(f"  {s['label']}: {s['status']} (Conf={s.get('confidence', 'N/A')})")
    prediction_ref.set(result)


print("[ML Worker] Listening to sensor_readings/latest...")
latest_ref.listen(on_sensor_change)

while True:
    time.sleep(1)
