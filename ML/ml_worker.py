import sys, os, time

sys.path.insert(0, os.path.dirname(__file__))

import firebase_admin
from firebase_admin import db, credentials
import pandas as pd
import joblib

SERVICE_ACCOUNT_ENV = os.environ.get("FIREBASE_SERVICE_ACCOUNT")
if SERVICE_ACCOUNT_ENV:
    import json, tempfile

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json", mode="w")
    tmp.write(SERVICE_ACCOUNT_ENV)
    tmp.close()
    cred = credentials.Certificate(tmp.name)
else:
    SA_PATH = os.path.join(
        os.path.dirname(__file__), "..", "notification_worker", "serviceAccountKey.json"
    )
    cred = credentials.Certificate(SA_PATH)

firebase_admin.initialize_app(
    cred,
    {
        "databaseURL": "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app"
    },
)

latest_ref = db.reference("sensor_readings/latest")
config_ref = db.reference("sensor_readings/config")
prediction_ref = db.reference("ml_predictions/latest")

MODELS_DIR = os.path.join(os.path.dirname(__file__), "models")

SENSOR_KEYS = ["temperature", "phLevel", "dissolvedOxygen", "turbidity", "waterLevel"]
SENSOR_SHORT = ["temp", "ph", "do", "turb", "wl"]
SENSOR_LABELS = [
    "Temperature",
    "pH Level",
    "Dissolved Oxygen",
    "Turbidity",
    "Water Level",
]
SENSOR_UNITS = ["\u00b0C", "", "mg/L", "NTU", "cm"]
SENSOR_LONG = ["temp", "ph", "do", "turb", "waterlevel"]

FEATURE_COLS = SENSOR_KEYS + [
    "temp_rate",
    "ph_rate",
    "do_rate",
    "turb_rate",
    "wl_rate",
    "stage_enc",
]

health_model_data = None
risk_model_data = None
label_encoders = None

health_path = os.path.join(MODELS_DIR, "craycare_health_prediction_model.pkl")
risk_path = os.path.join(MODELS_DIR, "craycare_sensor_risk_model.pkl")
le_path = os.path.join(MODELS_DIR, "label_encoders.pkl")

if os.path.exists(health_path) and os.path.exists(risk_path):
    health_model_data = joblib.load(health_path)
    risk_model_data = joblib.load(risk_path)
    label_encoders = joblib.load(le_path) if os.path.exists(le_path) else {}
    print("[ML Worker] Loaded v2 models (health + risk)")
else:
    print("[ML Worker] WARNING: v2 models not found")

STAGE_MAP = {
    "early_juvenile": 0,
    "advanced_juvenile": 1,
    "pre_adult": 2,
    "market_size": 3,
}
INV_STAGE_MAP = {v: k for k, v in STAGE_MAP.items()}

STAGE_LABELS = {
    "early_juvenile": "Early Juvenile",
    "advanced_juvenile": "Advanced Juvenile",
    "pre_adult": "Pre-Adult",
    "market_size": "Market Size",
}
STAGE_RANGES = {
    "early_juvenile": {
        "temp": (26.0, 28.0),
        "ph": (7.5, 8.0),
        "do": (5.0, 999.0),
        "turb": (0.0, 25.0),
        "waterlevel": (120.0, 160.0),
    },
    "advanced_juvenile": {
        "temp": (25.0, 30.0),
        "ph": (7.0, 8.5),
        "do": (5.0, 999.0),
        "turb": (0.0, 30.0),
        "waterlevel": (120.0, 170.0),
    },
    "pre_adult": {
        "temp": (24.0, 30.0),
        "ph": (7.0, 8.5),
        "do": (4.5, 999.0),
        "turb": (0.0, 35.0),
        "waterlevel": (130.0, 180.0),
    },
    "market_size": {
        "temp": (24.0, 28.0),
        "ph": (7.0, 8.0),
        "do": (4.0, 999.0),
        "turb": (0.0, 40.0),
        "waterlevel": (130.0, 180.0),
    },
}

FB_RANGES_KEY = {
    "temperature": "temp",
    "phLevel": "ph",
    "dissolvedOxygen": "do",
    "turbidity": "turb",
    "waterLevel": "waterlevel",
}
SHORT_TO_KEY = {
    "temp": "temperature",
    "ph": "phLevel",
    "do": "dissolvedOxygen",
    "turb": "turbidity",
    "wl": "waterLevel",
}
SHORT_TO_LABEL = {
    "temp": "Temperature",
    "ph": "pH Level",
    "do": "Dissolved Oxygen",
    "turb": "Turbidity",
    "wl": "Water Level",
}
SHORT_TO_UNIT = {
    "temp": "\u00b0C",
    "ph": "",
    "do": "mg/L",
    "turb": "NTU",
    "wl": "cm",
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


def get_zone(val, r_min, r_max):
    is_max_bound = r_max < 999.0
    if val < r_min or val > r_max:
        return "CRITICAL"
    range_span = (r_max - r_min) if is_max_bound else r_min
    warning_threshold = range_span * 0.10
    check_lower = r_min > 0.0
    check_upper = is_max_bound
    if (check_lower and (val - r_min) < warning_threshold) or (
        check_upper and (r_max - val) < warning_threshold
    ):
        return "WARNING"
    return "OPTIMAL"


def predict_health(features_vec, stage_str):
    if health_model_data is None:
        return "Healthy", 0.5
    stage_enc = STAGE_MAP.get(stage_str, 2)
    row = list(features_vec) + [stage_enc]
    X = pd.DataFrame([row], columns=FEATURE_COLS)
    model = health_model_data["model"]
    inv_map = health_model_data["inv_health_map"]
    pred_idx = model.predict(X)[0]
    probs = model.predict_proba(X)[0]
    confidence = float(max(probs))
    label = inv_map.get(pred_idx, "Healthy")
    return label, confidence


def predict_risk(features_vec, stage_str):
    if risk_model_data is None:
        return "None", 0.5
    stage_enc = STAGE_MAP.get(stage_str, 2)
    row = list(features_vec) + [stage_enc]
    X = pd.DataFrame([row], columns=FEATURE_COLS)
    model = risk_model_data["model"]
    inv_map = risk_model_data["inv_risk_map"]
    pred_idx = model.predict(X)[0]
    probs = model.predict_proba(X)[0]
    confidence = float(max(probs))
    label = inv_map.get(pred_idx, "None")
    return label, confidence


def build_features_vec(
    temp, ph, d_o, turb, wl, temp_rate, ph_rate, do_rate, turb_rate, wl_rate
):
    return [temp, ph, d_o, turb, wl, temp_rate, ph_rate, do_rate, turb_rate, wl_rate]


def generate_insight(health_status, primary_risk, stage, sensor_zones, ranges):
    stage_label = STAGE_LABELS.get(stage, stage.replace("_", " ").title())

    if health_status == "Healthy":
        return (
            f"Water quality conditions are currently suitable for the {stage_label} stage. "
            "All parameters are within optimal ranges. The aquaculture system is healthy."
        )

    risk_sensor_label = primary_risk.replace(" Risk", "").replace(
        "Multiple", "multiple"
    )
    risk_detail = ""
    if primary_risk == "DO Risk" and "do" in sensor_zones:
        risk_detail = f" Dissolved oxygen is below the recommended threshold for {stage_label} stage."
    elif primary_risk == "Turbidity Risk" and "turb" in sensor_zones:
        risk_detail = (
            f" Turbidity is above the recommended threshold for {stage_label} stage."
        )
    elif primary_risk == "Temperature Risk" and "temp" in sensor_zones:
        risk_detail = (
            f" Temperature is outside the optimal range for {stage_label} stage."
        )
    elif primary_risk == "PH Risk" and "ph" in sensor_zones:
        risk_detail = (
            f" pH level is outside the recommended range for {stage_label} stage."
        )
    elif primary_risk == "Water Level Risk" and "wl" in sensor_zones:
        risk_detail = (
            f" Water level is outside the optimal range for {stage_label} stage."
        )
    elif primary_risk == "Multiple Risks":
        problem_sensors = [
            SHORT_TO_LABEL.get(s, s) for s, z in sensor_zones.items() if z != "OPTIMAL"
        ]
        if problem_sensors:
            risk_detail = (
                f" Multiple parameters require attention: {', '.join(problem_sensors)}."
            )

    if health_status == "Moderate Risk":
        return (
            f"Water quality conditions show signs of deviation from the recommended range "
            f"for the {stage_label} stage.{risk_detail} "
            "Continued monitoring is advised."
        )

    return (
        f"Water quality conditions may negatively affect crayfish growth and survival "
        f"for the {stage_label} stage.{risk_detail} "
        "Immediate attention is recommended."
    )


def generate_recommendation(health_status, primary_risk, sensor_zones, ranges, stage):
    if health_status == "Healthy":
        return "Continue regular monitoring and scheduled maintenance."

    risk_to_rec = {
        "DO Risk": (
            "The aerator should be activated or increased to improve dissolved oxygen concentration. "
            "Check that air stones are clean and the motor is running. Monitor oxygen levels closely."
        ),
        "Turbidity Risk": (
            "The water pump should be activated to circulate water through the "
            "recirculating aquaculture system (RAS). Monitor turbidity levels for further improvement."
        ),
        "PH Risk": (
            "Manual intervention is required. Apply an approved pH correction treatment "
            "and inspect possible sources of acidity or alkalinity in the system."
        ),
        "Temperature Risk": (
            "Increase water circulation and reduce heat exposure. "
            "Check shade nets and consider water exchange if temperature is critically high."
        ),
        "Water Level Risk": (
            "Refill the tank and inspect for leaks or excessive evaporation. "
            "Check auto-refill system and plumbing connections."
        ),
        "Multiple Risks": (
            "Multiple water quality parameters require attention. "
            "Check all automated systems (aerator, pump, filter) and consider partial water exchange (20-30%). "
            "Manual intervention may be needed for parameters that cannot be corrected automatically."
        ),
    }

    base_rec = risk_to_rec.get(
        primary_risk, "Manual intervention may be required. Inspect the system."
    )
    if health_status == "High Risk":
        return f"EMERGENCY: {base_rec}"
    return base_rec


def generate_sensor_insight(
    short_name, val, zone, r_min, r_max, unit, health_status, primary_risk
):
    label = SHORT_TO_LABEL.get(short_name, short_name)
    if zone == "OPTIMAL":
        return f"{label} at {val}{unit} is within the optimal range."
    elif zone == "WARNING":
        return f"{label} at {val}{unit} is approaching the limit ({r_min}-{r_max}{unit}). Trend may require attention."
    else:
        return f"{label} at {val}{unit} is outside the safe range ({r_min}-{r_max}{unit}). Action required."


def generate_sensor_prediction(short_name, health_status, primary_risk, confidence):
    if health_status == "Healthy":
        return f"CrayAI predicts Healthy overall status ({int(confidence * 100)}% confidence)."
    return (
        f"CrayAI predicts {health_status} status ({int(confidence * 100)}% confidence). "
        f"Primary risk factor: {primary_risk}."
    )


def generate_sensor_recommendation(
    short_name, zone, health_status, primary_risk, r_min, r_max, unit
):
    if zone == "OPTIMAL":
        return "No action needed for this parameter."
    risk_map_short = {
        "do": "DO Risk",
        "turb": "Turbidity Risk",
        "temp": "Temperature Risk",
        "ph": "PH Risk",
        "wl": "Water Level Risk",
    }
    sensor_risk = risk_map_short.get(short_name, "")
    if primary_risk != "Multiple Risks" and sensor_risk and sensor_risk != primary_risk:
        return "Monitor this parameter."
    if short_name == "do" and zone != "OPTIMAL":
        return "Activate or increase aeration to improve dissolved oxygen levels."
    elif short_name == "turb" and zone != "OPTIMAL":
        return "Activate water pump for circulation. Check filter media."
    elif short_name == "ph" and zone != "OPTIMAL":
        return (
            "Apply pH correction treatment. Check water source for acidity/alkalinity."
        )
    elif short_name == "temp" and zone != "OPTIMAL":
        return "Adjust water temperature. Check shade nets and water circulation."
    elif short_name == "wl" and zone != "OPTIMAL":
        return "Adjust water level. Check for leaks or evaporation."
    return "Monitor this parameter."


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


histories = {k: SensorHistory() for k in ["temp", "ph", "do", "turb", "waterlevel"]}


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

    t_min, t_max = ranges["temp"]["min"], ranges["temp"]["max"]
    p_min, p_max = ranges["ph"]["min"], ranges["ph"]["max"]
    do_min = ranges["do"]["min"]
    turb_max = ranges["turb"]["max"]
    wl_min, wl_max = ranges["waterlevel"]["min"], ranges["waterlevel"]["max"]

    features_vec = build_features_vec(
        temp, ph, d_o, turb, wl, temp_rate, ph_rate, do_rate, turb_rate, wl_rate
    )
    health_status, health_conf = predict_health(features_vec, stage)
    primary_risk, risk_conf = predict_risk(features_vec, stage)

    sensor_zones = {
        "temp": get_zone(temp, t_min, t_max),
        "ph": get_zone(ph, p_min, p_max),
        "do": get_zone(d_o, do_min, 999.0),
        "turb": get_zone(turb, 0.0, turb_max),
        "wl": get_zone(wl, wl_min, wl_max),
    }

    overall_status_map = {
        "Healthy": "OPTIMAL",
        "Moderate Risk": "WARNING",
        "High Risk": "CRITICAL",
    }
    overall_status = overall_status_map.get(health_status, "OPTIMAL")

    overall_insight = generate_insight(
        health_status, primary_risk, stage, sensor_zones, ranges
    )
    overall_rec = generate_recommendation(
        health_status, primary_risk, sensor_zones, ranges, stage
    )

    sensors_list = []
    for sk, short, label, unit, r_min, r_max in [
        ("temperature", "temp", "Temperature", "\u00b0C", t_min, t_max),
        ("phLevel", "ph", "pH Level", "", p_min, p_max),
        ("dissolvedOxygen", "do", "Dissolved Oxygen", "mg/L", do_min, 999.0),
        ("turbidity", "turb", "Turbidity", "NTU", 0.0, turb_max),
        ("waterLevel", "wl", "Water Level", "cm", wl_min, wl_max),
    ]:
        zone = sensor_zones[short]
        val = {"temp": temp, "ph": ph, "do": d_o, "turb": turb, "wl": wl}[short]
        s_insight = generate_sensor_insight(
            short, val, zone, r_min, r_max, unit, health_status, primary_risk
        )
        s_prediction = generate_sensor_prediction(
            short, health_status, primary_risk, health_conf
        )
        s_recommendation = generate_sensor_recommendation(
            short, zone, health_status, primary_risk, r_min, r_max, unit
        )

        sensors_list.append(
            {
                "key": sk,
                "label": label,
                "status": zone,
                "confidence": health_conf,
                "insight": s_insight,
                "prediction": s_prediction,
                "recommendation": s_recommendation,
            }
        )

    result = {
        "predictedStatus": overall_status,
        "confidence": health_conf,
        "stage": stage,
        "sensors": sensors_list,
        "insight": overall_insight,
        "prediction": (
            f"CrayAI predicts {health_status} overall health status "
            f"({int(health_conf * 100)}% confidence) based on "
            f"current {STAGE_LABELS.get(stage, stage)}-stage thresholds and sensor data."
        ),
        "recommendation": overall_rec,
        "healthStatus": health_status,
        "primaryRisk": primary_risk,
        "timestamp": int(time.time() * 1000),
    }

    print(
        f"[ML Worker] Stage={stage} Health={health_status} ({int(health_conf * 100)}%) Risk={primary_risk}"
    )
    for s in sensors_list:
        print(f"  {s['label']:20s}: {s['status']:8s} ({int(s['confidence'] * 100)}%)")

    prediction_ref.set(result)


print("[ML Worker] Listening to sensor_readings/latest ...")
latest_ref.listen(on_sensor_change)

while True:
    time.sleep(1)
