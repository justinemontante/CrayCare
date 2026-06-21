"""
CrayCare ML Worker - v3.0
=========================
Listens to Firebase sensor_readings/latest, fetches user-defined thresholds,
computes ratio features, runs ensemble models, generates stage-aware
insight/prediction/recommendation texts, and writes to ml_predictions/latest.
"""

import sys, os, time

sys.path.insert(0, os.path.dirname(__file__))

import firebase_admin
from firebase_admin import db, credentials
import pandas as pd
import joblib

# ── Firebase init ──────────────────────────────────────────────────────────────
SERVICE_ACCOUNT_ENV = os.environ.get("FIREBASE_SERVICE_ACCOUNT")
if SERVICE_ACCOUNT_ENV:
    import json, tempfile
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json", mode="w")
    tmp.write(SERVICE_ACCOUNT_ENV)
    tmp.close()
    cred = credentials.Certificate(tmp.name)
    print("[ML Worker] Loaded credentials from environment variable.")
else:
    SA_PATH = os.path.join(os.path.dirname(__file__), "..", "notification_worker", "serviceAccountKey.json")
    cred = credentials.Certificate(SA_PATH)
    print("[ML Worker] Loaded credentials from serviceAccountKey.json.")

firebase_admin.initialize_app(cred, {
    "databaseURL": "https://craycare-8436c-default-rtdb.asia-southeast1.firebasedatabase.app"
})

latest_ref     = db.reference("sensor_readings/latest")
config_ref     = db.reference("sensor_readings/config")
prediction_ref = db.reference("ml_predictions/latest")

# ── Load models ────────────────────────────────────────────────────────────────
MODELS_DIR  = os.path.join(os.path.dirname(__file__), "models")
SENSOR_KEYS = ["temp", "ph", "do", "turb", "wl"]

models = {}
for key in SENSOR_KEYS:
    path = os.path.join(MODELS_DIR, f"craycare_{key}_model.pkl")
    if os.path.exists(path):
        models[key] = joblib.load(path)
        print(f"[ML Worker] Loaded {key} model")
    else:
        models[key] = None
        print(f"[ML Worker] WARNING: {key} model not found")

status_path = os.path.join(MODELS_DIR, "craycare_status_model.pkl")
status_model = joblib.load(status_path) if os.path.exists(status_path) else None
print("[ML Worker] Loaded overall status model" if status_model else "[ML Worker] WARNING: status model not found")

# ── Sensor metadata ────────────────────────────────────────────────────────────
SENSOR_CONFIGS = [
    {"key": "temperature",    "name": "temp",      "label": "Temperature",      "unit": "°C"},
    {"key": "phLevel",        "name": "ph",        "label": "pH Level",         "unit": ""},
    {"key": "dissolvedOxygen","name": "do",        "label": "Dissolved Oxygen", "unit": "mg/L"},
    {"key": "turbidity",      "name": "turb",      "label": "Turbidity",        "unit": "NTU"},
    {"key": "waterLevel",     "name": "wl",        "label": "Water Level",      "unit": "cm"},
]

FEATURE_ORDER = [
    "temperature","phLevel","dissolvedOxygen","turbidity","waterLevel",
    "temp_rate","ph_rate","do_rate","turb_rate","wl_rate",
    "temp_min","temp_max","ph_min","ph_max","do_min","turb_max","wl_min","wl_max",
    "temp_ratio","ph_ratio","do_ratio","turb_ratio","wl_ratio",
]

# ── Stage-aware context strings ────────────────────────────────────────────────
STAGE_CONTEXT = {
    "early_juvenile": {
        "temp": "Early Juveniles need a very stable, warm temp (26–28°C) for rapid shell formation and first molts.",
        "ph":   "Newly stocked early juveniles are extremely sensitive to pH. Keep strictly between 7.5–8.0.",
        "do":   "Early juveniles require high dissolved oxygen (>=5.0 mg/L) — their small gills are less efficient.",
        "turb": "Crystal-clear water (<=25 NTU) is critical so juveniles can locate food and avoid predator stress.",
        "wl":   "Maintain water level 120–160 cm. Sudden drops expose juveniles and cause mass mortality.",
    },
    "advanced_juvenile": {
        "temp": "Advanced juveniles thrive at 25–30°C. Consistent temperature promotes steady growth and molting.",
        "ph":   "pH 7.0–8.5 supports shell calcium uptake and enzyme activity for active growth phase.",
        "do":   "Dissolved oxygen must stay above 5.0 mg/L to sustain the elevated metabolic rate of this growth stage.",
        "turb": "Keep turbidity below 30 NTU. Sediment build-up irritates gills and slows growth.",
        "wl":   "Water level 120–170 cm gives advanced juveniles room to swim and reduces territorial stress.",
    },
    "pre_adult": {
        "temp": "Pre-adults grow best at 24–30°C. Stable temperature maximises feed conversion and weight gain.",
        "ph":   "pH 7.0–8.5 is the safe window. Deviations reduce immune response during the final growth push.",
        "do":   "Minimum DO of 4.5 mg/L is required. Below this, feeding ceases and growth reverses.",
        "turb": "Turbidity limit 35 NTU. Higher values damage gill tissue and increase disease susceptibility.",
        "wl":   "Water level 130–180 cm. Pre-adults begin burrowing — sufficient depth is necessary.",
    },
    "market_size": {
        "temp": "Market-size crayfish need 24–28°C. High temp accelerates metabolism and reduces harvest weight.",
        "ph":   "Strict pH 7.0–8.0 for market-size animals ensures shell integrity and meat quality at harvest.",
        "do":   "DO >= 4.0 mg/L minimum. Hypoxia causes stress-blackening and reduces market value.",
        "turb": "Maximum turbidity 40 NTU. Turbid water stresses mature animals and taints meat flavour.",
        "wl":   "Maintain 130–180 cm depth. Market-size crayfish need stable depth for burrowing and pre-harvest conditioning.",
    },
}

STAGE_LABEL_MAP = {
    "early_juvenile":    "Early Juvenile",
    "advanced_juvenile": "Advanced Juvenile",
    "pre_adult":         "Pre-Adult",
    "market_size":       "Market Size",
}

# ── Rolling history for rate-of-change ────────────────────────────────────────
class SensorHistory:
    def __init__(self, max_len=5):
        self.history = []
        self.max_len = max_len

    def add(self, value):
        self.history.append(value)
        if len(self.history) > self.max_len:
            self.history.pop(0)

    def get_rate(self):
        if len(self.history) < 2:
            return 0.0
        return (self.history[-1] - self.history[0]) / (len(self.history) - 1)


histories = {k: SensorHistory() for k in ["temp", "ph", "do", "turb", "wl"]}

# ── Helpers ────────────────────────────────────────────────────────────────────
def compute_ratio(val, vmin, vmax):
    span = vmax - vmin
    return (val - vmin) / span if span > 0 else 0.5

def get_current_stage_ranges():
    config = config_ref.get() or {}
    stage  = config.get("selectedStage") or "pre_adult"
    stage_config = config.get(stage, {})

    defaults = {
        "temp":     {"min": 24.0, "max": 30.0},
        "ph":       {"min": 7.0,  "max": 8.5},
        "do":       {"min": 4.5,  "max": 999.0},
        "turb":     {"min": 0.0,  "max": 35.0},
        "waterlevel":{"min":130.0, "max": 180.0},
    }

    ranges = {}
    for key in ["temp", "ph", "do", "turb", "waterlevel"]:
        sr = stage_config.get(key, {}) if isinstance(stage_config, dict) else {}
        if not sr:
            sr = config.get("ranges", {}).get(key, {})
        if not sr:
            sr = defaults[key]
        d = defaults[key]
        ranges[key] = {
            "min": float(sr["min"]) if sr.get("min") is not None else d["min"],
            "max": float(sr["max"]) if sr.get("max") is not None else d["max"],
        }
    return stage, ranges

# ── Stage-aware insight generator ─────────────────────────────────────────────
def generate_insight(label, val, unit, status, rate, r_min, r_max,
                     stage, sensor_key, ratio):
    u    = unit if unit else ""
    sign = "+" if rate >= 0 else ""
    ctx  = STAGE_CONTEXT.get(stage, {}).get(sensor_key, "")
    sl   = STAGE_LABEL_MAP.get(stage, stage.replace("_", " ").title())
    is_bounded = r_max < 999.0
    max_disp   = f"{r_max}{u}" if is_bounded else "∞"

    # ── Absolute Biological Override ──────────────────────────────────────────
    # Prevents "OPTIMAL" status if user puts extreme out-of-standard inputs.
    absolute_critical = False
    override_msg = ""
    if sensor_key == "do" and val < 3.0:
        absolute_critical, override_msg = True, "BIOLOGICAL HAZARD: DO < 3.0 mg/L is lethal to crayfish regardless of custom settings!"
    elif sensor_key == "temp" and (val < 15.0 or val > 35.0):
        absolute_critical, override_msg = True, "BIOLOGICAL HAZARD: Temperature outside 15-35°C is highly lethal to crayfish!"
    elif sensor_key == "ph" and (val < 5.5 or val > 9.5):
        absolute_critical, override_msg = True, "BIOLOGICAL HAZARD: pH level is chemically burning the crayfish gills!"
    elif sensor_key == "wl" and val < 50.0:
        absolute_critical, override_msg = True, "BIOLOGICAL HAZARD: Water level is dangerously shallow. Risk of overheating and predation!"

    if absolute_critical:
        status = "CRITICAL"

    # ── Hardware / Physical Recommendations Logic ─────────────────────────────
    hardware_rec = ""
    if status != "OPTIMAL":
        if sensor_key == "do" and (val < r_min or absolute_critical):
            hardware_rec = "⚙️ AUTOMATION: Ensure both automated aerators are running. Physical Check: Clean clogged air stones."
        elif sensor_key == "turb":
            hardware_rec = "⚙️ AUTOMATION: Automated water pump should cycle water. Physical Check: Inspect filtration system and clean filter media."
        elif sensor_key == "temp" and (val > r_max or val > 35.0):
            hardware_rec = "Physical Check: Check if tank covers/shade nets are missing ('walang tabon'). Block direct sunlight."
        elif sensor_key == "temp" and (val < r_min or val < 15.0):
            hardware_rec = "Physical Check: Ensure tank is protected from cold drafts. Use covers at night to retain heat."
        elif sensor_key == "wl" and (val < r_min or val < 50.0):
            hardware_rec = "Physical Check: URGENT! Inspect tank and plumbing for leaks ('baka may butas'). Check automated refill."
        elif sensor_key == "wl" and val > r_max:
            hardware_rec = "Physical Check: Verify if overflow pipes are clogged."
        elif sensor_key == "ph":
            hardware_rec = "Physical Check: Add agricultural lime for low pH, or perform partial water change for high pH."

    # ── CRITICAL ──────────────────────────────────────────────────────────────
    if status == "CRITICAL":
        if absolute_critical:
            insight        = f"⚠️ {override_msg} Current {label}: {val}{u}."
            prediction     = ("Crayfish are in a biologically lethal environment. Mass mortality imminent!")
            recommendation = f"EMERGENCY ACTION REQUIRED IMMEDIATELY! {hardware_rec}"
        elif val < r_min:
            diff = round(r_min - val, 2)
            insight        = (f"{label} is CRITICALLY LOW at {val}{u} — "
                              f"{diff}{u} below the minimum threshold of {r_min}{u} "
                              f"for {sl} stage.")
            prediction     = ("Crayfish are experiencing acute physiological stress. "
                              "Mortality risk increases significantly if this persists beyond 30 minutes.")
            recommendation = (f"URGENT: Increase {label.lower()} immediately. "
                              f"{hardware_rec} {ctx}")
        else:
            diff = round(val - r_max, 2)
            insight        = (f"{label} is CRITICALLY HIGH at {val}{u} — "
                              f"{diff}{u} above the maximum threshold of {max_disp} "
                              f"for {sl} stage.")
            prediction     = ("Prolonged exposure will cause physiological damage. "
                              "Crayfish may exhibit erratic behaviour or surface for air.")
            recommendation = (f"URGENT: Reduce {label.lower()} immediately. "
                              f"{hardware_rec} {ctx}")

    # ── WARNING ───────────────────────────────────────────────────────────────
    elif status == "WARNING":
        span       = (r_max - r_min) if is_bounded else r_min
        range_mid  = (r_min + r_max) / 2 if is_bounded else r_min * 1.5
        heading    = "lower" if val < range_mid else "upper"
        near_limit = r_min if val < range_mid else r_max

        rdgs_to_critical = None
        if abs(rate) > 0.001:
            gap = abs(val - near_limit)
            rdgs_to_critical = int(gap / abs(rate)) if abs(rate) > 0 else None

        eta_str = (f" At the current rate ({sign}{rate:.3f}{u}/reading), "
                   f"it will reach the {heading} limit in ~{rdgs_to_critical} readings."
                   if rdgs_to_critical and rdgs_to_critical < 30 else "")

        insight        = (f"{label} is in the WARNING zone at {val}{u} "
                          f"(approaching the {heading} limit of {near_limit}{u} "
                          f"for {sl} stage).{eta_str}")
        prediction     = (f"Trend: {sign}{rate:.3f}{u}/reading. "
                          f"Condition will deteriorate to CRITICAL if uncorrected. {ctx}")
        recommendation = (f"Monitor closely. {hardware_rec} "
                          f"Adjust toward safe midpoint ({round((r_min + r_max)/2, 1)}{u}).")

    # ── OPTIMAL ───────────────────────────────────────────────────────────────
    else:
        pct = round(ratio * 100, 1)
        insight        = (f"{label} is OPTIMAL at {val}{u} "
                          f"(ideal range for {sl}: {r_min}{u} – {max_disp}, "
                          f"currently at {pct}% of range).")
        trend_desc     = ("stable" if abs(rate) < 0.01
                          else ("slowly rising" if rate > 0 else "slowly falling"))
        prediction     = (f"Condition is {trend_desc} ({sign}{rate:.3f}{u}/reading). "
                          f"No immediate risk. {ctx}")
        recommendation = "No action needed. Continue regular monitoring and maintenance."

    # ── Override predictions for rapid-rate special cases ─────────────────────
    if sensor_key == "do" and rate < -0.08:
        prediction     = (f"⚠️ RAPID DO DROP detected ({rate:.3f} mg/L/reading). "
                           f"At this rate, DO will reach critical levels soon!")
        recommendation = "Activate aerator / oxygen support IMMEDIATELY."

    elif sensor_key == "turb" and rate > 1.0:
        prediction     = (f"⚠️ TURBIDITY RISING FAST (+{rate:.2f} NTU/reading). "
                           f"Filtration system may be failing or sediment is disturbed.")
        recommendation = "Turn on recirculation pump and check filter media."

    elif sensor_key == "wl" and rate < -0.8:
        prediction     = (f"⚠️ WATER LEVEL DROPPING FAST ({rate:.2f} cm/reading). "
                           f"Possible leak or evaporation event.")
        recommendation = ("Refill tank immediately. Do NOT run water pump if "
                           "water level is too low — this will burn the motor.")

    return insight, prediction, recommendation


# ── Main sensor event handler ──────────────────────────────────────────────────
def on_sensor_change(event):
    data = event.data
    if not data:
        return

    temp = data.get("temperature")
    ph   = data.get("phLevel")
    d_o  = data.get("dissolvedOxygen")
    turb = data.get("turbidity")
    wl   = data.get("waterLevel")

    if any(v is None for v in [temp, ph, d_o, turb, wl]):
        print("[ML Worker] Incomplete sensor data — skipping.")
        return

    # Update histories
    histories["temp"].add(temp)
    histories["ph"].add(ph)
    histories["do"].add(d_o)
    histories["turb"].add(turb)
    histories["wl"].add(wl)

    temp_rate = histories["temp"].get_rate()
    ph_rate   = histories["ph"].get_rate()
    do_rate   = histories["do"].get_rate()
    turb_rate = histories["turb"].get_rate()
    wl_rate   = histories["wl"].get_rate()

    stage, ranges = get_current_stage_ranges()

    t_min, t_max = ranges["temp"]["min"],      ranges["temp"]["max"]
    p_min, p_max = ranges["ph"]["min"],        ranges["ph"]["max"]
    do_min       = ranges["do"]["min"]
    turb_max     = ranges["turb"]["max"]
    wl_min, wl_max = ranges["waterlevel"]["min"], ranges["waterlevel"]["max"]

    # Compute ratios
    temp_ratio = compute_ratio(temp, t_min,  t_max)
    ph_ratio   = compute_ratio(ph,   p_min,  p_max)
    do_ratio   = (d_o - do_min) / max(do_min, 0.1)      # one-sided (more = better)
    turb_ratio = turb / max(turb_max, 0.1)              # one-sided (less = better)
    wl_ratio   = compute_ratio(wl,  wl_min, wl_max)

    features = {
        "temperature":     float(temp),
        "phLevel":         float(ph),
        "dissolvedOxygen": float(d_o),
        "turbidity":       float(turb),
        "waterLevel":      float(wl),
        "temp_rate":       float(temp_rate),
        "ph_rate":         float(ph_rate),
        "do_rate":         float(do_rate),
        "turb_rate":       float(turb_rate),
        "wl_rate":         float(wl_rate),
        "temp_min":        t_min, "temp_max": t_max,
        "ph_min":          p_min, "ph_max":   p_max,
        "do_min":          do_min,
        "turb_max":        turb_max,
        "wl_min":          wl_min, "wl_max":  wl_max,
        "temp_ratio":      float(temp_ratio),
        "ph_ratio":        float(ph_ratio),
        "do_ratio":        float(do_ratio),
        "turb_ratio":      float(turb_ratio),
        "wl_ratio":        float(wl_ratio),
    }

    X = pd.DataFrame([features])[FEATURE_ORDER]

    rate_map = {
        "temperature":     (temp_rate, "temp"),
        "phLevel":         (ph_rate,   "ph"),
        "dissolvedOxygen": (do_rate,   "do"),
        "turbidity":       (turb_rate, "turb"),
        "waterLevel":      (wl_rate,   "wl"),
    }
    ratio_map = {
        "temperature":     temp_ratio,
        "phLevel":         ph_ratio,
        "dissolvedOxygen": do_ratio,
        "turbidity":       turb_ratio,
        "waterLevel":      wl_ratio,
    }
    fb_name_map = {
        "temperature":     "temp",
        "phLevel":         "ph",
        "dissolvedOxygen": "do",
        "turbidity":       "turb",
        "waterLevel":      "waterlevel",
    }

    sensors_list = []

    for cfg in SENSOR_CONFIGS:
        key        = cfg["key"]
        name       = cfg["name"]
        label      = cfg["label"]
        unit       = cfg["unit"]
        val        = float(features[key])
        fn_name    = fb_name_map[key]
        r_min      = ranges[fn_name]["min"]
        r_max      = ranges[fn_name]["max"]
        rate, _    = rate_map[key]
        ratio      = ratio_map[key]

        model = models.get(name)
        if model is not None:
            sensor_status = str(model.predict(X)[0])
            proba         = model.predict_proba(X)[0]
            confidence    = round(float(max(proba)), 3)
        else:
            # Fallback to rule-based if model missing
            if ratio < 0 or ratio > 1:
                sensor_status = "CRITICAL"
            elif ratio < 0.12 or ratio > 0.88:
                sensor_status = "WARNING"
            else:
                sensor_status = "OPTIMAL"
            confidence = 1.0

        insight, prediction, recommendation = generate_insight(
            label=label, val=round(val, 2), unit=unit,
            status=sensor_status, rate=rate,
            r_min=r_min, r_max=r_max,
            stage=stage, sensor_key=name, ratio=ratio,
        )

        sensors_list.append({
            "key":            key,
            "label":          label,
            "status":         sensor_status,
            "confidence":     confidence,
            "insight":        insight,
            "prediction":     prediction,
            "recommendation": recommendation,
        })

    # ── Overall status ─────────────────────────────────────────────────────────
    if status_model is not None:
        overall_pred = str(status_model.predict(X)[0])
        proba_ov     = status_model.predict_proba(X)[0]
        ov_conf      = round(float(max(proba_ov)), 3)
    else:
        order = {"OPTIMAL": 0, "WARNING": 1, "CRITICAL": 2}
        overall_pred = max([s["status"] for s in sensors_list], key=lambda s: order[s])
        ov_conf      = 1.0

    non_optimal = [s for s in sensors_list if s["status"] != "OPTIMAL"]
    if non_optimal:
        insight_text = " | ".join(s["insight"] for s in non_optimal)
        rec_text     = " | ".join(s["recommendation"] for s in non_optimal)
    else:
        insight_text = ("All water quality parameters are within optimal ranges "
                        f"for the {STAGE_LABEL_MAP.get(stage, stage)} stage. "
                        "The aquaculture system is healthy.")
        rec_text     = "Continue regular monitoring and scheduled maintenance."

    result = {
        "predictedStatus": overall_pred,
        "confidence":      ov_conf,
        "stage":           stage,
        "sensors":         sensors_list,
        "insight":         insight_text,
        "prediction":      (f"CrayAI predicts a {overall_pred} overall status "
                            f"({int(ov_conf * 100)}% confidence) based on "
                            f"current {STAGE_LABEL_MAP.get(stage, stage)}-stage "
                            f"thresholds and sensor trend data."),
        "recommendation":  rec_text,
        "timestamp":       int(time.time() * 1000),
    }

    print(f"[{time.strftime('%H:%M:%S')}] Stage={stage} | Overall={overall_pred} ({int(ov_conf*100)}%)")
    for s in sensors_list:
        print(f"  {s['label']:20s}: {s['status']:8s} ({int(s['confidence']*100)}%)")

    prediction_ref.set(result)


print("[ML Worker] Listening to sensor_readings/latest ...")
latest_ref.listen(on_sensor_change)

while True:
    time.sleep(1)
