"""
CrayCare Dataset Generator — v2 (Duration-Aware Labeling)
============================================================
Key improvement over v1: labels are NOT a pure deterministic copy of the
threshold-comparison formula used as model features. This version adds:

1. DURATION-IN-ZONE as a real feature — how long a sensor has been
   sitting in a warning/critical band, not just its instantaneous value.
   This is grounded in real crayfish physiology literature, e.g.:
   - Sustained low DO (< 0.5 ppm for a week+) causes mortality in juveniles,
     while short hypoxia exposure (24h at 1-3 mg/L) does NOT kill P. clarkii
     (Effects of Hypoxia Stress on Survival..., PMC10813390).
   - Thermal tolerance studies show mortality driven by CUMULATIVE
     heat-induced damage, not instantaneous temperature alone.

2. STAGE-DEPENDENT SENSITIVITY — juveniles are physiologically more
   vulnerable than sub-adults/market-size crayfish at the same stressor
   level (consistent with oxygen-consumption-rate literature).

3. PROBABILISTIC BOUNDARY NOISE — borderline cases get a probabilistic
   label instead of a hard cutoff, simulating real-world expert
   disagreement/measurement noise instead of a clean deterministic split.

Because of (1)-(3), the health_status label is no longer a closed-form
function of the same min/max features fed to the model — a model trained
on this dataset must learn an interaction pattern (severity x duration x
stage-sensitivity), not just memorize a comparison.

LIMITATION (be upfront about this in your defense): this is still a
SYNTHETIC dataset for a Capstone 1 (Ch 1-3) proof-of-concept. It is not
validated against real mortality/intervention outcomes from an actual
farm deployment. That validation is explicitly future work (Ch 4-5 /
deployment phase).
"""

import random
import numpy as np
import pandas as pd
import os

random.seed(42)
np.random.seed(42)

os.makedirs("dataset", exist_ok=True)

# ── Stage defaults, anchored to literature where possible ─────
# temp upper-tolerance ~25-30C depending on species/study (PMC12248993,
# ResearchGate 350560732); DO safe target generally agreed >2-5 mg/L
# (thefishsite crawfish mgmt; PMC10813390); pH normal range ~7.0-8.5
# (ResearchGate 350560732: 7.12 +/- 0.21 typical).
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

# Juveniles are more physiologically vulnerable per-unit-stressor than
# market-size crayfish (higher O2 consumption rate & asphyxiation point
# at same temp — PMC10813390). Used as a SEVERITY MULTIPLIER, not as a
# rewrite of the thresholds themselves.
STAGE_SENSITIVITY = {
    "early_juvenile":    1.35,
    "advanced_juvenile": 1.15,
    "pre_adult":         1.00,
    "market_size":       0.85,
}

STAGES    = list(STAGE_DEFAULTS.keys())
WARN_BAND = 0.10
NUM_SEQ   = 250     # number of independent tank-event sequences
READS     = 40      # steps per sequence -> 250 x 40 = 10,000 rows
READING_INTERVAL_SEC = 5
# Each generated "reading" represents this many simulated minutes elapsing.
# This lets duration-in-zone span 0 to several hours within a sequence,
# matching the timescales in the literature (e.g. mortality after a week
# of <0.5ppm DO, vs no mortality after 24h at 1-3mg/L DO), without needing
# millions of 5-second-resolution rows.
SIM_MINUTES_PER_READ = 5.0


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


# ── Per-sensor zone classification (OPTIMAL/WARNING/CRITICAL band) ────
def zone_of(val, vmin, vmax):
    span = vmax - vmin
    if span <= 0:
        return "OPTIMAL"
    if val < vmin or val > vmax:
        return "CRITICAL" if (val < vmin - 0.15 * span or val > vmax + 0.15 * span) else "WARNING"
    ratio = (val - vmin) / span
    if ratio < WARN_BAND or ratio > (1 - WARN_BAND):
        return "WARNING"
    return "OPTIMAL"


# ── Duration-aware, stage-sensitive, probabilistic-boundary label ─────
# This is the core change vs v1. Severity now compounds with TIME SPENT
# in a bad zone (not just instantaneous distance from threshold), and
# stage sensitivity scales how fast that severity accumulates.
def label_overall_v2(
    zones,            # dict: short -> "OPTIMAL"/"WARNING"/"CRITICAL" (this instant)
    minutes_in_zone,  # dict: short -> minutes continuously spent in current bad zone
    stage,
    rates,            # dict: short -> rate of change
):
    sens = STAGE_SENSITIVITY[stage]

    # Per-sensor severity score: combines instantaneous zone + duration.
    # A WARNING that has persisted for 30+ min is treated similarly to a
    # fresh CRITICAL — consistent with sustained-exposure literature.
    sensor_severity = {}
    for short, z in zones.items():
        mins = minutes_in_zone.get(short, 0.0)
        if z == "OPTIMAL":
            sensor_severity[short] = 0.0
            continue
        base = 1.0 if z == "WARNING" else 2.2
        # duration multiplier: ramps from 1.0x (just entered zone) to ~1.6x
        # after ~3 hours of continuous bad exposure (diminishing returns).
        # Kept modest so duration nudges severity rather than dominating it —
        # avoids almost everything that lingers in WARNING eventually
        # tipping into CRITICAL.
        duration_mult = 1.0 + min(mins / 180.0, 1.0) * 0.6
        sensor_severity[short] = base * duration_mult * sens

    total_severity = sum(sensor_severity.values())
    n_bad = sum(1 for v in sensor_severity.values() if v > 0)

    # Multiple simultaneously-stressed sensors compound risk faster than
    # the sum alone (mirrors documented combo effects e.g. heat+low-DO).
    if n_bad >= 2:
        total_severity *= 1.25

    # Probabilistic boundary instead of a hard cutoff — simulates
    # measurement noise / expert disagreement near the decision boundary.
    # CRITICAL_CENTER / WARNING_CENTER define where the sigmoid is centered;
    # the random draw means cases right at the boundary don't always
    # resolve the same way, so the label is NOT a deterministic function
    # of the inputs alone.
    def sigmoid(x):
        return 1.0 / (1.0 + np.exp(-x))

    p_critical = sigmoid((total_severity - 5.5) * 1.3)
    p_at_least_warning = sigmoid((total_severity - 1.3) * 2.2)

    roll = random.random()
    if roll < p_critical:
        return "CRITICAL"
    roll2 = random.random()
    if roll2 < p_at_least_warning:
        return "WARNING"
    return "OPTIMAL"


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

SENSOR_KEYS = ["temp", "ph", "do", "turb", "wl"]

for seq_idx in range(NUM_SEQ):
    stage  = random.choice(STAGES)
    thresh = sample_thresholds(stage)

    t_min,  t_max  = thresh["temp_min"], thresh["temp_max"]
    p_min,  p_max  = thresh["ph_min"],   thresh["ph_max"]
    d_min,  d_max  = thresh["do_min"],   thresh["do_max"]
    tr_min, tr_max = thresh["turb_min"], thresh["turb_max"]
    wl_min, wl_max = thresh["wl_min"],   thresh["wl_max"]

    bounds = {
        "temp": (t_min, t_max), "ph": (p_min, p_max), "do": (d_min, d_max),
        "turb": (tr_min, tr_max), "wl": (wl_min, wl_max),
    }

    overall_zone_seed = random.choices(
        ["OPTIMAL", "WARNING", "CRITICAL"], weights=[.34, .33, .33]
    )[0]
    seed_zones = assign_sensor_zones(overall_zone_seed)
    sensor_zone_seed = dict(zip(SENSOR_KEYS, seed_zones))

    vals = {
        k: initial_bounded(bounds[k][0], bounds[k][1], sensor_zone_seed[k])
        for k in SENSOR_KEYS
    }

    drifts = {
        "temp": random.choice([-0.15, -0.05, 0, 0.05, 0.15]),
        "ph":   random.choice([-0.02, -0.01, 0, 0.01, 0.02]),
        "do":   random.choice([-0.06, -0.02, 0, 0.02, 0.06]),
        "turb": random.choice([-0.3, 0, 0.3, 0.6]),
        "wl":   random.choice([-0.6, -0.2, 0, 0.2, 0.6]),
    }

    prev = dict(vals)
    # tracks how many consecutive readings each sensor has spent
    # continuously in a non-OPTIMAL zone (reset to 0 when it returns to OPTIMAL)
    consec_bad_reads = {k: 0 for k in SENSOR_KEYS}

    for rd_idx in range(READS):
        cur_zone_for_drift = {
            k: zone_of(vals[k], bounds[k][0], bounds[k][1]) for k in SENSOR_KEYS
        }

        for k in SENSOR_KEYS:
            drifts[k] = smart_drift(vals[k], bounds[k][0], bounds[k][1], drifts[k], cur_zone_for_drift[k])

        noise = {
            "temp": random.gauss(0, 0.04), "ph": random.gauss(0, 0.008),
            "do": random.gauss(0, 0.025), "turb": random.gauss(0, 0.08),
            "wl": random.gauss(0, 0.10),
        }
        for k in SENSOR_KEYS:
            vals[k] += drifts[k] + noise[k]

        # Physical clamps
        vals["temp"] = max(15.0, min(38.0,  vals["temp"]))
        vals["ph"]   = max(4.5,  min(10.5,  vals["ph"]))
        vals["do"]   = max(0.2,  min(15.0,  vals["do"]))
        vals["turb"] = max(0.0,  min(200.0, vals["turb"]))
        vals["wl"]   = max(1.0,  min(23.0,  vals["wl"]))

        if rd_idx == 0:
            rates = dict(drifts)
        else:
            rates = {k: round(vals[k] - prev[k], 3) for k in SENSOR_KEYS}
        prev = dict(vals)

        # current instantaneous zone per sensor
        zones_now = {k: zone_of(vals[k], bounds[k][0], bounds[k][1]) for k in SENSOR_KEYS}

        # update consecutive-bad-reads counters -> convert to minutes
        for k in SENSOR_KEYS:
            if zones_now[k] == "OPTIMAL":
                consec_bad_reads[k] = 0
            else:
                consec_bad_reads[k] += 1
        minutes_in_zone = {
            k: consec_bad_reads[k] * SIM_MINUTES_PER_READ for k in SENSOR_KEYS
        }

        health_status = label_overall_v2(
            zones_now, minutes_in_zone, stage, rates
        )

        rows.append({
            "seq_id":  seq_idx,
            "rd_idx":  rd_idx,
            "growth_stage":     stage,
            "temperature":      round(vals["temp"], 3),
            "phLevel":          round(vals["ph"],   3),
            "dissolvedOxygen":  round(vals["do"],   3),
            "turbidity":        round(vals["turb"], 3),
            "waterLevel":       round(vals["wl"],   3),
            "temp_rate":        round(rates["temp"], 3),
            "ph_rate":          round(rates["ph"],   3),
            "do_rate":          round(rates["do"],   3),
            "turb_rate":        round(rates["turb"], 3),
            "wl_rate":          round(rates["wl"],   3),
            # NEW duration features — this is what makes the label
            # non-deterministic w.r.t. the threshold features alone
            "temp_minutes_in_zone": round(minutes_in_zone["temp"], 2),
            "ph_minutes_in_zone":   round(minutes_in_zone["ph"],   2),
            "do_minutes_in_zone":   round(minutes_in_zone["do"],   2),
            "turb_minutes_in_zone": round(minutes_in_zone["turb"], 2),
            "wl_minutes_in_zone":   round(minutes_in_zone["wl"],   2),
            "temp_min":         t_min,  "temp_max":  t_max,
            "ph_min":           p_min,  "ph_max":    p_max,
            "do_min":           d_min,  "do_max":    d_max,
            "turb_min":         tr_min, "turb_max":  tr_max,
            "wl_min":           wl_min, "wl_max":    wl_max,
            "health_status":    health_status,
        })

df = pd.DataFrame(rows)
df.to_csv("dataset/craycare_dataset_v2.csv", index=False)

print(f"[OK] {len(df):,} rows | {len(df.columns)} columns")
print(f"\nhealth_status distribution:")
print(df["health_status"].value_counts().to_string())
print(f"\nhealth_status distribution (%):")
print((df["health_status"].value_counts(normalize=True) * 100).round(1).to_string())
print(f"\nStage distribution:")
print(df["growth_stage"].value_counts().to_string())

FEATURE_COLS = [
    "growth_stage", "temperature", "phLevel", "dissolvedOxygen",
    "turbidity", "waterLevel", "temp_rate", "ph_rate", "do_rate",
    "turb_rate", "wl_rate",
    "temp_minutes_in_zone", "ph_minutes_in_zone", "do_minutes_in_zone",
    "turb_minutes_in_zone", "wl_minutes_in_zone",
    "temp_min", "temp_max", "ph_min", "ph_max",
    "do_min", "do_max", "turb_min", "turb_max", "wl_min", "wl_max",
]
print(f"\nFeature columns (ML input), {len(FEATURE_COLS)} total:")
print(FEATURE_COLS)
print(f"\nTarget column: health_status")
print(f"\nSensor value ranges:")
for col in ["temperature", "phLevel", "dissolvedOxygen", "turbidity", "waterLevel"]:
    print(f"  {col}: {df[col].min():.2f} - {df[col].max():.2f}")
print(f"\nDuration feature ranges (minutes):")
for col in ["temp_minutes_in_zone", "ph_minutes_in_zone", "do_minutes_in_zone",
            "turb_minutes_in_zone", "wl_minutes_in_zone"]:
    print(f"  {col}: {df[col].min():.2f} - {df[col].max():.2f}")