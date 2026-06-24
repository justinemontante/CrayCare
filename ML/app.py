import os, sys, json, time, threading
from flask import Flask, request, jsonify
from flask_cors import CORS

import firebase_admin
from firebase_admin import db, credentials
import numpy as np
import pandas as pd
import pickle

PORT = int(os.environ.get("PORT", 7860))
DATABASE_URL = (
    "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app"
)

app = Flask(__name__)
CORS(app)

# ── Load Models ───────────────────────────────────────────────

MODELS_DIR = os.path.join(os.path.dirname(__file__), "models")

sensor_model = None
overall_model = None
encoders = None
feature_cols = None

try:
    with open(os.path.join(MODELS_DIR, "sensor_model.pkl"), "rb") as f:
        sensor_model = pickle.load(f)
    with open(os.path.join(MODELS_DIR, "overall_model.pkl"), "rb") as f:
        overall_model = pickle.load(f)
    with open(os.path.join(MODELS_DIR, "encoders.pkl"), "rb") as f:
        encoders = pickle.load(f)
    with open(os.path.join(MODELS_DIR, "feature_cols.pkl"), "rb") as f:
        feature_cols = pickle.load(f)
    print("[ML] All models loaded successfully")
except Exception as e:
    print(f"[ML] WARNING: Could not load models — {e}")

# ── Constants ─────────────────────────────────────────────────

READING_INTERVAL_SEC = 5  # ESP32 sends every 5 seconds

STAGE_MAP = {
    "early_juvenile": 0,
    "advanced_juvenile": 1,
    "pre_adult": 2,
    "market_size": 3,
}
STAGE_LABELS = {
    "early_juvenile": "Early Juvenile",
    "advanced_juvenile": "Advanced Juvenile",
    "pre_adult": "Pre-Adult",
    "market_size": "Market Size",
}
SHORT_TO_LABEL = {
    "temp": "Temperature",
    "ph": "pH Level",
    "do": "Dissolved Oxygen",
    "turb": "Turbidity",
    "wl": "Water Level",
}
SHORT_TO_UNIT = {
    "temp": "°C",
    "ph": "",
    "do": "mg/L",
    "turb": "NTU",
    "wl": "cm",
}
SENSOR_TARGETS = ["temp_status", "ph_status", "do_status", "turb_status", "wl_status"]

# ── Sensor History ────────────────────────────────────────────


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
        return (self.history[-1] - self.history[0]) / (len(self.history) - 1)


histories = {k: SensorHistory() for k in ["temp", "ph", "do", "turb", "wl"]}

# ── Feature Engineering ───────────────────────────────────────


def compute_ratio(val, vmin, vmax):
    span = vmax - vmin
    return (val - vmin) / span if span > 0 else 0.5


def build_feature_row(
    temp,
    ph,
    do_,
    turb,
    wl,
    temp_rate,
    ph_rate,
    do_rate,
    turb_rate,
    wl_rate,
    t_min,
    t_max,
    p_min,
    p_max,
    d_min,
    d_max,
    tr_min,
    tr_max,
    wl_min,
    wl_max,
    stage_str,
):
    stage_enc = STAGE_MAP.get(stage_str, 2)
    row = {
        "temperature": temp,
        "phLevel": ph,
        "dissolvedOxygen": do_,
        "turbidity": turb,
        "waterLevel": wl,
        "temp_rate": temp_rate,
        "ph_rate": ph_rate,
        "do_rate": do_rate,
        "turb_rate": turb_rate,
        "wl_rate": wl_rate,
        "temp_min": t_min,
        "temp_max": t_max,
        "ph_min": p_min,
        "ph_max": p_max,
        "do_min": d_min,
        "do_max": d_max,
        "turb_min": tr_min,
        "turb_max": tr_max,
        "wl_min": wl_min,
        "wl_max": wl_max,
        "temp_ratio": round(compute_ratio(temp, t_min, t_max), 4),
        "ph_ratio": round(compute_ratio(ph, p_min, p_max), 4),
        "do_ratio": round(compute_ratio(do_, d_min, d_max), 4),
        "turb_ratio": round(compute_ratio(turb, tr_min, tr_max), 4),
        "wl_ratio": round(compute_ratio(wl, wl_min, wl_max), 4),
        "stage": stage_enc,
    }
    return pd.DataFrame([row], columns=feature_cols)


def predict_all(X):
    if sensor_model is None or overall_model is None:
        return {t: "OPTIMAL" for t in SENSOR_TARGETS}, "OPTIMAL", 0.5

    sensor_preds = sensor_model.predict(X)[0]
    sensor_probs = sensor_model.predict_proba(X)
    sensor_conf = float(min(float(np.max(p)) for p in sensor_probs))

    sensor_statuses = {}
    for i, target in enumerate(SENSOR_TARGETS):
        sensor_statuses[target] = encoders[target].inverse_transform([sensor_preds[i]])[
            0
        ]

    overall_pred = overall_model.predict(X)[0]
    overall_probs = overall_model.predict_proba(X)[0]
    overall_str = encoders["status"].inverse_transform([overall_pred])[0]
    overall_conf = float(max(overall_probs))

    return sensor_statuses, overall_str, overall_conf


# ── Text Generators ───────────────────────────────────────────


def format_time(seconds):
    """Convert seconds into a human-readable time string."""
    if seconds < 60:
        return "less than a minute"
    elif seconds < 3600:
        minutes = int(seconds / 60)
        return f"{minutes} minute{'s' if minutes > 1 else ''}"
    else:
        total_hours = seconds / 3600
        hours = int(total_hours)
        minutes = int((total_hours - hours) * 60)
        if hours >= 5:
            return f"about {hours} hours"
        elif minutes == 0:
            return f"{hours} hour{'s' if hours > 1 else ''}"
        else:
            return f"{hours} hour{'s' if hours > 1 else ''} and {minutes} minute{'s' if minutes > 1 else ''}"


def generate_insight(overall_status, sensor_statuses, stage, ranges):
    stage_label = STAGE_LABELS.get(stage, stage.replace("_", " ").title())

    if overall_status == "OPTIMAL":
        return (
            f"Everything looks good in the tank right now. "
            f"All five water parameters are within the safe range for your {stage_label} crayfish. "
            f"Keep up the current routine — they're doing well."
        )

    critical_sensors, warning_sensors = [], []
    for short, target in [
        ("temp", "temp_status"),
        ("ph", "ph_status"),
        ("do", "do_status"),
        ("turb", "turb_status"),
        ("wl", "wl_status"),
    ]:
        s = sensor_statuses.get(target, "OPTIMAL")
        if s == "CRITICAL":
            critical_sensors.append(SHORT_TO_LABEL[short])
        elif s == "WARNING":
            warning_sensors.append(SHORT_TO_LABEL[short])

    all_problems = critical_sensors + warning_sensors
    problem_str = ", ".join(all_problems) if all_problems else "some parameters"

    if overall_status == "WARNING":
        return (
            f"Water conditions for your {stage_label} crayfish are starting to drift. "
            f"{problem_str} {'is' if len(all_problems) == 1 else 'are'} moving outside the safe range — "
            f"nothing critical yet, but it's worth checking now before it gets worse."
        )

    crit_str = ", ".join(critical_sensors) if critical_sensors else problem_str
    return (
        f"There's a problem with the tank that needs your attention right away. "
        f"{crit_str} {'is' if len(critical_sensors) == 1 else 'are'} outside the safe range "
        f"for {stage_label} crayfish. "
        f"If left unaddressed, this could stress or harm your crayfish."
    )


def generate_prediction(
    overall_status,
    sensor_statuses,
    stage,
    ranges,
    temp,
    ph,
    do_,
    turb,
    wl,
    temp_rate,
    ph_rate,
    do_rate,
    turb_rate,
    wl_rate,
):
    """
    Trend-based forecast: estimates how long before each sensor
    breaches its safe threshold at the current rate of change.
    Only shows sensors that are still OPTIMAL or WARNING but trending toward a breach.
    Skips sensors already CRITICAL (those go to recommendation).
    Only shows forecasts within 5 hours — beyond that, not worth alarming the farmer.
    """
    stage_label = STAGE_LABELS.get(stage, stage.replace("_", " ").title())

    sensors_data = [
        (
            "temp",
            temp,
            temp_rate,
            ranges.get("temp", {}).get("min", 24.0),
            ranges.get("temp", {}).get("max", 30.0),
        ),
        (
            "ph",
            ph,
            ph_rate,
            ranges.get("ph", {}).get("min", 7.0),
            ranges.get("ph", {}).get("max", 8.5),
        ),
        (
            "do",
            do_,
            do_rate,
            ranges.get("do", {}).get("min", 4.5),
            ranges.get("do", {}).get("max", 10.0),
        ),
        (
            "turb",
            turb,
            turb_rate,
            ranges.get("turb", {}).get("min", 0.0),
            ranges.get("turb", {}).get("max", 35.0),
        ),
        (
            "wl",
            wl,
            wl_rate,
            ranges.get("waterlevel", {}).get("min", 8.0),
            ranges.get("waterlevel", {}).get("max", 15.0),
        ),
    ]

    MAX_FORECAST_SECONDS = 5 * 3600  # only show forecasts within 5 hours

    forecasts = []

    for short, val, rate, r_min, r_max in sensors_data:
        label = SHORT_TO_LABEL[short]
        status = sensor_statuses.get(f"{short}_status", "OPTIMAL")

        # Skip if already critical or no trend
        if status == "CRITICAL" or rate == 0:
            continue

        if rate < 0 and val > r_min:
            readings_to_breach = (val - r_min) / abs(rate)
            seconds = readings_to_breach * READING_INTERVAL_SEC
            if seconds <= MAX_FORECAST_SECONDS:
                time_str = format_time(seconds)
                if status == "WARNING":
                    forecasts.append(
                        f"{label} is already in warning range and continuing to drop — "
                        f"it could reach a critical low in about {time_str} if the trend holds."
                    )
                else:
                    forecasts.append(
                        f"{label} is slowly trending downward. "
                        f"At the current rate, it may leave the safe range in about {time_str}."
                    )

        elif rate > 0 and val < r_max:
            readings_to_breach = (r_max - val) / abs(rate)
            seconds = readings_to_breach * READING_INTERVAL_SEC
            if seconds <= MAX_FORECAST_SECONDS:
                time_str = format_time(seconds)
                if status == "WARNING":
                    forecasts.append(
                        f"{label} is already in warning range and continuing to rise — "
                        f"it could reach a critical high in about {time_str} if the trend holds."
                    )
                else:
                    forecasts.append(
                        f"{label} is slowly trending upward. "
                        f"At the current rate, it may leave the safe range in about {time_str}."
                    )

    if not forecasts:
        if overall_status == "OPTIMAL":
            return (
                f"All parameters are currently stable for your {stage_label} crayfish. "
                f"No concerning trends detected — conditions look good for the next few hours."
            )
        else:
            return (
                f"CrayAI has detected issues with current water conditions "
                f"for your {stage_label} crayfish. "
                f"Address the flagged parameters to prevent further deterioration."
            )

    forecast_text = " ".join(forecasts)
    return (
        f"Based on current sensor trends, here's what CrayAI forecasts "
        f"for your {stage_label} crayfish: {forecast_text}"
    )


def generate_sensor_prediction(short, val, rate, r_min, r_max, status, confidence):
    label = SHORT_TO_LABEL[short]
    conf_pct = int(confidence * 100)

    if status == "CRITICAL":
        return (
            f"CrayAI is {conf_pct}% confident that {label} is critically out of range "
            f"and needs immediate attention."
        )

    if rate == 0:
        return (
            f"CrayAI is {conf_pct}% confident that {label} is currently {status.lower()} "
            f"with no significant change detected."
        )

    MAX_FORECAST_SECONDS = 5 * 3600

    if rate < 0 and val > r_min:
        readings_to_breach = (val - r_min) / abs(rate)
        seconds = readings_to_breach * READING_INTERVAL_SEC
        if seconds <= MAX_FORECAST_SECONDS:
            time_str = format_time(seconds)
            boundary = "low" if status == "WARNING" else "the safe range"
            return (
                f"CrayAI is {conf_pct}% confident that {label} is trending downward. "
                f"It may reach {boundary} in about {time_str} at the current rate."
            )

    elif rate > 0 and val < r_max:
        readings_to_breach = (r_max - val) / abs(rate)
        seconds = readings_to_breach * READING_INTERVAL_SEC
        if seconds <= MAX_FORECAST_SECONDS:
            time_str = format_time(seconds)
            boundary = "high" if status == "WARNING" else "the safe range"
            return (
                f"CrayAI is {conf_pct}% confident that {label} is trending upward. "
                f"It may reach {boundary} in about {time_str} at the current rate."
            )

    return (
        f"CrayAI is {conf_pct}% confident that {label} is currently {status.lower()} "
        f"with no immediate risk of change."
    )


def generate_recommendation(overall_status, sensor_statuses):
    if overall_status == "OPTIMAL":
        return (
            "No action needed right now. "
            "Continue your regular feeding schedule and check the tank once a day."
        )

    actions = []

    turb_s = sensor_statuses.get("turb_status", "OPTIMAL")
    if turb_s == "CRITICAL":
        actions.append(
            "Turbidity is high — the water pump should have already turned on to circulate water through the filter. "
            "Check that the pump is running and the filter media isn't clogged."
        )
    elif turb_s == "WARNING":
        actions.append(
            "Turbidity is getting cloudy. The pump will activate automatically, "
            "but keep an eye on the filter — it may need cleaning soon."
        )

    do_s = sensor_statuses.get("do_status", "OPTIMAL")
    if do_s == "CRITICAL":
        actions.append(
            "Dissolved oxygen is critically low — the aerator should have switched on automatically. "
            "Confirm it's running. If DO is still dropping, check for a blockage or increase aeration manually."
        )
    elif do_s == "WARNING":
        actions.append(
            "Dissolved oxygen is dropping. The aerator will kick in automatically — "
            "just make sure nothing is blocking the airstone or diffuser."
        )

    ph_s = sensor_statuses.get("ph_status", "OPTIMAL")
    if ph_s == "CRITICAL":
        actions.append(
            "pH is out of the safe range. Correct this manually — "
            "add a small dose of pH buffer (up if too acidic, down if too alkaline), "
            "wait 15 minutes, then re-check before adding more."
        )
    elif ph_s == "WARNING":
        actions.append(
            "pH is drifting slightly. Test the water manually "
            "and have your pH buffer ready in case it continues to shift."
        )

    temp_s = sensor_statuses.get("temp_status", "OPTIMAL")
    if temp_s == "CRITICAL":
        actions.append(
            "Water temperature is out of the safe range. "
            "Check if the tank is exposed to direct sunlight or a heat source. "
            "Adjust shading, ventilation, or do a partial water exchange as needed."
        )
    elif temp_s == "WARNING":
        actions.append(
            "Temperature is starting to go out of range. "
            "Check for environmental factors like sunlight or airflow near the tank."
        )

    wl_s = sensor_statuses.get("wl_status", "OPTIMAL")
    if wl_s == "CRITICAL":
        actions.append(
            "Water level is outside the safe range. "
            "Check for leaks, splashing, or evaporation. "
            "Top up or drain carefully — avoid sudden changes that could stress the crayfish."
        )
    elif wl_s == "WARNING":
        actions.append(
            "Water level is slightly off. Keep an eye on it "
            "and top up or drain slowly if needed."
        )

    base = (
        " ".join(actions)
        if actions
        else "Inspect the tank manually to identify the issue."
    )
    if overall_status == "CRITICAL":
        return f"Action needed: {base}"
    return base


def generate_sensor_insight(short, val, status, r_min, r_max):
    label = SHORT_TO_LABEL[short]
    unit = SHORT_TO_UNIT[short]
    val_str = f"{val}{unit}"

    if status == "OPTIMAL":
        return (
            f"{label} is at {val_str}, which is right within the safe range "
            f"({r_min}–{r_max}{unit}). No issues here."
        )
    elif status == "WARNING":
        return (
            f"{label} is at {val_str} and starting to move outside the safe range "
            f"({r_min}–{r_max}{unit}). It's not critical yet, but worth watching."
        )
    return (
        f"{label} is at {val_str}, which is outside the safe range "
        f"({r_min}–{r_max}{unit}). This needs attention to keep your crayfish healthy."
    )


def generate_sensor_recommendation(short, status):
    if status == "OPTIMAL":
        return "This parameter is fine — no action needed."

    recs = {
        "do": {
            "WARNING": (
                "Dissolved oxygen is getting low. The aerator will activate automatically. "
                "Make sure the airstone or diffuser isn't blocked."
            ),
            "CRITICAL": (
                "Dissolved oxygen is critically low — the aerator should already be running. "
                "Check that it's working. If DO keeps dropping, manually increase aeration "
                "or reduce stocking density temporarily."
            ),
        },
        "turb": {
            "WARNING": (
                "Water is getting cloudy. The pump will circulate water through the RAS filter automatically. "
                "Check the filter media — it might need rinsing soon."
            ),
            "CRITICAL": (
                "Turbidity is too high. The water pump should have activated to push water through the filter. "
                "Verify the pump is on and the filter isn't clogged. "
                "Do a partial water change if it doesn't clear up."
            ),
        },
        "ph": {
            "WARNING": (
                "pH is drifting. Monitor manually and prepare your pH buffer. "
                "Wait to see if it stabilizes before making any adjustment."
            ),
            "CRITICAL": (
                "pH is out of the safe range. Adjust manually with a pH buffer — "
                "add small amounts, wait 15 minutes, then re-test before adding more. "
                "Avoid large sudden changes, as they're harmful to crayfish."
            ),
        },
        "temp": {
            "WARNING": (
                "Temperature is drifting. Check for heat sources or drafts near the tank. "
                "Adjust shading or ventilation if needed."
            ),
            "CRITICAL": (
                "Temperature is out of the safe range. Check the environment around the tank — "
                "direct sunlight, fans, or heaters may be the cause. "
                "Do a partial water change with water at the correct temperature if needed."
            ),
        },
        "wl": {
            "WARNING": (
                "Water level is slightly off. Keep an eye on it and top up or drain slowly "
                "if it continues to drift."
            ),
            "CRITICAL": (
                "Water level is out of the safe range. Check for leaks, evaporation, or overflow. "
                "Adjust slowly — sudden level changes can stress the crayfish."
            ),
        },
    }
    return recs.get(short, {}).get(status, "Inspect this parameter manually.")


# ── Firebase ──────────────────────────────────────────────────


def resolve_credentials():
    env_creds = os.environ.get("FIREBASE_SERVICE_ACCOUNT")
    if env_creds:
        try:
            return credentials.Certificate(json.loads(env_creds))
        except Exception as e:
            print(f"[ML] Failed to parse FIREBASE_SERVICE_ACCOUNT env: {e}")
    local = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
    if os.path.exists(local):
        return credentials.Certificate(local)
    raise FileNotFoundError("No Firebase credentials found.")


def get_current_stage_ranges(config_ref):
    config = config_ref.get() or {}
    stage = config.get("selectedStage") or "pre_adult"
    stage_config = config.get(stage, {})
    defaults = {
        "temp": {"min": 24.0, "max": 30.0},
        "ph": {"min": 7.0, "max": 8.5},
        "do": {"min": 4.5, "max": 10.0},
        "turb": {"min": 0.0, "max": 35.0},
        "waterlevel": {"min": 8.0, "max": 15.0},
    }
    ranges = {}
    for key in defaults:
        sr = stage_config.get(key, {}) if isinstance(stage_config, dict) else {}
        if not sr:
            sr = config.get("ranges", {}).get(key, {})
        if not sr:
            sr = defaults[key]
        ranges[key] = {
            "min": float(sr.get("min", defaults[key]["min"])),
            "max": float(sr.get("max", defaults[key]["max"])),
        }
    return stage, ranges


prediction_ref = None
config_ref = None
latest_ref = None


def on_sensor_change(event):
    try:
        data = event.data
        if not data:
            return

        temp = data.get("temperature")
        ph = data.get("phLevel")
        do_ = data.get("dissolvedOxygen")
        turb = data.get("turbidity")
        wl = data.get("waterLevel")
        if any(v is None for v in [temp, ph, do_, turb, wl]):
            return

        for k, v in [
            ("temp", temp),
            ("ph", ph),
            ("do", do_),
            ("turb", turb),
            ("wl", wl),
        ]:
            histories[k].add(v)

        temp_rate = histories["temp"].get_rate()
        ph_rate = histories["ph"].get_rate()
        do_rate = histories["do"].get_rate()
        turb_rate = histories["turb"].get_rate()
        wl_rate = histories["wl"].get_rate()

        stage, ranges = get_current_stage_ranges(config_ref)
        t_min, t_max = ranges["temp"]["min"], ranges["temp"]["max"]
        p_min, p_max = ranges["ph"]["min"], ranges["ph"]["max"]
        d_min, d_max = ranges["do"]["min"], ranges["do"]["max"]
        tr_min, tr_max = ranges["turb"]["min"], ranges["turb"]["max"]
        wl_min, wl_max = ranges["waterlevel"]["min"], ranges["waterlevel"]["max"]

        X = build_feature_row(
            temp,
            ph,
            do_,
            turb,
            wl,
            temp_rate,
            ph_rate,
            do_rate,
            turb_rate,
            wl_rate,
            t_min,
            t_max,
            p_min,
            p_max,
            d_min,
            d_max,
            tr_min,
            tr_max,
            wl_min,
            wl_max,
            stage,
        )

        sensor_statuses, overall_status, confidence = predict_all(X)
        conf_pct = int(confidence * 100)
        stage_label = STAGE_LABELS.get(stage, stage.replace("_", " ").title())

        sensors_list = []
        rate_map = {
            "temp": temp_rate,
            "ph": ph_rate,
            "do": do_rate,
            "turb": turb_rate,
            "wl": wl_rate,
        }

        for sk, short, r_min, r_max in [
            ("temperature", "temp", t_min, t_max),
            ("phLevel", "ph", p_min, p_max),
            ("dissolvedOxygen", "do", d_min, d_max),
            ("turbidity", "turb", tr_min, tr_max),
            ("waterLevel", "wl", wl_min, wl_max),
        ]:
            status = sensor_statuses.get(f"{short}_status", "OPTIMAL")
            val = {"temp": temp, "ph": ph, "do": do_, "turb": turb, "wl": wl}[short]
            sensors_list.append(
                {
                    "key": sk,
                    "label": SHORT_TO_LABEL[short],
                    "status": status,
                    "confidence": confidence,
                    "insight": generate_sensor_insight(
                        short, val, status, r_min, r_max
                    ),
                    "prediction": generate_sensor_prediction(
                        short, val, rate_map[short], r_min, r_max, status, confidence
                    ),
                    "recommendation": generate_sensor_recommendation(short, status),
                }
            )

        result = {
            "predictedStatus": overall_status,
            "confidence": confidence,
            "stage": stage,
            "sensors": {s["key"]: s for s in sensors_list},
            "insight": generate_insight(overall_status, sensor_statuses, stage, ranges),
            "prediction": generate_prediction(
                overall_status,
                sensor_statuses,
                stage,
                ranges,
                temp,
                ph,
                do_,
                turb,
                wl,
                temp_rate,
                ph_rate,
                do_rate,
                turb_rate,
                wl_rate,
            ),
            "recommendation": generate_recommendation(overall_status, sensor_statuses),
            "timestamp": int(time.time() * 1000),
        }

        print(f"[ML] Stage={stage} Overall={overall_status} ({conf_pct}%)")
        for s in sensors_list:
            print(f"  {s['label']:20s}: {s['status']}")

        prediction_ref.set(result)

        now_sec = time.time()
        if now_sec - getattr(on_sensor_change, "_last_log", 0) >= 600:
            on_sensor_change._last_log = now_sec
            from datetime import datetime, timezone

            dt = datetime.now(timezone.utc)
            date_key = dt.strftime("%Y-%m-%d")
            time_key = dt.strftime("%H:%M")
            db.reference(f"ml_predictions/history/{date_key}/{time_key}").set(result)

    except Exception as e:
        print(f"[ML] Listener error: {e}")
        import traceback

        traceback.print_exc()


def start_listener():
    global prediction_ref, config_ref, latest_ref
    try:
        cred = resolve_credentials()
        firebase_admin.initialize_app(cred, {"databaseURL": DATABASE_URL})
        print("[ML] Firebase Admin initialized")
        prediction_ref = db.reference("ml_predictions/latest")
        config_ref = db.reference("sensor_readings/config")
        latest_ref = db.reference("sensor_readings/latest")
        print("[ML] Listening to sensor_readings/latest...")
        latest_ref.listen(on_sensor_change)
    except Exception as e:
        print(f"[ML] Failed to start listener: {e}")


# ── Flask Routes ──────────────────────────────────────────────


@app.route("/")
def home():
    return jsonify(
        {
            "message": "CrayCare ML Worker v3",
            "status": "running",
            "models_loaded": sensor_model is not None,
            "listener_active": prediction_ref is not None,
        }
    )


@app.route("/predict", methods=["POST"])
def predict():
    data = request.get_json()
    try:
        temp = float(data["temperature"])
        ph = float(data["phLevel"])
        do_ = float(data["dissolvedOxygen"])
        turb = float(data["turbidity"])
        wl = float(data["waterLevel"])
        stage = data.get("stage", "pre_adult")

        temp_rate = float(data.get("temp_rate", 0.0))
        ph_rate = float(data.get("ph_rate", 0.0))
        do_rate = float(data.get("do_rate", 0.0))
        turb_rate = float(data.get("turb_rate", 0.0))
        wl_rate = float(data.get("wl_rate", 0.0))

        t_min = float(data.get("temp_min", 24.0))
        t_max = float(data.get("temp_max", 30.0))
        p_min = float(data.get("ph_min", 7.0))
        p_max = float(data.get("ph_max", 8.5))
        d_min = float(data.get("do_min", 4.5))
        d_max = float(data.get("do_max", 10.0))
        tr_min = float(data.get("turb_min", 0.0))
        tr_max = float(data.get("turb_max", 35.0))
        wl_min = float(data.get("wl_min", 8.0))
        wl_max = float(data.get("wl_max", 15.0))

        ranges = {
            "temp": {"min": t_min, "max": t_max},
            "ph": {"min": p_min, "max": p_max},
            "do": {"min": d_min, "max": d_max},
            "turb": {"min": tr_min, "max": tr_max},
            "waterlevel": {"min": wl_min, "max": wl_max},
        }

        X = build_feature_row(
            temp,
            ph,
            do_,
            turb,
            wl,
            temp_rate,
            ph_rate,
            do_rate,
            turb_rate,
            wl_rate,
            t_min,
            t_max,
            p_min,
            p_max,
            d_min,
            d_max,
            tr_min,
            tr_max,
            wl_min,
            wl_max,
            stage,
        )

        sensor_statuses, overall_status, confidence = predict_all(X)
        conf_pct = int(confidence * 100)
        stage_label = STAGE_LABELS.get(stage, stage.replace("_", " ").title())

        rate_map = {
            "temp": temp_rate,
            "ph": ph_rate,
            "do": do_rate,
            "turb": turb_rate,
            "wl": wl_rate,
        }

        sensors_output = []
        for sk, short, r_min, r_max in [
            ("temperature", "temp", t_min, t_max),
            ("phLevel", "ph", p_min, p_max),
            ("dissolvedOxygen", "do", d_min, d_max),
            ("turbidity", "turb", tr_min, tr_max),
            ("waterLevel", "wl", wl_min, wl_max),
        ]:
            status = sensor_statuses.get(f"{short}_status", "OPTIMAL")
            val = {"temp": temp, "ph": ph, "do": do_, "turb": turb, "wl": wl}[short]
            sensors_output.append(
                {
                    "key": sk,
                    "label": SHORT_TO_LABEL[short],
                    "status": status,
                    "confidence": confidence,
                    "insight": generate_sensor_insight(
                        short, val, status, r_min, r_max
                    ),
                    "prediction": generate_sensor_prediction(
                        short, val, rate_map[short], r_min, r_max, status, confidence
                    ),
                    "recommendation": generate_sensor_recommendation(short, status),
                }
            )

        return jsonify(
            {
                "sensors": sensors_output,
                "predictedStatus": overall_status,
                "confidence": confidence,
                "stage": stage,
                "insight": generate_insight(
                    overall_status, sensor_statuses, stage, ranges
                ),
                "prediction": generate_prediction(
                    overall_status,
                    sensor_statuses,
                    stage,
                    ranges,
                    temp,
                    ph,
                    do_,
                    turb,
                    wl,
                    temp_rate,
                    ph_rate,
                    do_rate,
                    turb_rate,
                    wl_rate,
                ),
                "recommendation": generate_recommendation(
                    overall_status, sensor_statuses
                ),
            }
        )

    except KeyError as e:
        return jsonify({"error": f"Missing parameter: {e.args[0]}"}), 400
    except Exception as e:
        return jsonify({"error": f"Prediction failed: {str(e)}"}), 500


# ── Start ─────────────────────────────────────────────────────

listener_thread = threading.Thread(target=start_listener, daemon=True)
listener_thread.start()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
