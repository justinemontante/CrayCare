"""Shared feature engineering, CSI scoring, and constants for the CrayCare ML pipeline."""

SENSORS = ["temp", "pH", "DO", "turbidity", "waterLevel"]

# Optimal ranges for crayfish aquaculture — aligned with Firestore config/default/ranges
PH_OPTIMAL_MIN = 7.0
PH_OPTIMAL_MAX = 8.5
TEMP_MAX = 30.0   # °C
TEMP_MIN = 24.0   # °C
DO_MIN = 4.5       # mg/L
TURB_MAX = 35.0    # NTU

# Fixed CSI normalization reference — p96 of raw CSI on labeled dataset
# p96 gives balanced class distribution for better ML training.
# Computed: raw CSI (new thresholds) p96 = 25.20 → Low 45%, Moderate 31%, High 11%, Critical 13%
CSI_NORM_REF = 25.20

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

    feat = feat.bfill().fillna(0)
    return feat, SENSORS


def compute_csi_score(df):
    """Compute a 0-100 Crayfish Stress Index from raw sensor DataFrames.

    Uses rolling 36-tick (6-hour) window of individual hazard scores.
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
    csi_raw = row_hazard.rolling(WIN, min_periods=1).sum()
    csi_score = np.clip(csi_raw / CSI_NORM_REF * 100, 0, 100)
    return csi_score


def classify(score):
    """Map a CSI score (0-100) to a (class_int, class_name) pair.

     0 — Low       (< 25)
     1 — Moderate  (25-49)
     2 — High      (50-74)
     3 — Critical  (≥ 75)
    """
    if score < 25:
        return 0, "Low"
    if score < 50:
        return 1, "Moderate"
    if score < 75:
        return 2, "High"
    return 3, "Critical"
