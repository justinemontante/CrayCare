"""CrayCare — Water Quality Dataset Generator
============================================

Generates `sensor_dataset.csv` — a synthetic 90-day time-series of pond
sensor readings at 10-minute intervals (~12,960 rows).

*** SYNTHETIC DATA — NOT REAL SENSOR READINGS ***
All thresholds used to define fault events are derived from official agency
standards (DENR DAO 2016-08, DA-BFAR, FAO TP-458, Boyd & Tucker 1998).
See agency_standards.py for full citations.

Class distribution target (approximate):
  0 — Low risk      ~45%   (all parameters within optimal/good range)
  1 — Moderate risk ~28%   (minor deviations, single parameter drifting)
  2 — High risk     ~15%   (one or more parameters in fair/poor zone)
  3 — Critical risk ~12%   (any parameter in critical zone)

Usage:
  python generate_dataset.py
  -> writes sensor_dataset.csv in the same directory
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta

from agency_standards import PARAM_STANDARDS

np.random.seed(42)

# ── Simulation parameters ──────────────────────────────────────────────────────
N_DAYS = 90           # longer = better temporal coverage across all fault types
INTERVAL_MIN = 10     # reading interval (minutes)
ROWS = int((N_DAYS * 24 * 60) / INTERVAL_MIN)
START = datetime(2025, 10, 1)   # Dry-season start (relevant for PH temp/DO dynamics)

# Agency-aligned baseline operating conditions (midpoint of optimal range)
BASELINES = {
    "temp":       26.0,   # °C — optimal 24–28 (DA-BFAR, FAO)
    "pH":          7.6,   # — optimal 7.0–8.0 (FAO/HOLDICH)
    "DO":          6.8,   # mg/L — well above 5.0 minimum (DENR/DA-BFAR)
    "turbidity":  12.0,   # NTU — below 25 NTU good threshold (DENR/FAO)
    "waterLevel": 140.0,  # cm — centre of 120–160 optimal range
}

# Diurnal amplitudes (natural daily swing for tropical pond)
AMPLITUDES = {
    "temp":       1.8,    # driven by solar radiation
    "pH":         0.35,   # photosynthesis drives pH up during day
    "DO":         1.3,    # DO inversely correlated with temp (peaks dawn)
    "turbidity":  2.0,    # slight morning/evening elevation from fish activity
    "waterLevel": 0.6,    # evaporation during day, rain refill at night
}

# Noise standard deviations
NOISE_SD = {
    "temp":       0.20,
    "pH":         0.07,
    "DO":         0.25,
    "turbidity":  1.00,
    "waterLevel": 0.40,
}

# DO is inversely correlated with temp (phase shift of 12 h)
DO_PHASE = 12.0


# ── Helper: diurnal sine + cumulative drift + noise ────────────────────────────
def diurnal(t, base, amp, sd, phase=0.0):
    daily = amp * np.sin(2 * np.pi * (t + phase) / 24.0)
    drift = np.cumsum(np.random.normal(0, sd * 0.10, len(t)))
    noise = np.random.normal(0, sd, len(t))
    return base + daily + drift + noise


# ── Time axis (hours since start) ─────────────────────────────────────────────
t = (np.arange(ROWS) * INTERVAL_MIN) / 60.0

# Base signals
signals = {
    "temp":       diurnal(t, BASELINES["temp"],       AMPLITUDES["temp"],       NOISE_SD["temp"]),
    "pH":         diurnal(t, BASELINES["pH"],         AMPLITUDES["pH"],         NOISE_SD["pH"]),
    "DO":         diurnal(t, BASELINES["DO"],         AMPLITUDES["DO"],         NOISE_SD["DO"],  phase=DO_PHASE),
    "turbidity":  np.clip(diurnal(t, BASELINES["turbidity"],  AMPLITUDES["turbidity"],  NOISE_SD["turbidity"]), 0.5, None),
    "waterLevel": diurnal(t, BASELINES["waterLevel"], AMPLITUDES["waterLevel"], NOISE_SD["waterLevel"]),
}


# ── Fault injection ────────────────────────────────────────────────────────────
def inject(arr, start, length, delta):
    """Apply a smooth bell-shaped perturbation of magnitude `delta` over `length` ticks."""
    end = min(start + length, len(arr))
    seg = np.arange(end - start)
    shape = np.sin(np.pi * seg / max(len(seg), 1))
    arr[start:end] += delta * shape
    return arr


# Fault definitions — magnitudes derived from agency threshold gaps:
# e.g., aerator failure drops DO from baseline 6.8 to ~1.5 (below 2.0 critical)
FAULT_KINDS = [
    # (name, deltas_dict, duration_range_ticks)
    # Aerator failure: DO crashes, temp rises slightly (DENR/FAO: DO < 2 critical)
    ("aerator_fail",  {"DO": -5.5,  "temp": +1.5,  "turbidity": +8.0},  (42, 108)),
    # pH acid crash: e.g., after heavy rain + acid soil runoff (DENR: < 6.5 alarm)
    ("pH_acid_crash", {"pH": -2.5,  "DO": -0.8},                         (30, 80)),
    # pH alkaline spike: algae bloom (DENR: > 8.5 alarm)
    ("pH_algae_spike",{"pH": +1.6,  "DO": +1.5,  "turbidity": +15.0},   (36, 90)),
    # Heat spike: high ambient temp (DA-BFAR: > 30 warning, > 35 critical)
    ("heat_spike",    {"temp": +7.0, "DO": -2.5},                         (36, 96)),
    # Overfeeding: turbidity spikes, DO drops (DENR: turbidity >50 alert)
    ("overfeeding",   {"turbidity": +55.0, "DO": -2.0, "pH": -0.4},      (30, 72)),
    # Water level low: evaporation / pump failure (FAO/Boyd)
    ("water_low",     {"waterLevel": -80.0},                              (36, 120)),
    # Water level high: heavy rain / inlet failure
    ("water_high",    {"waterLevel": +70.0},                              (36, 72)),
    # Cold snap (sub-optimal temp; HOLDICH: < 20 warning, < 15 critical)
    ("cold_snap",     {"temp": -9.0, "DO": +1.0},                         (36, 96)),
]

# Repeat each fault kind multiple times across the timeline so every CV fold
# sees at least one occurrence — prevents fold starvation of minority classes.
N_REPEATS = 5
events = []
for k_idx, (kind, deltas, dur_range) in enumerate(FAULT_KINDS):
    segment = ROWS // N_REPEATS
    stagger = int(segment / (len(FAULT_KINDS) + 1) * (k_idx + 1))
    for i in range(N_REPEATS):
        jitter = int(np.random.randint(-200, 200))
        start = int(np.clip(segment * i + stagger + jitter, 50, ROWS - 200))
        length = int(np.random.randint(*dur_range))
        events.append((kind, deltas, start, length))

for kind, deltas, s, ln in events:
    for sensor, delta in deltas.items():
        signals[sensor] = inject(signals[sensor], s, ln, delta)

# ── Clip to physically plausible bounds ───────────────────────────────────────
# Bounds are wider than agency thresholds to preserve the full label range
signals["temp"]       = np.clip(signals["temp"],       10.0,  42.0)
signals["DO"]         = np.clip(signals["DO"],           0.2,  13.0)
signals["pH"]         = np.clip(signals["pH"],           3.5,  10.5)
signals["turbidity"]  = np.clip(signals["turbidity"],    0.3, 160.0)
signals["waterLevel"] = np.clip(signals["waterLevel"],  20.0, 240.0)


# ── Build min/max spread around avg ───────────────────────────────────────────
def spread(avg, jitter_sd, spike_prob=0.025, spike_mag=None, clip_lo=None, clip_hi=None):
    """Simulate a 10-minute window min/max around an average reading."""
    n = len(avg)
    spread_ = np.abs(np.random.normal(jitter_sd, jitter_sd * 0.4, n))
    lo = avg - spread_
    hi = avg + spread_
    # Occasional sensor spike on max side (fouling, bubbles, etc.)
    if spike_mag:
        spikes = (np.random.random(n) < spike_prob) * np.random.uniform(spike_mag * 0.3, spike_mag, n)
        hi += spikes
    if clip_lo is not None:
        lo = np.clip(lo, clip_lo, None)
    if clip_hi is not None:
        hi = np.clip(hi, None, clip_hi)
    # Guarantee lo ≤ avg ≤ hi
    lo = np.minimum(lo, avg)
    hi = np.maximum(hi, avg)
    return lo, hi


temp_lo, temp_hi = spread(signals["temp"],       0.15, spike_mag=1.0,   clip_lo=10,   clip_hi=42)
do_lo,   do_hi   = spread(signals["DO"],         0.20, spike_mag=None,   clip_lo=0.1,  clip_hi=13)
ph_lo,   ph_hi   = spread(signals["pH"],         0.05, spike_mag=None,   clip_lo=3.5,  clip_hi=10.5)
turb_lo, turb_hi = spread(signals["turbidity"],  0.80, spike_mag=20.0,  clip_lo=0.1,  clip_hi=160)
wl_lo,   wl_hi   = spread(signals["waterLevel"], 0.30, spike_mag=1.0,   clip_lo=10,   clip_hi=240)

# ── Assemble DataFrame ────────────────────────────────────────────────────────
df = pd.DataFrame({
    "timestamp":      [START + timedelta(minutes=INTERVAL_MIN * i) for i in range(ROWS)],
    "temp_avg":       signals["temp"],
    "temp_min":       temp_lo,
    "temp_max":       temp_hi,
    "pH_avg":         signals["pH"],
    "pH_min":         ph_lo,
    "pH_max":         ph_hi,
    "DO_avg":         signals["DO"],
    "DO_min":         do_lo,
    "DO_max":         do_hi,
    "turbidity_avg":  signals["turbidity"],
    "turbidity_min":  turb_lo,
    "turbidity_max":  turb_hi,
    "waterLevel_avg": signals["waterLevel"],
    "waterLevel_min": wl_lo,
    "waterLevel_max": wl_hi,
}).round(3)

import os
_DIR = os.path.dirname(os.path.abspath(__file__))
out_path = os.path.join(_DIR, "sensor_dataset.csv")
df.to_csv(out_path, index=False)
print(f"Wrote sensor_dataset.csv — {len(df):,} rows × {len(df.columns)} columns")
print(f"Date range: {df['timestamp'].min()} → {df['timestamp'].max()}")
print(f"Fault events injected: {len(events)} ({len(FAULT_KINDS)} fault types × {N_REPEATS} repeats)")
print("\nSignal summary (avg column):")
for s in ["temp", "pH", "DO", "turbidity", "waterLevel"]:
    col = signals[s]
    print(f"  {s:12s}: min={col.min():.2f}  mean={col.mean():.2f}  max={col.max():.2f}")
