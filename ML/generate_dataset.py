import random
import numpy as np
import pandas as pd
import os

random.seed(42)
np.random.seed(42)

os.makedirs("dataset", exist_ok=True)

# ── Stage defaults (farmer configures within these bands) ─────
STAGE_DEFAULTS = {
    "early_juvenile":    {
        "temp": (26, 28),  "ph": (7.5, 8.0),
        "do":   (5.0, 9.0), "turb": (0, 25), "wl": (5.0, 10.0)
    },
    "advanced_juvenile": {
        "temp": (25, 30),  "ph": (7.0, 8.5),
        "do":   (5.0, 10.0), "turb": (0, 30), "wl": (7.0, 12.0)
    },
    "pre_adult": {
        "temp": (24, 30),  "ph": (7.0, 8.5),
        "do":   (4.5, 10.0), "turb": (0, 35), "wl": (8.0, 13.0)
    },
    "market_size": {
        "temp": (24, 28),  "ph": (7.0, 8.0),
        "do":   (4.0, 9.0), "turb": (0, 40), "wl": (9.0, 15.0)
    },
}

STAGES    = list(STAGE_DEFAULTS.keys())
WARN_BAND = 0.10
NUM_SEQ   = 500   # 500 sequences × 20 readings = 10,000 rows
READS     = 20


# ── Randomly sample farmer-configured thresholds per sequence ─
def sample_thresholds(stage):
    b = STAGE_DEFAULTS[stage]
    j = lambda v, p: round(v * (1 + random.uniform(-p, p)), 2)
    return {
        "temp_min": j(b["temp"][0], .05), "temp_max": j(b["temp"][1], .05),
        "ph_min":   j(b["ph"][0],   .04), "ph_max":   j(b["ph"][1],   .04),
        "do_min":   j(b["do"][0],   .08), "do_max":   j(b["do"][1],   .08),
        "turb_min": j(b["turb"][0], .05), "turb_max": j(b["turb"][1], .10),
        "wl_min":   j(b["wl"][0],   .05), "wl_max":   j(b["wl"][1],   .05),
    }


# ── Label overall health from raw values vs thresholds only ───
# No ratios, no per-sensor status — pure comparison
def label_overall(temp, ph, do_, turb, wl,
                  t_min, t_max, p_min, p_max,
                  d_min, d_max, tr_min, tr_max,
                  wl_min, wl_max,
                  temp_rate, ph_rate, do_rate, turb_rate, wl_rate):

    t_span  = t_max  - t_min
    p_span  = p_max  - p_min
    d_span  = d_max  - d_min
    tr_span = tr_max - tr_min
    wl_span = wl_max - wl_min

    # CRITICAL thresholds — clearly outside safe range
    if (temp < t_min  - 0.15 * t_span  or temp > t_max  + 0.15 * t_span  or
        ph   < p_min  - 0.20 * p_span  or ph   > p_max  + 0.20 * p_span  or
        do_  < d_min  - 0.25 * d_span  or
        turb > tr_max + 0.30 * tr_span or
        wl   < wl_min - 0.20 * wl_span or wl   > wl_max + 0.20 * wl_span):
        return "CRITICAL"

    # WARNING thresholds — near boundaries or trending badly
    warn_band_t  = WARN_BAND * t_span
    warn_band_p  = WARN_BAND * p_span
    warn_band_d  = 0.15 * d_span
    warn_band_tr = 0.20 * tr_span
    warn_band_wl = WARN_BAND * wl_span

    temp_warn = (temp < t_min  + warn_band_t  or temp > t_max  - warn_band_t)
    ph_warn   = (ph   < p_min  + warn_band_p  or ph   > p_max  - warn_band_p)
    do_warn   = (do_  < d_min  + warn_band_d)
    turb_warn = (turb > tr_max - warn_band_tr)
    wl_warn   = (wl   < wl_min + warn_band_wl or wl   > wl_max - warn_band_wl)

    # Rate-based warning: fast trend near boundary
    rate_warn = (
        (abs(temp_rate) > 0.12 and temp_warn) or
        (abs(ph_rate)   > 0.03 and ph_warn)   or
        (do_rate        < -0.05 and do_warn)   or
        (turb_rate      > 0.8   and turb_warn) or
        (abs(wl_rate)   > 0.4   and wl_warn)
    )

    if any([temp_warn, ph_warn, do_warn, turb_warn, wl_warn]) or rate_warn:
        return "WARNING"

    return "OPTIMAL"


def overall_from_list(statuses):
    order = {"OPTIMAL": 0, "WARNING": 1, "CRITICAL": 2}
    return max(statuses, key=lambda s: order[s])


def initial_bounded(vmin, vmax, zone):
    span = vmax - vmin
    warn = WARN_BAND * span
    if zone == "OPTIMAL":
        lo, hi = vmin + warn + 0.01, vmax - warn - 0.01
    elif zone == "WARNING":
        lo, hi = (vmin, vmin + warn) if random.random() < .5 else (vmax - warn, vmax)
    else:
        lo, hi = (
            (vmin - .35 * span, vmin - .01)
            if random.random() < .5
            else (vmax + .01, vmax + .35 * span)
        )
    return random.uniform(min(lo, hi - .01), hi)


def smart_drift(val, vmin, vmax, drift, zone):
    span  = vmax - vmin
    ratio = (val - vmin) / span if span > 0 else 0.5
    if zone == "OPTIMAL":
        if ratio < 0.15 and drift < 0: drift =  abs(drift)
        if ratio > 0.85 and drift > 0: drift = -abs(drift)
    elif zone == "WARNING":
        if 0.20 < ratio < 0.80: drift = -drift
    else:
        if 0.10 < ratio < 0.90:
            drift = -abs(drift) if ratio < 0.5 else abs(drift)
    return drift


def assign_sensor_zones(overall_zone):
    if overall_zone == "OPTIMAL":
        return ["OPTIMAL"] * 5
    elif overall_zone == "WARNING":
        n_warn = random.randint(1, 3)
        zones  = ["WARNING"] * n_warn + ["OPTIMAL"] * (5 - n_warn)
        random.shuffle(zones)
        return zones
    else:
        n_crit = random.randint(1, 3)
        remain = 5 - n_crit
        n_warn = random.randint(0, remain)
        zones  = (["CRITICAL"] * n_crit +
                  ["WARNING"]  * n_warn +
                  ["OPTIMAL"]  * (remain - n_warn))
        random.shuffle(zones)
        return zones


# ── Generate ──────────────────────────────────────────────────
rows = []

for seq_idx in range(NUM_SEQ):
    stage  = random.choice(STAGES)
    thresh = sample_thresholds(stage)

    t_min,  t_max  = thresh["temp_min"], thresh["temp_max"]
    p_min,  p_max  = thresh["ph_min"],   thresh["ph_max"]
    d_min,  d_max  = thresh["do_min"],   thresh["do_max"]
    tr_min, tr_max = thresh["turb_min"], thresh["turb_max"]
    wl_min, wl_max = thresh["wl_min"],   thresh["wl_max"]

    overall_zone = random.choices(
        ["OPTIMAL", "WARNING", "CRITICAL"], weights=[.34, .33, .33]
    )[0]
    zones = assign_sensor_zones(overall_zone)
    temp_zone, ph_zone, do_zone, turb_zone, wl_zone = zones

    temp = initial_bounded(t_min,  t_max,  temp_zone)
    ph   = initial_bounded(p_min,  p_max,  ph_zone)
    do_  = initial_bounded(d_min,  d_max,  do_zone)
    turb = initial_bounded(tr_min, tr_max, turb_zone)
    wl   = initial_bounded(wl_min, wl_max, wl_zone)

    temp_drift = random.choice([-0.15, -0.05, 0, 0.05, 0.15])
    ph_drift   = random.choice([-0.02, -0.01, 0, 0.01, 0.02])
    do_drift   = random.choice([-0.06, -0.02, 0, 0.02, 0.06])
    turb_drift = random.choice([-0.3, 0, 0.3, 0.6])
    wl_drift   = random.choice([-0.6, -0.2, 0, 0.2, 0.6])

    prev = [temp, ph, do_, turb, wl]

    for rd_idx in range(READS):
        temp_drift = smart_drift(temp, t_min,  t_max,  temp_drift, temp_zone)
        ph_drift   = smart_drift(ph,   p_min,  p_max,  ph_drift,   ph_zone)
        do_drift   = smart_drift(do_,  d_min,  d_max,  do_drift,   do_zone)
        turb_drift = smart_drift(turb, tr_min, tr_max, turb_drift, turb_zone)
        wl_drift   = smart_drift(wl,   wl_min, wl_max, wl_drift,   wl_zone)

        temp += temp_drift + random.gauss(0, 0.04)
        ph   += ph_drift   + random.gauss(0, 0.008)
        do_  += do_drift   + random.gauss(0, 0.025)
        turb += turb_drift + random.gauss(0, 0.08)
        wl   += wl_drift   + random.gauss(0, 0.10)

        # Physical clamps
        temp = max(15.0, min(38.0,  temp))
        ph   = max(4.5,  min(10.5,  ph))
        do_  = max(0.2,  min(15.0,  do_))
        turb = max(0.0,  min(200.0, turb))
        wl   = max(1.0,  min(23.0,  wl))

        if rd_idx == 0:
            rates = [temp_drift, ph_drift, do_drift, turb_drift, wl_drift]
        else:
            cur   = [temp, ph, do_, turb, wl]
            rates = [round(c - p, 3) for c, p in zip(cur, prev)]
        prev = [temp, ph, do_, turb, wl]

        temp_rate, ph_rate, do_rate, turb_rate, wl_rate = [
            round(r, 3) for r in rates
        ]

        # Label from raw values only — NO ratios, NO per-sensor status
        health_status = label_overall(
            temp, ph, do_, turb, wl,
            t_min, t_max, p_min, p_max,
            d_min, d_max, tr_min, tr_max,
            wl_min, wl_max,
            temp_rate, ph_rate, do_rate, turb_rate, wl_rate,
        )

        rows.append({
            # identifiers
            "seq_id":  seq_idx,
            "rd_idx":  rd_idx,
            # features — what the ML model sees
            "growth_stage":     stage,
            "temperature":      round(temp, 3),
            "phLevel":          round(ph,   3),
            "dissolvedOxygen":  round(do_,  3),
            "turbidity":        round(turb, 3),
            "waterLevel":       round(wl,   3),
            "temp_rate":        temp_rate,
            "ph_rate":          ph_rate,
            "do_rate":          do_rate,
            "turb_rate":        turb_rate,
            "wl_rate":          wl_rate,
            "temp_min":         t_min,  "temp_max":  t_max,
            "ph_min":           p_min,  "ph_max":    p_max,
            "do_min":           d_min,  "do_max":    d_max,
            "turb_min":         tr_min, "turb_max":  tr_max,
            "wl_min":           wl_min, "wl_max":    wl_max,
            # target — what the ML model predicts
            "health_status":    health_status,
        })

df = pd.DataFrame(rows)
df.to_csv("dataset/craycare_dataset.csv", index=False)

print(f"[OK] {len(df):,} rows | {len(df.columns)} columns")
print(f"\nhealth_status distribution:")
print(df["health_status"].value_counts().to_string())
print(f"\nStage distribution:")
print(df["growth_stage"].value_counts().to_string())
print(f"\nFeature columns (ML input):")
FEATURE_COLS = [
    "growth_stage", "temperature", "phLevel", "dissolvedOxygen",
    "turbidity", "waterLevel", "temp_rate", "ph_rate", "do_rate",
    "turb_rate", "wl_rate", "temp_min", "temp_max", "ph_min", "ph_max",
    "do_min", "do_max", "turb_min", "turb_max", "wl_min", "wl_max",
]
print(FEATURE_COLS)
print(f"\nTarget column: health_status")
print(f"\nSensor value ranges:")
for col in ["temperature", "phLevel", "dissolvedOxygen", "turbidity", "waterLevel"]:
    print(f"  {col}: {df[col].min():.2f} – {df[col].max():.2f}")