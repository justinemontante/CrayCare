"""Shared feature engineering, WQRI scoring, and constants for the CrayCare ML pipeline.

WQRI = Water Quality Risk Index
All threshold values are aligned with official agency standards:
  - DENR DAO 2016-08  (Class C Inland Waters — Fishery Water Supply)
  - DA-BFAR           (Philippine Freshwater Aquaculture Water Quality)
  - FAO TP-458        (Water Quality for Pond Aquaculture)
  - Boyd & Tucker (1998); Holdich (2002)

See agency_standards.py for full citations and threshold rationale.

METHODOLOGY NOTE (for thesis/defense):
`wqri_class` (the ML training label) is derived from the deterministic
`compute_wqri_score()` formula — it is NOT independent, expert-labeled ground truth.
The ML model approximates/generalises this formula using richer temporal features
(rolling trend, volatility, hours-in-bad-condition) than the formula itself uses.
High classification accuracy primarily demonstrates that the model can closely
reproduce a known deterministic function. Frame the ML component as
"trend-aware early warning / smoothing over the rule-based system."
See train_model.py Stage 1.5 for ablation numbers to cite in the defense.
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

# Water level (cm) — configured operational range for tank
WATER_MIN_CM    = 120.0
WATER_MAX_CM    = 160.0

# ── WQRI normalisation reference ────────────────────────────────────────────────
# p96 of the raw rolling WQRI hazard on the 90-day dataset → balanced class split.
# Recompute if thresholds change: run compute_wqri_score() on the new dataset
# and take np.percentile(wqri_raw / p96 * 100, 96).
WQRI_NORM_REF = 28.50

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
        (df["waterLevel_min"] < WATER_MIN_CM) | (df["waterLevel_max"] > WATER_MAX_CM)
    ).rolling(36, min_periods=1).sum() / 6.0

    # ── Continuous per-sensor hazard (rolling 6h) — smooth signal for boundary ─
    # These give the model a continuous gradient around each class boundary,
    # not just a binary pass/fail flag (which starves the "High" class).
    water_range = max(WATER_MAX_CM - WATER_MIN_CM, 1.0)

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
        np.clip(WATER_MIN_CM - df["waterLevel_min"], 0, None) / water_range
      + np.clip(df["waterLevel_max"] - WATER_MAX_CM, 0, None) / water_range
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


# ── WQRI score computation (deterministic rule-based) ───────────────────────────
def compute_wqri_score(df):
    """Compute a 0–100 Water Quality Risk Index from raw sensor DataFrame.

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

    This is a DETERMINISTIC formula, not ML. It is used to auto-generate the
    `wqri_class` training label (see train_model.py docstring for implications).
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
    water_range  = max(WATER_MAX_CM - WATER_MIN_CM, 1.0)
    s["water_lo"] = np.clip(WATER_MIN_CM - df["waterLevel_min"], 0, None) / water_range
    s["water_hi"] = np.clip(df["waterLevel_max"] - WATER_MAX_CM, 0, None) / water_range

    row_hazard = s.sum(axis=1)
    WIN = 36   # 6-hour window
    wqri_raw   = row_hazard.rolling(WIN, min_periods=1).sum()
    wqri_score = np.clip(wqri_raw / WQRI_NORM_REF * 100, 0, 100)
    return wqri_score


# ── Class label mapping ──────────────────────────────────────────────────────────
def classify(score):
    """Map a WQRI score (0–100) to (class_int, class_name).

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
            f"Water level averaged {water_avg:.1f} cm — outside the "
            f"{WATER_MIN_CM:.0f}–{WATER_MAX_CM:.0f} cm optimal range. "
            + (
                "Low water concentrates waste, raises stocking density, and increases territorial "
                "aggression in crayfish (FAO TP-458; Boyd & Tucker 1998)."
                if water_avg < WATER_MIN_CM else
                "Excess water risks overflow, stock loss, and dilution of dissolved nutrients."
            )
        ),
    }
    return templates.get(driver, f"{driver} reading is outside the agency-recommended range.")


# ── Full prediction pipeline ─────────────────────────────────────────────────────
def predict_wqri(df, bundle, recs):
    """Single source of truth: raw sensor history → full WQRI prediction result.

    Used by BOTH the deployed Cloud Function (main.py) and the local test
    script (predict.py) so there is exactly one place to fix prediction bugs.

    Args:
        df:     raw sensor DataFrame sorted by timestamp (columns: {sensor}_avg/_min/_max)
        bundle: dict {"model", "features", "type"} from wqri_model.joblib, or None
        recs:   dict loaded from recommendations.json

    Returns dict: score, level, confidence, driver, problem, insight, action,
                  source, timestamp.
    """
    import numpy as np
    import pandas as pd

    feat, _ = build_features(df)

    # Always compute the deterministic WQRI score first — stable 0–100 metric
    wqri_series = compute_wqri_score(df)
    score       = round(float(wqri_series.iloc[-1]), 1)

    if bundle is not None:
        model      = bundle["model"]
        FEATURES   = bundle["features"]
        model_type = bundle.get("type", "classifier")

        latest_feat = feat.iloc[[-1]].copy()
        for m in set(FEATURES) - set(latest_feat.columns):
            latest_feat[m] = 0.0
        latest_feat = latest_feat[FEATURES]

        if model_type == "regressor":
            pred_score = float(np.clip(model.predict(latest_feat)[0], 0, 100))
            score      = round(pred_score, 1)
            _, level   = classify(score)
            diff       = abs(pred_score - float(wqri_series.iloc[-1]))
            confidence = 92 if diff < 5 else (85 if diff < 10 else (75 if diff < 20 else 65))
        else:
            raw_pred   = model.predict(latest_feat)
            pred_1d    = raw_pred.argmax(axis=1) if len(raw_pred.shape) == 2 else raw_pred
            cls        = int(pred_1d[0])
            proba      = model.predict_proba(latest_feat)[0]
            confidence = round(proba[cls] * 100)
            _, level   = classify(score)

        imp    = pd.Series(model.feature_importances_, index=FEATURES)
        driver = max(SENSORS, key=lambda s: imp[[c for c in FEATURES if c.startswith(s)]].sum())
    else:
        # Rule-based fallback: driver from WQRI hazard sub-scores
        _, level   = classify(score)
        confidence = 85
        last       = df.iloc[-1]
        water_range = max(WATER_MAX_CM - WATER_MIN_CM, 1.0)
        hazards = {
            "DO":         float(np.clip(DO_OPTIMAL_MIN - last["DO_min"], 0, None) / DO_OPTIMAL_MIN),
            "pH":         float(max(
                              np.clip(PH_GOOD_MIN - last["pH_min"], 0, None) / 1.5,
                              np.clip(last["pH_max"] - PH_GOOD_MAX, 0, None) / 1.5,
                          )),
            "temp":       float(max(
                              np.clip(last["temp_max"] - TEMP_GOOD_MAX, 0, None) / 5.0,
                              np.clip(TEMP_GOOD_MIN - last["temp_min"], 0, None) / 5.0,
                          )),
            "turbidity":  float(np.clip(last["turbidity_max"] - TURB_FAIR_MAX, 0, None) / TURB_FAIR_MAX),
            "waterLevel": float(max(
                              np.clip(WATER_MIN_CM - last["waterLevel_min"], 0, None) / water_range,
                              np.clip(last["waterLevel_max"] - WATER_MAX_CM, 0, None) / water_range,
                          )),
        }
        driver = max(hazards, key=hazards.get) if max(hazards.values()) > 0 else "DO"

    rec        = recs.get(driver, recs["DO"])
    action_key = "critical_action" if level == "Critical" else "action"
    action     = rec.get(action_key, rec.get("action", ""))
    insight    = generate_insight(driver, df.iloc[-1], level)

    from datetime import datetime, timezone
    return {
        "score":      score,
        "level":      level,
        "confidence": confidence,
        "driver":     driver,
        "problem":    rec["problem"],
        "insight":    insight,
        "action":     action,
        "source":     rec["source"],
        "timestamp":  datetime.now(timezone.utc).isoformat(),
    }
