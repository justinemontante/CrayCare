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

# ── Load Model ────────────────────────────────────────────────
MODELS_DIR = os.path.join(os.path.dirname(__file__), "models")

overall_model = None
encoders = None
feature_cols = None

try:
    with open(os.path.join(MODELS_DIR, "overall_model.pkl"), "rb") as f:
        overall_model = pickle.load(f)
    with open(os.path.join(MODELS_DIR, "encoders.pkl"), "rb") as f:
        encoders = pickle.load(f)
    with open(os.path.join(MODELS_DIR, "feature_cols.pkl"), "rb") as f:
        feature_cols = pickle.load(f)
    print("[ML] Model loaded successfully")
except Exception as e:
    print(f"[ML] WARNING: Could not load model — {e}")

# ── Constants ─────────────────────────────────────────────────
READING_INTERVAL_SEC = 5

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
    stage_enc = (
        encoders["growth_stage"].transform([stage_str])[0]
        if encoders
        else STAGE_MAP.get(stage_str, 2)
    )
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
        "growth_stage": stage_enc,
    }
    return pd.DataFrame([row], columns=feature_cols)


def predict_status(X):
    """Run ML model — returns (overall_status, confidence)."""
    if overall_model is None:
        return "OPTIMAL", 0.5
    pred = overall_model.predict(X)[0]
    probs = overall_model.predict_proba(X)[0]
    status_str = (
        encoders[
            overall_model.classes_[0].__class__.__name__ if False else "health_status"
        ].inverse_transform([pred])[0]
        if "health_status" in encoders
        else ["CRITICAL", "OPTIMAL", "WARNING"][pred]
    )
    # Safer fallback using encoder
    try:
        status_str = encoders["health_status"].inverse_transform([pred])[0]
    except Exception:
        pass
    return status_str, float(max(probs))


# ── Rule-based per-sensor status from raw values ──────────────
def get_sensor_status(val, vmin, vmax):
    span = vmax - vmin
    if span <= 0:
        return "OPTIMAL"
    ratio = (val - vmin) / span
    if ratio < 0 or ratio > 1:
        return "CRITICAL"
    if ratio < 0.10 or ratio > 0.90:
        return "WARNING"
    return "OPTIMAL"


# ── Sensor combination detection ──────────────────────────────
def detect_combinations(
    sensor_statuses,
    temp,
    ph,
    do_,
    turb,
    t_min,
    t_max,
    p_min,
    p_max,
    d_min,
    d_max,
    tr_min,
    tr_max,
):
    """
    Returns a list of active dangerous combinations.
    Each combo is a dict with: sensors, insight, prediction_note, recommendation
    """
    combos = []

    temp_s = sensor_statuses.get("temp_status", "OPTIMAL")
    ph_s = sensor_statuses.get("ph_status", "OPTIMAL")
    do_s = sensor_statuses.get("do_status", "OPTIMAL")
    turb_s = sensor_statuses.get("turb_status", "OPTIMAL")

    temp_high = temp > t_max and temp_s in ("WARNING", "CRITICAL")
    temp_low = temp < t_min and temp_s in ("WARNING", "CRITICAL")
    ph_low = ph < p_min and ph_s in ("WARNING", "CRITICAL")
    ph_high = ph > p_max and ph_s in ("WARNING", "CRITICAL")
    do_low = do_ < d_min and do_s in ("WARNING", "CRITICAL")
    turb_high = turb > tr_max and turb_s in ("WARNING", "CRITICAL")

    # HIGH TEMP + LOW DO — most dangerous combination
    if temp_high and do_low:
        combos.append(
            {
                "sensors": ["Temperature", "Dissolved Oxygen"],
                "insight": (
                    f"Temperature is elevated at {round(temp, 1)}°C while Dissolved Oxygen "
                    f"is critically low at {round(do_, 1)} mg/L. This is a heat-oxygen cycle — "
                    f"warm water naturally holds less dissolved oxygen, meaning your crayfish "
                    f"are experiencing heat stress and oxygen deprivation at the same time. "
                    f"This is the most dangerous water quality combination in aquaculture."
                ),
                "prediction_note": (
                    "As temperature continues to rise, dissolved oxygen will drop further "
                    "even without additional changes. Both trends will worsen each other."
                ),
                "recommendation": (
                    "Address temperature first — cooling the water will naturally help oxygen "
                    "recover. Check for direct sunlight or heat sources near the tank. "
                    "Add shade or improve ventilation immediately. The aerator has activated "
                    "automatically, but it cannot fully compensate for heat-induced oxygen loss. "
                    "Do a partial water exchange with cooler water if temperature does not drop."
                ),
            }
        )

    # LOW pH + LOW DO
    elif ph_low and do_low:
        combos.append(
            {
                "sensors": ["pH Level", "Dissolved Oxygen"],
                "insight": (
                    f"pH Level is acidic at {round(ph, 2)} while Dissolved Oxygen is low "
                    f"at {round(do_, 1)} mg/L. Acidic water reduces the ability of crayfish "
                    f"blood to carry oxygen — even if DO improves, your crayfish may still "
                    f"struggle to absorb it. Shell corrosion and gill damage are likely "
                    f"if this combination persists."
                ),
                "prediction_note": (
                    "Restoring DO alone will not be enough — pH must be corrected first "
                    "for the crayfish to properly utilize available oxygen."
                ),
                "recommendation": (
                    "Fix pH first before expecting DO to recover. Apply pH buffer slowly "
                    "to raise pH toward the safe range. Wait 15 minutes and re-test before "
                    "adding more. The aerator has activated automatically to assist DO. "
                    "Do not increase feeding during this period — uneaten food worsens both "
                    "pH and oxygen levels."
                ),
            }
        )

    # HIGH TURBIDITY + LOW DO
    elif turb_high and do_low:
        combos.append(
            {
                "sensors": ["Turbidity", "Dissolved Oxygen"],
                "insight": (
                    f"Turbidity is high at {round(turb, 1)} NTU while Dissolved Oxygen "
                    f"is low at {round(do_, 1)} mg/L. High turbidity from organic matter "
                    f"and bacteria in suspension is actively consuming oxygen in your tank. "
                    f"The cloudier the water, the faster oxygen depletes."
                ),
                "prediction_note": (
                    "Dissolved oxygen will continue to drop as long as turbidity remains high. "
                    "Clearing the water is the priority — DO will recover once organic load reduces."
                ),
                "recommendation": (
                    "The RAS water pump has activated automatically to circulate water through "
                    "the filter. Check that the pump is running and the filter media is not clogged. "
                    "The aerator is also running to boost DO. Do a partial water change if turbidity "
                    "does not improve within 30 minutes. Reduce feeding temporarily to lower "
                    "organic load in the tank."
                ),
            }
        )

    # HIGH TEMP + HIGH TURBIDITY
    elif temp_high and turb_high:
        combos.append(
            {
                "sensors": ["Temperature", "Turbidity"],
                "insight": (
                    f"Temperature is elevated at {round(temp, 1)}°C and turbidity is high "
                    f"at {round(turb, 1)} NTU. Warm, cloudy water is an ideal environment "
                    f"for rapid bacterial and algae growth. Dissolved oxygen is likely to "
                    f"crash soon if both parameters are not addressed immediately."
                ),
                "prediction_note": (
                    "If temperature and turbidity both remain elevated, expect dissolved "
                    "oxygen to drop to critical levels within the next 1–2 hours."
                ),
                "recommendation": (
                    "The RAS water pump has activated to filter the water. Reduce heat exposure "
                    "by adding shade or improving ventilation. Do not feed until both parameters "
                    "are back in the safe range — additional organic matter will accelerate "
                    "bacterial growth and oxygen depletion. Monitor DO closely."
                ),
            }
        )

    # LOW pH + HIGH TURBIDITY
    elif ph_low and turb_high:
        combos.append(
            {
                "sensors": ["pH Level", "Turbidity"],
                "insight": (
                    f"pH Level is acidic at {round(ph, 2)} while turbidity is high at "
                    f"{round(turb, 1)} NTU. Acidic, cloudy water often indicates organic "
                    f"decomposition in the tank — rotting waste and uneaten food produce "
                    f"acids that lower pH and increase turbidity simultaneously."
                ),
                "prediction_note": (
                    "Both parameters will continue to worsen if organic waste is not removed. "
                    "Dissolved oxygen is at risk of dropping next."
                ),
                "recommendation": (
                    "The RAS water pump has activated to circulate water through the filter. "
                    "Correct pH manually with buffer while the pump runs. Remove any visible "
                    "uneaten food or waste from the tank. Check filter media and clean if needed. "
                    "Avoid overfeeding until conditions stabilize."
                ),
            }
        )

    # HIGH pH + LOW DO
    elif ph_high and do_low:
        combos.append(
            {
                "sensors": ["pH Level", "Dissolved Oxygen"],
                "insight": (
                    f"pH Level is alkaline at {round(ph, 2)} while Dissolved Oxygen is low "
                    f"at {round(do_, 1)} mg/L. High pH can indicate an algae bloom — "
                    f"algae consume CO2 during the day raising pH, but consume oxygen at night, "
                    f"causing DO to crash. Check for green water or algae on tank walls."
                ),
                "prediction_note": (
                    "If this is an algae bloom, DO will fluctuate with the light cycle — "
                    "higher during daylight, dangerously low at night."
                ),
                "recommendation": (
                    "The aerator has activated to boost DO. Manually correct pH with buffer. "
                    "Check for algae growth and reduce light exposure to the tank if present. "
                    "Do a partial water change to dilute algae concentration. Monitor DO "
                    "closely overnight as it may drop further in the dark."
                ),
            }
        )

    return combos


# ── Time formatter ────────────────────────────────────────────
def format_time(seconds):
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
            return (
                f"{hours} hour{'s' if hours > 1 else ''} "
                f"and {minutes} minute{'s' if minutes > 1 else ''}"
            )


# ── OVERALL TEXT GENERATORS ───────────────────────────────────


def generate_insight(
    overall_status,
    sensor_statuses,
    stage,
    ranges,
    temp,
    ph,
    do_,
    turb,
    t_min,
    t_max,
    p_min,
    p_max,
    d_min,
    d_max,
    tr_min,
    tr_max,
):
    stage_label = STAGE_LABELS.get(stage, stage.replace("_", " ").title())

    if overall_status == "OPTIMAL":
        return (
            f"Everything looks good in the tank right now. "
            f"All five water parameters are within the safe range for your "
            f"{stage_label} crayfish. Keep up the current routine — they're doing well."
        )

    # Check for dangerous sensor combinations first
    combos = detect_combinations(
        sensor_statuses,
        temp,
        ph,
        do_,
        turb,
        t_min,
        t_max,
        p_min,
        p_max,
        d_min,
        d_max,
        tr_min,
        tr_max,
    )
    if combos:
        return combos[0]["insight"]

    # Single-sensor problems
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
            f"{problem_str} {'is' if len(all_problems) == 1 else 'are'} moving outside "
            f"the safe range — nothing critical yet, but it's worth checking now "
            f"before it gets worse."
        )

    crit_str = ", ".join(critical_sensors) if critical_sensors else problem_str
    return (
        f"There's a problem with the tank that needs your attention right away. "
        f"{crit_str} {'is' if len(critical_sensors) == 1 else 'are'} outside the "
        f"safe range for {stage_label} crayfish. "
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
    t_min,
    t_max,
    p_min,
    p_max,
    d_min,
    d_max,
    tr_min,
    tr_max,
):
    stage_label = STAGE_LABELS.get(stage, stage.replace("_", " ").title())

    # Check combinations first — they get a compound forecast
    combos = detect_combinations(
        sensor_statuses,
        temp,
        ph,
        do_,
        turb,
        t_min,
        t_max,
        p_min,
        p_max,
        d_min,
        d_max,
        tr_min,
        tr_max,
    )

    combo_note = ""
    if combos:
        combo_note = combos[0]["prediction_note"] + " "

    # Individual trend forecasts
    sensors_data = [
        ("temp", temp, temp_rate, t_min, t_max),
        ("ph", ph, ph_rate, p_min, p_max),
        ("do", do_, do_rate, d_min, d_max),
        ("turb", turb, turb_rate, tr_min, tr_max),
        (
            "wl",
            wl,
            wl_rate,
            ranges.get("waterlevel", {}).get("min", 8.0),
            ranges.get("waterlevel", {}).get("max", 15.0),
        ),
    ]

    MAX_SEC = 5 * 3600
    forecasts = []

    for short, val, rate, r_min, r_max in sensors_data:
        label = SHORT_TO_LABEL[short]
        status = sensor_statuses.get(f"{short}_status", "OPTIMAL")
        if status == "CRITICAL" or rate == 0:
            continue

        if rate < 0 and val > r_min:
            secs = ((val - r_min) / abs(rate)) * READING_INTERVAL_SEC
            if secs <= MAX_SEC:
                t = format_time(secs)
                if status == "WARNING":
                    forecasts.append(
                        f"{label} is already in warning range and continuing to drop — "
                        f"it could reach a critical low in about {t} if the trend holds."
                    )
                else:
                    forecasts.append(
                        f"{label} is trending downward. "
                        f"At the current rate, it may leave the safe range in about {t}."
                    )
        elif rate > 0 and val < r_max:
            secs = ((r_max - val) / abs(rate)) * READING_INTERVAL_SEC
            if secs <= MAX_SEC:
                t = format_time(secs)
                if status == "WARNING":
                    forecasts.append(
                        f"{label} is already in warning range and continuing to rise — "
                        f"it could reach a critical high in about {t} if the trend holds."
                    )
                else:
                    forecasts.append(
                        f"{label} is trending upward. "
                        f"At the current rate, it may leave the safe range in about {t}."
                    )

    if not forecasts and not combo_note:
        if overall_status == "OPTIMAL":
            return (
                f"All parameters are currently stable for your {stage_label} crayfish. "
                f"No concerning trends detected — conditions look good for the next few hours."
            )
        return (
            f"CrayAI has detected issues with current water conditions for your "
            f"{stage_label} crayfish. Address the flagged parameters to prevent "
            f"further deterioration."
        )

    forecast_text = " ".join(forecasts)
    base = f"Based on current sensor trends, here's what CrayAI forecasts for your {stage_label} crayfish: "
    return base + combo_note + forecast_text


def generate_recommendation(
    overall_status,
    sensor_statuses,
    temp,
    ph,
    do_,
    turb,
    t_min,
    t_max,
    p_min,
    p_max,
    d_min,
    d_max,
    tr_min,
    tr_max,
):
    if overall_status == "OPTIMAL":
        return (
            "No action needed right now. "
            "Continue your regular feeding schedule and check the tank once a day."
        )

    # Combination-aware recommendation first
    combos = detect_combinations(
        sensor_statuses,
        temp,
        ph,
        do_,
        turb,
        t_min,
        t_max,
        p_min,
        p_max,
        d_min,
        d_max,
        tr_min,
        tr_max,
    )
    if combos:
        prefix = "Action needed: " if overall_status == "CRITICAL" else ""
        return prefix + combos[0]["recommendation"]

    # Single-sensor fallback
    actions = []

    if sensor_statuses.get("turb_status") == "CRITICAL":
        actions.append(
            "Turbidity is high — the water pump has activated to circulate water through "
            "the filter. Confirm it is running and the filter media is not clogged."
        )
    elif sensor_statuses.get("turb_status") == "WARNING":
        actions.append(
            "Turbidity is getting cloudy. The pump will activate automatically — "
            "keep an eye on the filter, it may need cleaning soon."
        )

    if sensor_statuses.get("do_status") == "CRITICAL":
        actions.append(
            "Dissolved oxygen is critically low — the aerator has switched on automatically. "
            "Confirm it is running. If DO is still dropping, check for a blockage "
            "or increase aeration manually."
        )
    elif sensor_statuses.get("do_status") == "WARNING":
        actions.append(
            "Dissolved oxygen is dropping. The aerator will kick in automatically — "
            "make sure nothing is blocking the airstone or diffuser."
        )

    if sensor_statuses.get("ph_status") == "CRITICAL":
        actions.append(
            "pH is out of the safe range. Correct this manually — add a small dose "
            "of pH buffer (up if too acidic, down if too alkaline), wait 15 minutes, "
            "then re-check before adding more."
        )
    elif sensor_statuses.get("ph_status") == "WARNING":
        actions.append(
            "pH is drifting slightly. Test the water manually and have your pH buffer "
            "ready in case it continues to shift."
        )

    if sensor_statuses.get("temp_status") == "CRITICAL":
        actions.append(
            "Water temperature is out of the safe range. Check for direct sunlight or "
            "heat sources near the tank. Adjust shading, ventilation, or do a partial "
            "water exchange as needed."
        )
    elif sensor_statuses.get("temp_status") == "WARNING":
        actions.append(
            "Temperature is starting to go out of range. Check for environmental "
            "factors like sunlight or airflow near the tank."
        )

    if sensor_statuses.get("wl_status") == "CRITICAL":
        actions.append(
            "Water level is outside the safe range. Check for leaks, splashing, or "
            "evaporation. Top up or drain carefully — avoid sudden changes that could "
            "stress the crayfish."
        )
    elif sensor_statuses.get("wl_status") == "WARNING":
        actions.append(
            "Water level is slightly off. Keep an eye on it and top up or drain "
            "slowly if needed."
        )

    base = (
        " ".join(actions)
        if actions
        else "Inspect the tank manually to identify the issue."
    )
    return f"Action needed: {base}" if overall_status == "CRITICAL" else base


# ── PER-SENSOR TEXT GENERATORS ────────────────────────────────


def generate_sensor_insight(short, val, status, r_min, r_max):
    label = SHORT_TO_LABEL[short]
    unit = SHORT_TO_UNIT[short]
    val_str = f"{val}{unit}"

    context = {
        "temp": {
            "OPTIMAL": "Temperature directly affects crayfish metabolism and molting.",
            "WARNING": "Crayfish become lethargic and feed poorly outside their temperature range.",
            "CRITICAL": "Extreme temperatures cause severe physiological stress and can be fatal.",
        },
        "ph": {
            "OPTIMAL": "Stable pH keeps crayfish shells strong and gill function healthy.",
            "WARNING": "pH drift affects crayfish ability to regulate body chemistry.",
            "CRITICAL": "Extreme pH causes shell corrosion, gill damage, and can be lethal.",
        },
        "do": {
            "OPTIMAL": "Adequate oxygen supports healthy activity, feeding, and growth.",
            "WARNING": "Crayfish may become sluggish and move toward the water surface.",
            "CRITICAL": "Critically low oxygen causes rapid stress and mass mortality within hours.",
        },
        "turb": {
            "OPTIMAL": "Clear water indicates good filtration and low organic load.",
            "WARNING": "Increasing cloudiness suggests rising bacterial or organic matter levels.",
            "CRITICAL": "High turbidity reduces oxygen, clogs gills, and indicates poor water quality.",
        },
        "wl": {
            "OPTIMAL": "Stable water level maintains proper tank conditions for your crayfish.",
            "WARNING": "Water level drift may affect aeration coverage and tank stability.",
            "CRITICAL": "Extreme water level changes stress crayfish and disrupt tank equipment.",
        },
    }

    ctx = context.get(short, {}).get(status, "")

    if status == "OPTIMAL":
        return (
            f"{label} is at {val_str}, right within the safe range "
            f"({r_min}–{r_max}{unit}). {ctx}"
        )
    elif status == "WARNING":
        return (
            f"{label} is at {val_str} and moving outside the safe range "
            f"({r_min}–{r_max}{unit}). {ctx}"
        )
    return (
        f"{label} is at {val_str}, outside the safe range "
        f"({r_min}–{r_max}{unit}). {ctx}"
    )


def generate_sensor_prediction(short, val, rate, r_min, r_max, status, confidence):
    label = SHORT_TO_LABEL[short]
    conf_pct = int(confidence * 100)

    if status == "CRITICAL":
        return (
            f"CrayAI is {conf_pct}% confident that {label} is critically out of range "
            f"and requires immediate attention."
        )
    if rate == 0:
        return (
            f"CrayAI is {conf_pct}% confident that {label} is currently "
            f"{status.lower()} with no significant trend detected."
        )

    MAX_SEC = 5 * 3600
    if rate < 0 and val > r_min:
        secs = ((val - r_min) / abs(rate)) * READING_INTERVAL_SEC
        if secs <= MAX_SEC:
            t = format_time(secs)
            boundary = "a critical low" if status == "WARNING" else "the safe minimum"
            return (
                f"CrayAI is {conf_pct}% confident that {label} is trending downward. "
                f"At the current rate, it may reach {boundary} in about {t}."
            )
    elif rate > 0 and val < r_max:
        secs = ((r_max - val) / abs(rate)) * READING_INTERVAL_SEC
        if secs <= MAX_SEC:
            t = format_time(secs)
            boundary = "a critical high" if status == "WARNING" else "the safe maximum"
            return (
                f"CrayAI is {conf_pct}% confident that {label} is trending upward. "
                f"At the current rate, it may reach {boundary} in about {t}."
            )

    return (
        f"CrayAI is {conf_pct}% confident that {label} is currently "
        f"{status.lower()} with no immediate risk of change."
    )


def generate_sensor_recommendation(short, status):
    if status == "OPTIMAL":
        return "This parameter is within the safe range — no action needed."
    recs = {
        "do": {
            "WARNING": (
                "Dissolved oxygen is getting low. The aerator will activate automatically. "
                "Make sure the airstone or diffuser is not blocked."
            ),
            "CRITICAL": (
                "Dissolved oxygen is critically low — the aerator should already be running. "
                "Verify it is working. If DO keeps dropping, manually increase aeration "
                "or reduce stocking density temporarily."
            ),
        },
        "turb": {
            "WARNING": (
                "Water is getting cloudy. The RAS water pump will activate automatically. "
                "Check the filter media — it may need rinsing soon."
            ),
            "CRITICAL": (
                "Turbidity is too high. The water pump has activated to push water through "
                "the filter. Verify the pump is on and the filter is not clogged. "
                "Do a partial water change if it does not clear up."
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
                "Avoid large sudden changes, as rapid pH swings are harmful to crayfish."
            ),
        },
        "temp": {
            "WARNING": (
                "Temperature is drifting. Check for heat sources or drafts near the tank. "
                "Adjust shading or ventilation if needed."
            ),
            "CRITICAL": (
                "Temperature is out of the safe range. Check the environment around the "
                "tank — direct sunlight, fans, or heaters may be the cause. "
                "Do a partial water change with water at the correct temperature if needed."
            ),
        },
        "wl": {
            "WARNING": (
                "Water level is slightly off. Keep an eye on it and top up or drain "
                "slowly if it continues to drift."
            ),
            "CRITICAL": (
                "Water level is out of the safe range. Check for leaks, evaporation, "
                "or overflow. Adjust slowly — sudden changes stress the crayfish."
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
            print(f"[ML] Failed to parse FIREBASE_SERVICE_ACCOUNT: {e}")
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


def _build_result(
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
    stage,
    ranges,
):
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
    overall_status, confidence = predict_status(X)

    # Per-sensor status from rules (no separate ML model needed)
    sensor_statuses = {
        "temp_status": get_sensor_status(temp, t_min, t_max),
        "ph_status": get_sensor_status(ph, p_min, p_max),
        "do_status": get_sensor_status(do_, d_min, d_max),
        "turb_status": get_sensor_status(turb, tr_min, tr_max),
        "wl_status": get_sensor_status(wl, wl_min, wl_max),
    }

    return {
        "predictedStatus": overall_status,
        "confidence": confidence,
        "stage": stage,
        "insight": generate_insight(
            overall_status,
            sensor_statuses,
            stage,
            ranges,
            temp,
            ph,
            do_,
            turb,
            t_min,
            t_max,
            p_min,
            p_max,
            d_min,
            d_max,
            tr_min,
            tr_max,
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
            t_min,
            t_max,
            p_min,
            p_max,
            d_min,
            d_max,
            tr_min,
            tr_max,
        ),
        "recommendation": generate_recommendation(
            overall_status,
            sensor_statuses,
            temp,
            ph,
            do_,
            turb,
            t_min,
            t_max,
            p_min,
            p_max,
            d_min,
            d_max,
            tr_min,
            tr_max,
        ),
        "timestamp": int(time.time() * 1000),
    }


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
        result = _build_result(
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
            stage,
            ranges,
        )

        conf_pct = int(result["confidence"] * 100)
        print(f"[ML] Stage={stage} Overall={result['predictedStatus']} ({conf_pct}%)")

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
            "message": "CrayCare ML Worker v4",
            "status": "running",
            "model_loaded": overall_model is not None,
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

        ranges = {
            "temp": {
                "min": float(data.get("temp_min", 24.0)),
                "max": float(data.get("temp_max", 30.0)),
            },
            "ph": {
                "min": float(data.get("ph_min", 7.0)),
                "max": float(data.get("ph_max", 8.5)),
            },
            "do": {
                "min": float(data.get("do_min", 4.5)),
                "max": float(data.get("do_max", 10.0)),
            },
            "turb": {
                "min": float(data.get("turb_min", 0.0)),
                "max": float(data.get("turb_max", 35.0)),
            },
            "waterlevel": {
                "min": float(data.get("wl_min", 8.0)),
                "max": float(data.get("wl_max", 15.0)),
            },
        }

        result = _build_result(
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
            stage,
            ranges,
        )
        return jsonify(result)

    except KeyError as e:
        return jsonify({"error": f"Missing parameter: {e.args[0]}"}), 400
    except Exception as e:
        return jsonify({"error": f"Prediction failed: {str(e)}"}), 500


# ── Start ─────────────────────────────────────────────────────
listener_thread = threading.Thread(target=start_listener, daemon=True)
listener_thread.start()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
