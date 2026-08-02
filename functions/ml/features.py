"""Shared feature engineering, scoring, and constants for the CrayCare Water Quality Classification pipeline.

All threshold values are aligned with official agency standards:
  - DENR DAO 2016-08  (Class C Inland Waters — Fishery Water Supply)
  - DA-BFAR           (Philippine Freshwater Aquaculture Water Quality)
  - FAO TP-458        (Water Quality for Pond Aquaculture)
  - Boyd & Tucker (1998); Holdich (2002)

See agency_standards.py for full citations and threshold rationale.

METHODOLOGY NOTE (for thesis/defense):
The ML training label is derived from the deterministic `compute_wqc_score()` formula —
it is NOT independent, expert-labeled ground truth.
The Water Quality Classification model approximates/generalises this formula using richer
temporal features (rolling trend, volatility, hours-in-bad-condition) than the formula itself uses.
High classification accuracy primarily demonstrates that the model can closely reproduce a known
deterministic function. Frame the ML component as "trend-aware early warning / smoothing over the
rule-based system." See train_model.py Stage 1.5 for ablation numbers to cite in the defense.
"""

SENSORS = ["temp", "pH", "DO", "turbidity", "waterLevel"]

# ── Agency-calibrated thresholds ────────────────────────────────────────────────
# Source: DENR DAO 2016-08 Class C; DA-BFAR; FAO TP-458; HOLDICH 2002

# Dissolved Oxygen — DENR Class C: ≥5 mg/L; DA-BFAR: ≥5 mg/L (min 4 mg/L)
DO_OPTIMAL_MIN  = 5.0   # mg/L — DENR/DA-BFAR standard
DO_WARN_MIN     = 4.0   # mg/L — DA-BFAR minimum; below = moderate risk
DO_POOR_MIN     = 3.0   # mg/L — Boyd & Tucker: sub-lethal stress
DO_CRIT_MIN     = 2.0   # mg/L — FAO/Holdich: acute hypoxia threshold

# pH — DENR Class C: 6.5–8.5; DA-BFAR: 6.5–9.0; FAO crayfish optimal: 7.0–8.0
PH_OPTIMAL_MIN  = 7.0
PH_OPTIMAL_MAX  = 8.0
PH_GOOD_MIN     = 6.5   # DENR lower bound
PH_GOOD_MAX     = 8.5   # DENR upper bound
PH_FAIR_MIN     = 6.0   # DA-BFAR extended lower
PH_FAIR_MAX     = 9.0   # DA-BFAR extended upper
PH_CRIT_MIN     = 5.5   # Holdich: acute injury
PH_CRIT_MAX     = 9.5   # Holdich: acute injury

# Temperature — DA-BFAR: 20–30°C; FAO/Holdich crayfish optimal: 24–28°C
TEMP_OPTIMAL_MIN = 24.0  # °C
TEMP_OPTIMAL_MAX = 28.0  # °C
TEMP_GOOD_MIN    = 20.0  # DA-BFAR minimum
TEMP_GOOD_MAX    = 30.0  # DA-BFAR maximum
TEMP_CRIT_MIN    = 15.0  # °C — Holdich: torpor / lethal zone
TEMP_CRIT_MAX    = 35.0  # °C — Holdich: lethal zone

# Turbidity — DENR Class C: ≤50 NTU; FAO good pond: <25 NTU
TURB_OPTIMAL_MAX = 10.0  # NTU — FAO clear pond water
TURB_GOOD_MAX    = 25.0  # NTU — Boyd & Tucker acceptable
TURB_FAIR_MAX    = 50.0  # NTU — DENR Class C limit
TURB_CRIT_MAX    = 100.0 # NTU — extreme; severe oxygen demand

# Water level (%) — matches the ESP32 percentage payload and Firestore threshold.
WATER_MIN_PERCENT = 70.0
WATER_MAX_PERCENT = 100.0

# ── Normalisation reference ──────────────────────────────────────────────────────
# p96 of the raw rolling hazard on the 90-day dataset → balanced class split.
# Recompute if thresholds change: run compute_wqc_score() on the new dataset
# and take np.percentile(hazard_raw / p96 * 100, 96).
WQC_NORM_REF = 28.50

CLASS_NAMES = ["Low", "Moderate", "High", "Critical"]


# ── Feature engineering ──────────────────────────────────────────────────────────
def build_features(df):
    """Build 43 engineered features from raw sensor DataFrame.

    Expects columns: {sensor}_avg, {sensor}_min, {sensor}_max
    for each sensor in SENSORS (["temp","pH","DO","turbidity","waterLevel"]).

    Returns (feat_df, SENSORS).

    Feature groups:
      - Raw avg/min/max per sensor                   (15 cols)
      - Volatility (max-min) per sensor              ( 5 cols)
      - 6-hour rolling mean per sensor               ( 5 cols)
      - 24-hour rolling mean per sensor              ( 5 cols)
      - Short-term trend (6-tick slope) per sensor   ( 5 cols)
      - Hours-in-bad-condition counts                ( 4 cols)
      - Continuous per-sensor hazard, 6h rolling     ( 5 cols)
      - Total combined hazard, 6h rolling            ( 1 col)
      ──────────────────────────────────────────────────────────
      Total                                          (45 cols)
    """
    import numpy as np
    import pandas as pd

    base_cols = [f"{s}_{stat}" for s in SENSORS for stat in ("avg", "min", "max")]
    feat = df[base_cols].copy()

    for s in SENSORS:
        a = df[f"{s}_avg"]
        feat[f"{s}_volatility"] = df[f"{s}_max"] - df[f"{s}_min"]
        feat[f"{s}_roll6h"]     = a.rolling(36,  min_periods=1).mean()
        feat[f"{s}_roll24h"]    = a.rolling(144, min_periods=1).mean()
        feat[f"{s}_trend"]      = a.diff().rolling(6, min_periods=1).mean()

    # ── Hours-in-bad-condition (count of 10-min ticks / 6 = hours) ────────────
    feat["DO_hrs_low"]       = (df["DO_min"] < DO_OPTIMAL_MIN).rolling(36, min_periods=1).sum() / 6.0
    feat["temp_hrs_hi"]      = (df["temp_max"] > TEMP_GOOD_MAX).rolling(36, min_periods=1).sum() / 6.0
    feat["pH_hrs_bad"]       = (
        (df["pH_min"] < PH_GOOD_MIN) | (df["pH_max"] > PH_GOOD_MAX)
    ).rolling(36, min_periods=1).sum() / 6.0
    feat["waterLevel_hrs_bad"] = (
        (df["waterLevel_min"] < WATER_MIN_PERCENT) | (df["waterLevel_max"] > WATER_MAX_PERCENT)
    ).rolling(36, min_periods=1).sum() / 6.0

    # ── Continuous per-sensor hazard (rolling 6h) — smooth signal for boundary ─
    # These give the model a continuous gradient around each class boundary,
    # not just a binary pass/fail flag (which starves the "High" class).
    water_range = max(WATER_MAX_PERCENT - WATER_MIN_PERCENT, 1.0)

    do_hz   = np.clip(DO_OPTIMAL_MIN - df["DO_min"],   0, None) / DO_OPTIMAL_MIN
    ph_hz   = (
        np.clip(PH_GOOD_MIN - df["pH_min"],   0, None) / 1.5
      + np.clip(df["pH_max"] - PH_GOOD_MAX,   0, None) / 1.5
    )
    temp_hz = (
        np.clip(df["temp_max"] - TEMP_GOOD_MAX,  0, None) / 5.0
      + np.clip(TEMP_GOOD_MIN - df["temp_min"],  0, None) / 5.0
    )
    turb_hz = np.clip(df["turbidity_max"] - TURB_GOOD_MAX, 0, None) / TURB_GOOD_MAX
    water_hz = (
        np.clip(WATER_MIN_PERCENT - df["waterLevel_min"], 0, None) / water_range
      + np.clip(df["waterLevel_max"] - WATER_MAX_PERCENT, 0, None) / water_range
    )

    feat["DO_hazard_roll6h"]    = do_hz.rolling(36, min_periods=1).sum()
    feat["pH_hazard_roll6h"]    = ph_hz.rolling(36, min_periods=1).sum()
    feat["temp_hazard_roll6h"]  = temp_hz.rolling(36, min_periods=1).sum()
    feat["turb_hazard_roll6h"]  = turb_hz.rolling(36, min_periods=1).sum()
    feat["water_hazard_roll6h"] = water_hz.rolling(36, min_periods=1).sum()
    feat["total_hazard_roll6h"] = (
        feat["DO_hazard_roll6h"]
      + feat["pH_hazard_roll6h"]
      + feat["temp_hazard_roll6h"]
      + feat["turb_hazard_roll6h"]
      + feat["water_hazard_roll6h"]
    )

    # Forward-fill only (no bfill) to prevent look-ahead leakage on first row
    feat = feat.ffill().fillna(0)
    return feat, SENSORS


# ── Hazard score computation (deterministic rule-based, used for label generation) ──
def compute_wqc_score(df):
    """Compute a 0–100 internal hazard score from raw sensor DataFrame.

    Used internally to auto-generate Water Quality Classification training labels.
    NOT exposed in the final classification output.

    Uses a rolling 36-tick (6-hour) window sum of instantaneous per-sensor
    hazard sub-scores, normalised to [0, 100].

    Hazard sub-scores are proportional deviations from DENR/DA-BFAR thresholds:
      - DO:         deficit below DENR Class C minimum (5.0 mg/L)
      - pH_lo:      deficit below DENR lower bound (6.5)
      - pH_hi:      excess above DENR upper bound (8.5)
      - temp_hi:    excess above DA-BFAR max (30°C)
      - temp_lo:    deficit below DA-BFAR min (20°C)
      - turbidity:  excess above DENR Class C limit (50 NTU)
      - water_lo/hi: deviation from configured operating range
    """
    import numpy as np
    import pandas as pd

    s = pd.DataFrame(index=df.index)

    # DO hazard — scaled to [0, 1] at zero DO
    s["DO"]      = np.clip(DO_OPTIMAL_MIN - df["DO_min"], 0, None) / DO_OPTIMAL_MIN

    # pH hazard — scaled by 1.5 (distance from DENR bound to critical)
    s["pH_lo"]   = np.clip(PH_GOOD_MIN - df["pH_min"], 0, None) / (PH_GOOD_MIN - PH_CRIT_MIN)
    s["pH_hi"]   = np.clip(df["pH_max"] - PH_GOOD_MAX, 0, None) / (PH_CRIT_MAX - PH_GOOD_MAX)

    # Temp hazard — scaled by range from good to critical
    s["temp_hi"] = np.clip(df["temp_max"] - TEMP_GOOD_MAX, 0, None) / (TEMP_CRIT_MAX - TEMP_GOOD_MAX)
    s["temp_lo"] = np.clip(TEMP_GOOD_MIN - df["temp_min"], 0, None) / (TEMP_GOOD_MIN - TEMP_CRIT_MIN)

    # Turbidity hazard — scaled by DENR Class C limit
    s["turb"]    = np.clip(df["turbidity_max"] - TURB_FAIR_MAX, 0, None) / TURB_FAIR_MAX

    # Water level hazard
    water_range  = max(WATER_MAX_PERCENT - WATER_MIN_PERCENT, 1.0)
    s["water_lo"] = np.clip(WATER_MIN_PERCENT - df["waterLevel_min"], 0, None) / water_range
    s["water_hi"] = np.clip(df["waterLevel_max"] - WATER_MAX_PERCENT, 0, None) / water_range

    row_hazard  = s.sum(axis=1)
    WIN         = 36   # 6-hour window
    hazard_raw  = row_hazard.rolling(WIN, min_periods=1).sum()
    hazard_score = np.clip(hazard_raw / WQC_NORM_REF * 100, 0, 100)
    return hazard_score


# ── Class label mapping ──────────────────────────────────────────────────────────
def classify(score):
    """Map a WQC hazard score (0–100) to (class_int, class_name).

      0 — Low      (score < 25)  : All parameters within DENR/DA-BFAR optimal
      1 — Moderate (25 ≤ score < 50): Minor deviation; within good bounds
      2 — High     (50 ≤ score < 75): Fair/poor zone; action recommended
      3 — Critical (score ≥ 75)  : Any parameter in critical zone; act now
    """
    if score < 25:  return 0, "Low"
    if score < 50:  return 1, "Moderate"
    if score < 75:  return 2, "High"
    return 3, "Critical"


# ── Insight sentence generator ───────────────────────────────────────────────────
def generate_insight(driver, last_row, level):
    """Return a human-readable insight sentence citing the violated agency standard."""
    do_min    = float(last_row.get("DO_min",         0))
    ph_min    = float(last_row.get("pH_min",         0))
    ph_max    = float(last_row.get("pH_max",         0))
    temp_min  = float(last_row.get("temp_min",       0))
    temp_max  = float(last_row.get("temp_max",       0))
    turb_max  = float(last_row.get("turbidity_max",  0))
    water_avg = float(last_row.get("waterLevel_avg", 0))

    templates = {
        "DO": (
            f"Dissolved oxygen reached a low of {do_min:.1f} mg/L — "
            f"below the {DO_OPTIMAL_MIN:.1f} mg/L minimum set by DENR DAO 2016-08 Class C "
            f"and DA-BFAR freshwater aquaculture standards. "
            f"Sustained low DO increases stress and mortality risk in crayfish (Holdich 2002)."
        ),
        "pH": (
            f"pH ranged {ph_min:.2f}–{ph_max:.2f} during this period, "
            f"outside the {PH_GOOD_MIN:.1f}–{PH_GOOD_MAX:.1f} range specified by "
            f"DENR DAO 2016-08 Class C and DA-BFAR. "
            f"Prolonged pH imbalance impairs crayfish molting and calcium uptake (Holdich 2002; FAO TP-458)."
        ),
        "temp": (
            f"Water temperature ranged {temp_min:.1f}–{temp_max:.1f}°C, "
            f"outside the {TEMP_GOOD_MIN:.0f}–{TEMP_GOOD_MAX:.0f}°C range "
            f"recommended by DA-BFAR for freshwater aquaculture. "
            f"Extreme temperature stresses metabolism, feeding behavior, and immune response (Holdich 2002)."
        ),
        "turbidity": (
            f"Turbidity peaked at {turb_max:.1f} NTU — "
            f"above the {TURB_FAIR_MAX:.0f} NTU limit of DENR DAO 2016-08 Class C. "
            f"High turbidity reduces surface oxygen exchange, increases biological oxygen demand, "
            f"and impairs crayfish feeding visibility (Boyd & Tucker 1998; FAO TP-458)."
        ),
        "waterLevel": (
            f"Water level averaged {water_avg:.1f}% — outside the "
            f"{WATER_MIN_PERCENT:.0f}–{WATER_MAX_PERCENT:.0f}% operating range. "
            + (
                "Low water concentrates waste, raises stocking density, and increases territorial "
                "aggression in crayfish (FAO TP-458; Boyd & Tucker 1998)."
                if water_avg < WATER_MIN_PERCENT else
                "Excess water risks overflow, stock loss, and dilution of dissolved nutrients."
            )
        ),
    }
    return templates.get(driver, f"{driver} reading is outside the agency-recommended range.")


# ── Full classification pipeline ─────────────────────────────────────────────────
def _current_driver_details(last):
    """Identify the sensor causing the current risk from live deviations."""
    import numpy as np
    water_range = max(WATER_MAX_PERCENT - WATER_MIN_PERCENT, 1.0)
    hazards = {
        "DO": float(np.clip(DO_OPTIMAL_MIN - last["DO_min"], 0, None) / DO_OPTIMAL_MIN),
        "pH": float(max(np.clip(PH_GOOD_MIN - last["pH_min"], 0, None) / 1.5,
                         np.clip(last["pH_max"] - PH_GOOD_MAX, 0, None) / 1.5)),
        "temp": float(max(np.clip(last["temp_max"] - TEMP_GOOD_MAX, 0, None) / 5.0,
                           np.clip(TEMP_GOOD_MIN - last["temp_min"], 0, None) / 5.0)),
        "turbidity": float(np.clip(last["turbidity_max"] - TURB_GOOD_MAX, 0, None) / TURB_GOOD_MAX),
        "waterLevel": float(max(np.clip(WATER_MIN_PERCENT - last["waterLevel_min"], 0, None) / water_range,
                                np.clip(last["waterLevel_max"] - WATER_MAX_PERCENT, 0, None) / water_range)),
    }
    driver = max(hazards, key=hazards.get)
    if hazards[driver] <= 0:
        return "overall", 0.0, {"label": "All monitored parameters", "value": None, "unit": "", "min": None, "max": None}
    details = {
        "DO": {"label": "Dissolved Oxygen", "value": float(last["DO_avg"]), "unit": "mg/L", "min": DO_OPTIMAL_MIN, "max": None},
        "pH": {"label": "pH Level", "value": float(last["pH_avg"]), "unit": "", "min": PH_GOOD_MIN, "max": PH_GOOD_MAX},
        "temp": {"label": "Temperature", "value": float(last["temp_avg"]), "unit": "°C", "min": TEMP_GOOD_MIN, "max": TEMP_GOOD_MAX},
        "turbidity": {"label": "Turbidity", "value": float(last["turbidity_avg"]), "unit": "NTU", "min": 0.0, "max": TURB_GOOD_MAX},
        "waterLevel": {"label": "Water Level", "value": float(last["waterLevel_avg"]), "unit": "%", "min": WATER_MIN_PERCENT, "max": WATER_MAX_PERCENT},
    }
    return driver, hazards[driver], details[driver]


def predict_wqc(df, bundle, recs):
    """Classify risk and produce a current, explainable recommendation."""
    import numpy as np
    feat, _ = build_features(df)
    hazard_series = compute_wqc_score(df)
    score = round(float(hazard_series.iloc[-1]), 1)
    model_used = False
    if bundle is not None:
        model, features = bundle["model"], bundle["features"]
        latest = feat.iloc[[-1]].copy()
        for missing in set(features) - set(latest.columns): latest[missing] = 0.0
        latest = latest[features]
        if bundle.get("type", "classifier") == "regressor":
            predicted = float(np.clip(model.predict(latest)[0], 0, 100))
            score = round(predicted, 1)
            _, level = classify(score)
            diff = abs(predicted - float(hazard_series.iloc[-1]))
            confidence = 92 if diff < 5 else (85 if diff < 10 else (75 if diff < 20 else 65))
        else:
            raw = model.predict(latest)
            cls = int(raw.argmax(axis=1)[0] if len(raw.shape) == 2 else raw[0])
            confidence = round(float(model.predict_proba(latest)[0][cls]) * 100)
            level = CLASS_NAMES[cls]
        model_used = True
    else:
        _, level = classify(score)
        confidence = 85
    driver, driver_hazard, details = _current_driver_details(df.iloc[-1])
    rec = recs.get(driver, recs["overall"])
    action = rec.get("critical_action" if level == "Critical" else "action", rec["action"])
    from datetime import datetime, timezone
    return {
        "level": level, "confidence": confidence, "risk_score": score,
        "driver": driver, "driver_label": details["label"],
        "driver_value": details["value"], "driver_unit": details["unit"],
        "driver_min": details["min"], "driver_max": details["max"],
        "driver_hazard": round(driver_hazard, 3),
        "problem": rec["problem"],
        "insight": generate_insight(driver, df.iloc[-1], level) if driver != "overall" else rec["problem"],
        "action": action, "source": rec["source"],
        "analysis_mode": "XGBoost trend-aware classification" if model_used else "Rule-based water-quality assessment",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

