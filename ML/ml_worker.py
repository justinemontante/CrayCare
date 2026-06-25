import sys, os, time, json
import pickle
import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(__file__))

import firebase_admin
from firebase_admin import db, credentials

SERVICE_ACCOUNT_ENV = os.environ.get("FIREBASE_SERVICE_ACCOUNT")
if SERVICE_ACCOUNT_ENV:
    import tempfile

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
zone_ref = db.reference("ml_worker/zone_tracker")

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
    print("[ML Worker] Model loaded successfully")
except Exception as e:
    print(f"[ML Worker] WARNING: Could not load model — {e}")

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

_FALLBACKS = {
    "temp": 27.0,
    "ph": 7.5,
    "do": 7.0,
    "turb": 10.0,
    "wl": 12.0,
}
_DISABLED_FLAGS = {
    "temp": "tempDisabled",
    "ph": "phDisabled",
    "do": "doDisabled",
    "turb": "turbDisabled",
    "wl": "waterDisabled",
}
_SENSOR_VALUE_KEYS = {
    "temp": "temperature",
    "ph": "phLevel",
    "do": "dissolvedOxygen",
    "turb": "turbidity",
    "wl": "waterLevel",
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


# ── Zone Duration Tracking ────────────────────────────────────
class ZoneTracker:
    def __init__(self):
        self.entry_time = None
        self.accumulated_minutes = 0.0
        self._prev_in_bad = False

    def update(self, in_bad_zone):
        now = time.time()
        if in_bad_zone:
            if self.entry_time is None:
                self.entry_time = now
            self.accumulated_minutes = (now - self.entry_time) / 60.0
        else:
            self.accumulated_minutes = 0.0
            self.entry_time = None
        self._prev_in_bad = in_bad_zone
        return round(self.accumulated_minutes, 2)

    def is_transition(self, in_bad_zone):
        return in_bad_zone != self._prev_in_bad


zone_trackers = {k: ZoneTracker() for k in ["temp", "ph", "do", "turb", "wl"]}


def _persist_zone_state():
    if zone_ref is None:
        return
    zone_ref.set({k: zt.entry_time for k, zt in zone_trackers.items()})


def _restore_zone_state():
    global zone_trackers
    if zone_ref is None:
        return
    saved = zone_ref.get()
    if not saved:
        return
    for key, zt in zone_trackers.items():
        entry = saved.get(key)
        if entry and entry > 0:
            zt.entry_time = entry
            zt.accumulated_minutes = (time.time() - entry) / 60.0
            zt._prev_in_bad = True


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
    temp_mz,
    ph_mz,
    do_mz,
    turb_mz,
    wl_mz,
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
        "temp_minutes_in_zone": temp_mz,
        "ph_minutes_in_zone": ph_mz,
        "do_minutes_in_zone": do_mz,
        "turb_minutes_in_zone": turb_mz,
        "wl_minutes_in_zone": wl_mz,
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
    if overall_model is None:
        return "OPTIMAL", 0.5
    pred = overall_model.predict(X)[0]
    probs = overall_model.predict_proba(X)[0]
    try:
        status = encoders["health_status"].inverse_transform([pred])[0]
    except Exception:
        status = "OPTIMAL"
    return status, float(max(probs))


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


# ── Sensor Combination Detection ──────────────────────────────
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

    if temp_high and do_low:
        combos.append(
            {
                "sensors": ["Temperature", "Dissolved Oxygen"],
                "insight": (
                    f"Elevated temp ({round(temp, 1)}°C) + low DO ({round(do_, 1)} mg/L). "
                    f"Heat-oxygen cycle — warm water holds less oxygen. Your crayfish are "
                    f"experiencing heat stress and oxygen deprivation simultaneously."
                ),
                "prediction_note": (
                    "Rising temp will drop DO further. Both trends will worsen each other."
                ),
                "recommendation": (
                    "Cool the water first — this will naturally help DO recover. "
                    "Add shade or improve ventilation. Aerator is running but cannot fully "
                    "compensate. Partial water exchange with cooler water if temp persists."
                ),
            }
        )
    elif ph_low and do_low:
        combos.append(
            {
                "sensors": ["pH Level", "Dissolved Oxygen"],
                "insight": (
                    f"Acidic pH ({round(ph, 2)}) + low DO ({round(do_, 1)} mg/L). "
                    f"Acid reduces oxygen absorption — even if DO improves, crayfish "
                    f"may still struggle to absorb it."
                ),
                "prediction_note": (
                    "Restoring DO alone is not enough — pH must be corrected first."
                ),
                "recommendation": (
                    "Fix pH first. Apply buffer slowly, wait 15 min, re-test. "
                    "Aerator is running. Reduce feeding until resolved."
                ),
            }
        )
    elif turb_high and do_low:
        combos.append(
            {
                "sensors": ["Turbidity", "Dissolved Oxygen"],
                "insight": (
                    f"High turbidity ({round(turb, 1)} NTU) + low DO "
                    f"({round(do_, 1)} mg/L). Organic matter is consuming oxygen — "
                    f"the cloudier the water, the faster oxygen depletes."
                ),
                "prediction_note": (
                    "DO will keep dropping while turbidity stays high. "
                    "Clear the water first, DO will recover after."
                ),
                "recommendation": (
                    "Pump is running to filter the water. Check filter for clogs. "
                    "Partial water change if no improvement in 30 min. Reduce feeding."
                ),
            }
        )
    elif temp_high and turb_high:
        combos.append(
            {
                "sensors": ["Temperature", "Turbidity"],
                "insight": (
                    f"Elevated temp ({round(temp, 1)}°C) + high turbidity "
                    f"({round(turb, 1)} NTU). Warm, cloudy water promotes rapid "
                    f"bacterial growth — DO may crash soon."
                ),
                "prediction_note": (
                    "If both stay elevated, expect DO to reach critical within 1–2 hours."
                ),
                "recommendation": (
                    "Pump is running. Reduce heat exposure — add shade or ventilation. "
                    "Do not feed until both parameters normalize. Monitor DO closely."
                ),
            }
        )
    elif ph_low and turb_high:
        combos.append(
            {
                "sensors": ["pH Level", "Turbidity"],
                "insight": (
                    f"Acidic pH ({round(ph, 2)}) + high turbidity ({round(turb, 1)} NTU). "
                    f"Likely organic decomposition — rotting waste lowers pH and clouds water."
                ),
                "prediction_note": (
                    "Both will worsen if waste is not removed. DO may drop next."
                ),
                "recommendation": (
                    "Pump is running. Correct pH with buffer. Remove visible waste. "
                    "Check filter media and clean if needed."
                ),
            }
        )
    elif ph_high and do_low:
        combos.append(
            {
                "sensors": ["pH Level", "Dissolved Oxygen"],
                "insight": (
                    f"Alkaline pH ({round(ph, 2)}) + low DO ({round(do_, 1)} mg/L). "
                    f"Possible algae bloom — algae raise pH during day, consume O2 at night."
                ),
                "prediction_note": (
                    "DO will fluctuate with light cycle — higher by day, lower at night."
                ),
                "recommendation": (
                    "Aerator is running. Correct pH with buffer. "
                    "Check for algae, reduce light if present. Partial water change. "
                    "Monitor DO overnight."
                ),
            }
        )

    return combos


# ── Time Formatter ────────────────────────────────────────────
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


# ── Overall Text Generators ───────────────────────────────────
def generate_insight(
    overall_status,
    sensor_statuses,
    stage,
    ranges,
    temp,
    ph,
    do_,
    turb,
    wl,
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
):
    stage_label = STAGE_LABELS.get(stage, stage.replace("_", " ").title())

    values = {
        "Temperature": f"{temp:.2f}°C",
        "pH Level": f"{ph:.2f}",
        "Dissolved Oxygen": f"{do_:.2f} mg/L",
        "Turbidity": f"{turb:.2f} NTU",
        "Water Level": f"{wl:.2f} cm",
    }

    if overall_status == "OPTIMAL":
        return (
            f"All parameters are within safe range for your {stage_label} crayfish. "
            f"Tank conditions are good — keep up your current routine."
        )

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

    critical_sensors, warning_sensors = [], []
    sensor_map = [
        ("temp", "Temperature", "temp_status"),
        ("ph", "pH Level", "ph_status"),
        ("do", "Dissolved Oxygen", "do_status"),
        ("turb", "Turbidity", "turb_status"),
        ("wl", "Water Level", "wl_status"),
    ]

    for short, label, target in sensor_map:
        s = sensor_statuses.get(target, "OPTIMAL")
        if s == "CRITICAL":
            critical_sensors.append(label)
        elif s == "WARNING":
            warning_sensors.append(label)

    all_problems = critical_sensors + warning_sensors

    if len(critical_sensors) == 5:
        vals = "; ".join(f"{k}: {v}" for k, v in values.items())
        return (
            f"All parameters are critical. {vals}. "
            f"Immediate action required to prevent harm to your {stage_label} crayfish."
        )

    if overall_status == "WARNING":
        problem_str = ", ".join(all_problems) if all_problems else "some parameters"
        return (
            f"{problem_str} {'is' if len(all_problems) == 1 else 'are'} drifting "
            f"outside the safe range for {stage_label} crayfish. "
            f"Not critical yet — check soon."
        )

    crit_str = (
        ", ".join(critical_sensors) if critical_sensors else ", ".join(all_problems)
    )
    vals = "; ".join(f"{s}: {values[s]}" for s in critical_sensors)
    suffix = f" ({vals})" if vals else ""
    return (
        f"{crit_str} {'is' if len(critical_sensors) == 1 else 'are'} outside the "
        f"safe range for {stage_label} crayfish{suffix}. "
        f"Immediate attention needed."
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
    combo_note = combos[0]["prediction_note"] + " " if combos else ""

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
                direction = "dropping" if status == "WARNING" else "trending down"
                outcome = (
                    "a critically low level" if status == "WARNING" else "the minimum"
                )
                forecasts.append(f"{label} {direction} — may reach {outcome} in ~{t}.")
        elif rate > 0 and val < r_max:
            secs = ((r_max - val) / abs(rate)) * READING_INTERVAL_SEC
            if secs <= MAX_SEC:
                t = format_time(secs)
                direction = "rising" if status == "WARNING" else "trending up"
                outcome = (
                    "a critically high level" if status == "WARNING" else "the maximum"
                )
                forecasts.append(f"{label} {direction} — may reach {outcome} in ~{t}.")

    if not forecasts and not combo_note:
        if overall_status == "OPTIMAL":
            return (
                f"All parameters stable for your {stage_label} crayfish. "
                f"No concerning trends — conditions should remain good."
            )
        return (
            f"Issues detected with current water conditions. "
            f"Address flagged parameters to prevent further deterioration."
        )

    return combo_note + " ".join(forecasts)


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
        return "No action needed. Continue regular feeding and daily tank check."

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

    actions = []
    if sensor_statuses.get("turb_status") == "CRITICAL":
        actions.append(
            "Turbidity high — pump activated. Confirm it is running and filter is clear."
        )
    elif sensor_statuses.get("turb_status") == "WARNING":
        actions.append(
            "Turbidity rising. Pump will activate automatically — watch the filter."
        )
    if sensor_statuses.get("do_status") == "CRITICAL":
        actions.append("DO critically low — aerator on. Confirm it is running.")
    elif sensor_statuses.get("do_status") == "WARNING":
        actions.append("DO dropping. Aerator will activate — check airstone is clear.")
    if sensor_statuses.get("ph_status") == "CRITICAL":
        actions.append(
            "pH out of range. Correct with buffer — small amounts, wait 15 min, re-test."
        )
    elif sensor_statuses.get("ph_status") == "WARNING":
        actions.append("pH drifting. Prepare buffer in case it continues.")
    if sensor_statuses.get("temp_status") == "CRITICAL":
        actions.append(
            "Temp out of range. Check sunlight/heat sources. Adjust shade or ventilation."
        )
    elif sensor_statuses.get("temp_status") == "WARNING":
        actions.append("Temp drifting. Check environmental factors near tank.")
    if sensor_statuses.get("wl_status") == "CRITICAL":
        actions.append("Water level out of range. Check for leaks. Adjust slowly.")
    elif sensor_statuses.get("wl_status") == "WARNING":
        actions.append("Water level slightly off. Top up or drain if needed.")

    base = " ".join(actions) if actions else "Inspect the tank manually."
    return f"Action needed: {base}" if overall_status == "CRITICAL" else base


# ── Per-Sensor Text Generators ────────────────────────────────
def generate_sensor_insight(short, val, status, r_min, r_max):
    label = SHORT_TO_LABEL[short]
    unit = SHORT_TO_UNIT[short]
    val_str = f"{val:.2f}{unit}"
    context = {
        "temp": {
            "OPTIMAL": "Temperature directly affects crayfish metabolism and molting.",
            "WARNING": "Crayfish become lethargic and feed poorly outside their temperature range.",
            "CRITICAL": "Extreme temperatures cause severe physiological stress and can be fatal.",
        },
        "ph": {
            "OPTIMAL": "Stable pH keeps crayfish shells strong and gill function healthy.",
            "WARNING": "pH drift affects the ability of crayfish to regulate body chemistry.",
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
            "CRITICAL": "High turbidity clogs gills, reduces oxygen, and indicates poor water quality.",
        },
        "wl": {
            "OPTIMAL": "Stable water level maintains proper tank conditions.",
            "WARNING": "Water level drift may affect aeration coverage and tank stability.",
            "CRITICAL": "Extreme water level changes stress crayfish and disrupt tank equipment.",
        },
    }
    ctx = context.get(short, {}).get(status, "")
    if status == "OPTIMAL":
        return f"{label} is at {val_str}, right within the safe range ({r_min:.2f}–{r_max:.2f}{unit}). {ctx}"
    elif status == "WARNING":
        return f"{label} is at {val_str} and moving outside the safe range ({r_min:.2f}–{r_max:.2f}{unit}). {ctx}"
    return f"{label} is at {val_str}, outside the safe range ({r_min:.2f}–{r_max:.2f}{unit}). {ctx}"


def generate_sensor_prediction(short, val, rate, r_min, r_max, status, confidence):
    label = SHORT_TO_LABEL[short]
    conf_pct = int(confidence * 100)
    if status == "CRITICAL":
        return f"CrayAI is {conf_pct}% confident that {label} is critically out of range and requires immediate attention."
    if rate == 0:
        return f"CrayAI is {conf_pct}% confident that {label} is currently {status.lower()} with no significant trend detected."
    MAX_SEC = 5 * 3600
    if rate < 0 and val > r_min:
        secs = ((val - r_min) / abs(rate)) * READING_INTERVAL_SEC
        if secs <= MAX_SEC:
            t = format_time(secs)
            boundary = (
                "a critically low level"
                if status == "WARNING"
                else "the minimum threshold"
            )
            return (
                f"CrayAI is {conf_pct}% confident that {label} is trending downward. "
                f"At the current rate, it may reach {boundary} in about {t}."
            )
    elif rate > 0 and val < r_max:
        secs = ((r_max - val) / abs(rate)) * READING_INTERVAL_SEC
        if secs <= MAX_SEC:
            t = format_time(secs)
            boundary = (
                "a critically high level"
                if status == "WARNING"
                else "the maximum threshold"
            )
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
        return "This parameter is within the safe range \u2014 no action needed."
    recs = {
        "do": {
            "WARNING": (
                "Dissolved oxygen is getting low. The aerator will activate automatically. "
                "Make sure the airstone or diffuser is not blocked."
            ),
            "CRITICAL": (
                "Dissolved oxygen is critically low \u2014 the aerator should already be running. "
                "Verify it is working. If DO keeps dropping, manually increase aeration "
                "or reduce stocking density temporarily."
            ),
        },
        "turb": {
            "WARNING": (
                "Water is getting cloudy. The RAS water pump will activate automatically. "
                "Check the filter media \u2014 it may need rinsing soon."
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
                "pH is out of the safe range. Adjust manually with a pH buffer \u2014 "
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
                "tank \u2014 direct sunlight, fans, or heaters may be the cause. "
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
                "or overflow. Adjust slowly \u2014 sudden changes stress the crayfish."
            ),
        },
    }
    return recs.get(short, {}).get(status, "Inspect this parameter manually.")


def get_current_stage_ranges():
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


def on_sensor_change(event):
    try:
        data = event.data
        if not data:
            return

        resolved = {}
        disabled_sensors = set()

        for key in ["temp", "ph", "do", "turb", "wl"]:
            raw = data.get(_SENSOR_VALUE_KEYS[key])
            disabled = data.get(_DISABLED_FLAGS[key], False)
            fallback = _FALLBACKS[key]

            if key == "turb" and data.get("turbidityAir", False):
                disabled = True

            if disabled or raw is None or (isinstance(raw, (int, float)) and raw < 0):
                resolved[key] = fallback
                disabled_sensors.add(key)
            else:
                resolved[key] = float(raw)

        temp = resolved["temp"]
        ph = resolved["ph"]
        do_ = resolved["do"]
        turb = resolved["turb"]
        wl = resolved["wl"]

        for k, v in [
            ("temp", temp),
            ("ph", ph),
            ("do", do_),
            ("turb", turb),
            ("wl", wl),
        ]:
            if k not in disabled_sensors:
                histories[k].add(v)

        temp_rate = histories["temp"].get_rate()
        ph_rate = histories["ph"].get_rate()
        do_rate = histories["do"].get_rate()
        turb_rate = histories["turb"].get_rate()
        wl_rate = histories["wl"].get_rate()

        stage, ranges = get_current_stage_ranges()
        t_min, t_max = ranges["temp"]["min"], ranges["temp"]["max"]
        p_min, p_max = ranges["ph"]["min"], ranges["ph"]["max"]
        d_min, d_max = ranges["do"]["min"], ranges["do"]["max"]
        tr_min, tr_max = ranges["turb"]["min"], ranges["turb"]["max"]
        wl_min, wl_max = ranges["waterlevel"]["min"], ranges["waterlevel"]["max"]

        temp_mz = zone_trackers["temp"].update(
            get_sensor_status(temp, t_min, t_max) != "OPTIMAL"
        )
        ph_mz = zone_trackers["ph"].update(
            get_sensor_status(ph, p_min, p_max) != "OPTIMAL"
        )
        do_mz = zone_trackers["do"].update(
            get_sensor_status(do_, d_min, d_max) != "OPTIMAL"
        )
        turb_mz = zone_trackers["turb"].update(
            get_sensor_status(turb, tr_min, tr_max) != "OPTIMAL"
        )
        wl_mz = zone_trackers["wl"].update(
            get_sensor_status(wl, wl_min, wl_max) != "OPTIMAL"
        )

        _persist_zone_state()

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
            temp_mz,
            ph_mz,
            do_mz,
            turb_mz,
            wl_mz,
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

        sensor_statuses = {
            "temp_status": get_sensor_status(temp, t_min, t_max),
            "ph_status": get_sensor_status(ph, p_min, p_max),
            "do_status": get_sensor_status(do_, d_min, d_max),
            "turb_status": get_sensor_status(turb, tr_min, tr_max),
            "wl_status": get_sensor_status(wl, wl_min, wl_max),
        }

        sensors_meta = [
            ("temp", temp, temp_rate, t_min, t_max),
            ("ph", ph, ph_rate, p_min, p_max),
            ("do", do_, do_rate, d_min, d_max),
            ("turb", turb, turb_rate, tr_min, tr_max),
            ("wl", wl, wl_rate, wl_min, wl_max),
        ]
        sensor_insights = {}
        sensor_predictions = {}
        sensor_recommendations = {}
        for short, val, rate, r_min, r_max in sensors_meta:
            st = sensor_statuses[f"{short}_status"]
            sensor_insights[short] = generate_sensor_insight(
                short, val, st, r_min, r_max
            )
            sensor_predictions[short] = generate_sensor_prediction(
                short, val, rate, r_min, r_max, st, confidence
            )
            sensor_recommendations[short] = generate_sensor_recommendation(short, st)

        result = {
            "predictedStatus": overall_status,
            "confidence": confidence,
            "stage": stage,
            "sensorStatuses": sensor_statuses,
            "sensorInsights": sensor_insights,
            "sensorPredictions": sensor_predictions,
            "sensorRecommendations": sensor_recommendations,
            "insight": generate_insight(
                overall_status,
                sensor_statuses,
                stage,
                ranges,
                temp,
                ph,
                do_,
                turb,
                wl,
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

        conf_pct = int(confidence * 100)
        print(f"[ML Worker] Stage={stage} Overall={overall_status} ({conf_pct}%)")

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
        print(f"[ML Worker] Listener error: {e}")
        import traceback

        traceback.print_exc()


_restore_zone_state()

print("[ML Worker] Listening to sensor_readings/latest ...")
latest_ref.listen(on_sensor_change)

test_ref = db.reference("test_tools")
print("[ML Worker] Also listening to test_tools ...")
test_ref.listen(on_sensor_change)

while True:
    time.sleep(1)
