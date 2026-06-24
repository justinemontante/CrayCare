"""
CrayCare Dataset Generator for VALUE PREDICTION Regression
===========================================================
Generates LONG sequences (1000 readings = ~83 min) to enable
30-min and 60-min future value prediction training.

Key for TRUE ML regression:
  - Current reading + features → predicted VALUE at 30min / 60min
  - Not status labels, actual numeric values
  - Model learns temporal dynamics from realistic drift patterns
"""

import random
import numpy as np
import pandas as pd
import os

random.seed(42)
np.random.seed(42)

os.makedirs("dataset", exist_ok=True)

STAGE_DEFAULTS = {
    "early_juvenile": {
        "temp": (26.0, 28.0),
        "ph": (7.5, 8.0),
        "do_min": 5.0,
        "turb_max": 25.0,
        "wl": (120.0, 160.0),
    },
    "advanced_juvenile": {
        "temp": (25.0, 30.0),
        "ph": (7.0, 8.5),
        "do_min": 5.0,
        "turb_max": 30.0,
        "wl": (120.0, 170.0),
    },
    "pre_adult": {
        "temp": (24.0, 30.0),
        "ph": (7.0, 8.5),
        "do_min": 4.5,
        "turb_max": 35.0,
        "wl": (130.0, 180.0),
    },
    "market_size": {
        "temp": (24.0, 28.0),
        "ph": (7.0, 8.0),
        "do_min": 4.0,
        "turb_max": 40.0,
        "wl": (130.0, 180.0),
    },
}

STAGES = list(STAGE_DEFAULTS.keys())
WARN_BAND = 0.10  # 10% — matches Flutter app threshold

NUM_SEQUENCES = 10
READINGS_PER_SEQ = 1000  # 10 sequences x 1000 readings = 10,000 rows exactly


def sample_thresholds(stage):
    base = STAGE_DEFAULTS[stage]
    jitter = lambda v, pct: round(v * (1 + random.uniform(-pct, pct)), 2)
    t_min, t_max = base["temp"]
    p_min, p_max = base["ph"]
    wl_min, wl_max = base["wl"]
    return {
        "temp_min": jitter(t_min, 0.05),
        "temp_max": jitter(t_max, 0.05),
        "ph_min": jitter(p_min, 0.04),
        "ph_max": jitter(p_max, 0.04),
        "do_min": jitter(base["do_min"], 0.08),
        "turb_max": jitter(base["turb_max"], 0.10),
        "wl_min": jitter(wl_min, 0.05),
        "wl_max": jitter(wl_max, 0.05),
    }


def compute_ratio(val, vmin, vmax):
    span = vmax - vmin
    return (val - vmin) / span if span > 0 else 0.5


def label_bounded(ratio, rate, rate_warn):
    if ratio < 0 or ratio > 1:
        return "CRITICAL"
    if ratio < WARN_BAND or ratio > (1 - WARN_BAND):
        return "WARNING"
    if rate < -rate_warn and ratio < 0.30:
        return "WARNING"
    if rate > rate_warn and ratio > 0.70:
        return "WARNING"
    return "OPTIMAL"


def label_do(val, do_min, rate):
    margin = val - do_min
    ratio = margin / max(do_min, 0.1)
    if val < do_min:
        return "CRITICAL"
    if ratio < WARN_BAND:
        return "WARNING"
    if rate < -0.08 and ratio < 0.40:
        return "WARNING"
    return "OPTIMAL"


def label_turb(val, turb_max, rate):
    if val > turb_max:
        return "CRITICAL"
    ratio = val / max(turb_max, 0.1)
    if ratio > (1 - WARN_BAND):
        return "WARNING"
    if rate > 1.0 and ratio > 0.70:
        return "WARNING"
    return "OPTIMAL"


def overall_status(statuses):
    order = {"OPTIMAL": 0, "WARNING": 1, "CRITICAL": 2}
    return max(statuses, key=lambda s: order[s])


def choose_zone():
    return random.choices(
        ["OPTIMAL", "WARNING", "CRITICAL"],
        weights=[0.45, 0.30, 0.25],
    )[0]


def initial_bounded(vmin, vmax, zone):
    span = vmax - vmin
    warn = WARN_BAND * span
    if zone == "OPTIMAL":
        lo, hi = vmin + warn + 0.01, vmax - warn - 0.01
    elif zone == "WARNING":
        if random.random() < 0.5:
            lo, hi = vmin, vmin + warn
        else:
            lo, hi = vmax - warn, vmax
    else:
        if random.random() < 0.5:
            lo, hi = vmin - 0.35 * span, vmin - 0.01
        else:
            lo, hi = vmax + 0.01, vmax + 0.35 * span
    lo = min(lo, hi - 0.01)
    return random.uniform(lo, hi)


def initial_do(do_min, zone):
    warn = WARN_BAND * do_min
    if zone == "OPTIMAL":
        return random.uniform(do_min + warn + 0.1, do_min + 4.0)
    elif zone == "WARNING":
        return random.uniform(do_min, do_min + warn)
    else:
        return random.uniform(max(0.5, do_min - 2.5), do_min - 0.01)


def initial_turb(turb_max, zone):
    warn_hi = turb_max * (1 - WARN_BAND)
    if zone == "OPTIMAL":
        return random.uniform(0.0, warn_hi - 0.5)
    elif zone == "WARNING":
        return random.uniform(warn_hi, turb_max)
    else:
        return random.uniform(turb_max + 0.5, turb_max * 1.4)


rows = []

for seq_idx in range(NUM_SEQUENCES):
    stage = random.choice(STAGES)
    thresh = sample_thresholds(stage)

    t_min, t_max = thresh["temp_min"], thresh["temp_max"]
    p_min, p_max = thresh["ph_min"], thresh["ph_max"]
    do_min = thresh["do_min"]
    turb_max = thresh["turb_max"]
    wl_min, wl_max = thresh["wl_min"], thresh["wl_max"]

    temp = initial_bounded(t_min, t_max, choose_zone())
    ph = initial_bounded(p_min, p_max, choose_zone())
    do = initial_do(do_min, choose_zone())
    turb = initial_turb(turb_max, choose_zone())
    wl = initial_bounded(wl_min, wl_max, choose_zone())

    temp_drift = random.choice([-0.30, -0.15, -0.05, 0, 0.05, 0.15, 0.30])
    ph_drift = random.choice([-0.05, -0.02, 0, 0.02, 0.05])
    do_drift = (-abs(temp_drift) * 0.07) + random.uniform(-0.07, 0.04)
    turb_drift = random.choice([-0.5, 0, 0.5, 1.0, 2.0])
    wl_drift = random.choice([-1.0, -0.4, 0, 0.4, 1.0])

    prev_temp = temp
    prev_ph = ph
    prev_do = do
    prev_turb = turb
    prev_wl = wl

    for rd_idx in range(READINGS_PER_SEQ):
        temp += temp_drift + random.gauss(0, 0.05)
        ph += ph_drift + random.gauss(0, 0.01)
        do += do_drift + random.gauss(0, 0.03)
        turb += turb_drift + random.gauss(0, 0.10)
        wl += wl_drift + random.gauss(0, 0.30)

        temp = max(15.0, min(38.0, temp))
        ph = max(4.5, min(10.5, ph))
        do = max(0.2, min(15.0, do))
        turb = max(0.0, min(200.0, turb))
        wl = max(60.0, min(250.0, wl))

        if rd_idx == 0:
            temp_rate = round(temp_drift, 3)
            ph_rate = round(ph_drift, 3)
            do_rate = round(do_drift, 3)
            turb_rate = round(turb_drift, 3)
            wl_rate = round(wl_drift, 3)
        else:
            temp_rate = round(temp - prev_temp, 3)
            ph_rate = round(ph - prev_ph, 3)
            do_rate = round(do - prev_do, 3)
            turb_rate = round(turb - prev_turb, 3)
            wl_rate = round(wl - prev_wl, 3)

        prev_temp, prev_ph, prev_do, prev_turb, prev_wl = temp, ph, do, turb, wl

        temp_ratio = round(compute_ratio(temp, t_min, t_max), 4)
        ph_ratio = round(compute_ratio(ph, p_min, p_max), 4)
        do_ratio = round((do - do_min) / max(do_min, 0.1), 4)
        turb_ratio = round(turb / max(turb_max, 0.1), 4)
        wl_ratio = round(compute_ratio(wl, wl_min, wl_max), 4)

        temp_status = label_bounded(temp_ratio, temp_rate, 0.12)
        ph_status = label_bounded(ph_ratio, ph_rate, 0.03)
        do_status = label_do(do, do_min, do_rate)
        turb_status = label_turb(turb, turb_max, turb_rate)
        wl_status = label_bounded(wl_ratio, wl_rate, 0.40)

        ov = overall_status([temp_status, ph_status, do_status, turb_status, wl_status])

        rows.append(
            {
                "seq_id": seq_idx,
                "rd_idx": rd_idx,
                "temperature": round(temp, 3),
                "phLevel": round(ph, 3),
                "dissolvedOxygen": round(do, 3),
                "turbidity": round(turb, 3),
                "waterLevel": round(wl, 3),
                "temp_rate": temp_rate,
                "ph_rate": ph_rate,
                "do_rate": do_rate,
                "turb_rate": turb_rate,
                "wl_rate": wl_rate,
                "temp_min": t_min,
                "temp_max": t_max,
                "ph_min": p_min,
                "ph_max": p_max,
                "do_min": do_min,
                "turb_max": turb_max,
                "wl_min": wl_min,
                "wl_max": wl_max,
                "temp_ratio": temp_ratio,
                "ph_ratio": ph_ratio,
                "do_ratio": do_ratio,
                "turb_ratio": turb_ratio,
                "wl_ratio": wl_ratio,
                "stage": stage,
                "temp_status": temp_status,
                "ph_status": ph_status,
                "do_status": do_status,
                "turb_status": turb_status,
                "wl_status": wl_status,
                "status": ov,
            }
        )

df = pd.DataFrame(rows)
df.to_csv("dataset/craycare_dataset.csv", index=False)
print(f"[OK] Generated {len(df):,} rows | {len(df.columns)} features")
print(
    f"      {NUM_SEQUENCES} sequences x {READINGS_PER_SEQ} readings = {NUM_SEQUENCES * READINGS_PER_SEQ} rows"
)
print(
    f"      1hr look-ahead = 720 readings (valid for rows 0-{READINGS_PER_SEQ - 721})"
)
print(
    f"      2hr look-ahead = 1440 readings (valid for rows 0-{READINGS_PER_SEQ - 1441})"
)
print(f"\nStage distribution:")
print(df["stage"].value_counts())
print(f"\nOverall Status distribution:")
print(df["status"].value_counts())
