"""Shared feature engineering, WQRI scoring, and constants for the CrayCare ML pipeline.

WQRI = Water Quality Risk Index (formerly named "CSI" / Crayfish Stress
Index). Renamed because the score is computed purely from water-parameter
deviations (pH, DO, temperature, turbidity) — it is a water-quality hazard
proxy, NOT a direct physiological measurement of crayfish stress (no
biomarker, behavior, or mortality data is used anywhere in this pipeline).

METHODOLOGY NOTE FOR THESIS DEFENSE:
`wqri_class` (the ML training label) is derived from the deterministic
`compute_wqri_score()` formula below — it is NOT independent, expert- or
biologically-labeled ground truth. This means the ML model's job is to
approximate/generalize a KNOWN formula using richer temporal features
(rolling trend, volatility, hours-in-bad-condition) than the formula itself
uses. High classification accuracy mainly demonstrates that the model can
closely reproduce a known deterministic function — it does NOT, by itself,
validate that the formula correctly captures real crayfish stress. Frame the
ML component as "trend-aware early warning / smoothing over the rule-based
system," not as biologically-validated stress prediction, unless you have
literature that directly supports the specific thresholds used here.
See train_model.py Stage 1.5 for a concrete number on how much the temporal
engineering adds over the raw instantaneous readings.
"""

SENSORS = ["temp", "pH", "DO", "turbidity", "waterLevel"]

# Optimal ranges for crayfish aquaculture — aligned with Firestore config/default/ranges
PH_OPTIMAL_MIN = 7.0
PH_OPTIMAL_MAX = 8.5
TEMP_MAX = 30.0   # °C
TEMP_MIN = 24.0   # °C
DO_MIN = 4.5       # mg/L
TURB_MAX = 35.0    # NTU

# Fixed WQRI normalization reference — p96 of raw WQRI on labeled dataset
# p96 gives balanced class distribution for better ML training.
# Computed: raw WQRI (new thresholds) p96 = 25.20 → Low 45%, Moderate 31%, High 11%, Critical 13%
WQRI_NORM_REF = 25.20

CLASS_NAMES = ["Low", "Moderate", "High", "Critical"]


def build_features(df):
    """Build all 23 engineered features from raw sensor DataFrame.

    Expects columns: {sensor}_avg, {sensor}_min, {sensor}_max
    for each sensor in SENSORS.
    Returns (feat, sensors) where feat is the feature DataFrame.
    """
    import numpy as np
    import pandas as pd

    base_cols = []
    for s in SENSORS:
        base_cols += [f"{s}_avg", f"{s}_min", f"{s}_max"]

    feat = df[base_cols].copy()
    for s in SENSORS:
        a = df[f"{s}_avg"]
        feat[f"{s}_volatility"] = df[f"{s}_max"] - df[f"{s}_min"]
        feat[f"{s}_roll6h"] = a.rolling(36, min_periods=1).mean()
        feat[f"{s}_roll24h"] = a.rolling(144, min_periods=1).mean()
        feat[f"{s}_trend"] = a.diff().rolling(6, min_periods=1).mean()

    feat["DO_hrs_low"] = (df["DO_min"] < DO_MIN).rolling(36, min_periods=1).sum() / 6.0
    feat["temp_hrs_hi"] = (df["temp_max"] > TEMP_MAX).rolling(
        36, min_periods=1
    ).sum() / 6.0
    feat["pH_hrs_bad"] = (
        (df["pH_min"] < PH_OPTIMAL_MIN) | (df["pH_max"] > PH_OPTIMAL_MAX)
    ).rolling(36, min_periods=1).sum() / 6.0

    # Continuous per-sensor hazard, rolling-summed the same way
    # compute_wqri_score() builds the label -- the boolean hour-counts above
    # only capture "was it bad" (pass/fail), not "how bad" (magnitude). The
    # classifier was missing this continuous signal entirely, which is why
    # it could never learn the boundary of the "High" class: it had no
    # feature that actually varies smoothly with the WQRI score it's trying
    # to predict.
    do_hz = np.clip(DO_MIN - df["DO_min"], 0, None) / DO_MIN
    ph_hz = (
        np.clip(PH_OPTIMAL_MIN - df["pH_min"], 0, None) / 1.5
        + np.clip(df["pH_max"] - PH_OPTIMAL_MAX, 0, None) / 1.5
    )
    temp_hz = (
        np.clip(df["temp_max"] - TEMP_MAX, 0, None) / 4.0
        + np.clip(TEMP_MIN - df["temp_min"], 0, None) / 4.0
    )
    turb_hz = np.clip(df["turbidity_max"] - TURB_MAX, 0, None) / TURB_MAX

    feat["DO_hazard_roll6h"] = do_hz.rolling(36, min_periods=1).sum()
    feat["pH_hazard_roll6h"] = ph_hz.rolling(36, min_periods=1).sum()
    feat["temp_hazard_roll6h"] = temp_hz.rolling(36, min_periods=1).sum()
    feat["turb_hazard_roll6h"] = turb_hz.rolling(36, min_periods=1).sum()
    feat["total_hazard_roll6h"] = (
        feat["DO_hazard_roll6h"]
        + feat["pH_hazard_roll6h"]
        + feat["temp_hazard_roll6h"]
        + feat["turb_hazard_roll6h"]
    )

    # FIXED (was look-ahead leakage): the old code used .bfill() here, which
    # fills the leading NaN (from the `.diff()` warm-up on the very first
    # row) using a FUTURE value. We now forward-fill only (uses past values)
    # and fall back to 0 for the true first row, which has no prior reading
    # to borrow from — "assume zero trend until we have two readings"
    # instead of "peek at the next reading."
    feat = feat.ffill().fillna(0)
    return feat, SENSORS


def compute_wqri_score(df):
    """Compute a 0-100 Water Quality Risk Index from raw sensor DataFrames.

    Uses a rolling 36-tick (6-hour) window sum of instantaneous per-sensor
    hazard scores. This is a deterministic, rule-based formula — see module
    docstring for why that matters when interpreting ML accuracy trained on
    this label.
    """
    import numpy as np
    import pandas as pd

    s = pd.DataFrame(index=df.index)
    s["DO"] = np.clip(DO_MIN - df["DO_min"], 0, None) / DO_MIN
    s["pH_lo"] = np.clip(PH_OPTIMAL_MIN - df["pH_min"], 0, None) / 1.5
    s["pH_hi"] = np.clip(df["pH_max"] - PH_OPTIMAL_MAX, 0, None) / 1.5
    s["temp"] = np.clip(df["temp_max"] - TEMP_MAX, 0, None) / 4.0
    s["temp_lo"] = np.clip(TEMP_MIN - df["temp_min"], 0, None) / 4.0
    s["turb"] = np.clip(df["turbidity_max"] - TURB_MAX, 0, None) / TURB_MAX
    row_hazard = s.sum(axis=1)
    WIN = 36
    wqri_raw = row_hazard.rolling(WIN, min_periods=1).sum()
    wqri_score = np.clip(wqri_raw / WQRI_NORM_REF * 100, 0, 100)
    return wqri_score


def classify(score):
    """Map a WQRI score (0-100) to a (class_int, class_name) pair.

     0 — Low       (< 25)
     1 — Moderate  (25-49)
     2 — High      (50-74)
     3 — Critical  (>= 75)
    """
    if score < 25:
        return 0, "Low"
    if score < 50:
        return 1, "Moderate"
    if score < 75:
        return 2, "High"
    return 3, "Critical"


def generate_insight(driver, last_row, level):
    """Generate a short, human-readable insight sentence for the given driver.

    Plugs the actual latest numeric readings into a template so the text is
    specific to what the sensors just reported, not a generic label. Used
    alongside recommendations.json's "problem"/"action" fields — this is the
    longer explanatory sentence, those are the short label + action.
    """
    do_min = float(last_row.get("DO_min", 0))
    ph_min = float(last_row.get("pH_min", 0))
    ph_max = float(last_row.get("pH_max", 0))
    temp_min = float(last_row.get("temp_min", 0))
    temp_max = float(last_row.get("temp_max", 0))
    turb_max = float(last_row.get("turbidity_max", 0))
    water_avg = float(last_row.get("waterLevel_avg", 0))

    templates = {
        "DO": (
            f"Dissolved oxygen dropped to {do_min:.1f} mg/L, below the "
            f"{DO_MIN:.1f} mg/L safe minimum. Sustained low DO increases "
            f"stress and mortality risk in crayfish."
        ),
        "pH": (
            f"pH ranged {ph_min:.2f}-{ph_max:.2f}, outside the optimal "
            f"{PH_OPTIMAL_MIN:.1f}-{PH_OPTIMAL_MAX:.1f} range. Prolonged pH "
            f"imbalance can affect molting and shell hardness."
        ),
        "temp": (
            f"Water temperature ranged {temp_min:.1f}-{temp_max:.1f}\u00b0C, "
            f"outside the {TEMP_MIN:.0f}-{TEMP_MAX:.0f}\u00b0C safe range. "
            f"Extreme temperature stresses metabolism and feeding behavior."
        ),
        "turbidity": (
            f"Turbidity reached {turb_max:.1f} NTU, above the {TURB_MAX:.0f} "
            f"NTU threshold. High turbidity reduces oxygen exchange and "
            f"feeding visibility."
        ),
        "waterLevel": (
            f"Water level reading averaged {water_avg:.1f}, outside the "
            f"expected operating range. Abnormal water level concentrates "
            f"waste and raises stocking stress."
        ),
    }
    return templates.get(driver, f"{driver} reading is outside the optimal range.")
