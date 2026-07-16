"""CrayCare WQRI Dataset Generator -> sensor_dataset.csv

*** SYNTHETIC DATA -- NOT REAL SENSOR READINGS ***
This generates a purely simulated dataset (sine-wave diurnal patterns +
randomly injected fault events: aerator failure, heat spike, pH drop,
overfeeding). It exists so the ML pipeline can be built and prototyped
before real pond data is available.

Any accuracy/metric computed downstream from sensor_labeled.csv (which is
derived from this file) should be reported as "prototype validation on
synthetic data," NOT as field-validated performance. Swap this in for a
real historical export of sensorReadings from Firestore once enough real
data has been collected, then re-run label.py + train_model.py on that.
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta

np.random.seed(42)

N_DAYS = 45
INTERVAL_MIN = 10
ROWS = int((N_DAYS * 24 * 60) / INTERVAL_MIN)
START = datetime(2026, 5, 1)


def diurnal(t, base, amp, sd, phase=0.0):
    daily = amp * np.sin(2 * np.pi * (t + phase) / 24.0)
    drift = np.cumsum(np.random.normal(0, sd * 0.15, len(t)))
    noise = np.random.normal(0, sd, len(t))
    return base + daily + drift + noise


t = (np.arange(ROWS) * INTERVAL_MIN) / 60.0

temp_avg = diurnal(t, 27.5, 1.8, 0.25)
do_avg = diurnal(t, 6.8, 1.3, 0.30, phase=12)
ph_avg = diurnal(t, 7.6, 0.35, 0.08)
turb_avg = np.clip(diurnal(t, 12.0, 2.0, 1.2), 1, None)
water_avg = diurnal(t, 50.0, 0.6, 0.5)


def inject(arr, s, ln, delta):
    e = min(s + ln, len(arr))
    seg = np.arange(e - s)
    shape = np.sin(np.pi * seg / max(len(seg), 1))
    arr[s:e] += delta * shape
    return arr


# Each fault kind repeats several times, spread across the whole timeline
# (staggered per kind + randomized jitter/duration). A single occurrence per
# kind meant later TimeSeriesSplit CV folds tested on fault patterns the
# model had literally never seen in training -- this is what was collapsing
# fold 3/4 accuracy and starving the "High" class of learnable examples.
FAULT_KINDS = ["aer", "heat", "ph", "feed"]
N_REPEATS = 4
events = []
for k_idx, kind in enumerate(FAULT_KINDS):
    segment = ROWS // N_REPEATS
    stagger = int(segment / (len(FAULT_KINDS) + 1) * (k_idx + 1))
    for i in range(N_REPEATS):
        jitter = int(np.random.randint(-150, 150))
        start = int(np.clip(segment * i + stagger + jitter, 50, ROWS - 150))
        length = int(np.random.randint(35, 95))
        events.append((kind, start, length))

for kind, s, ln in events:
    if kind == "aer":
        do_avg = inject(do_avg, s, ln, -4.0)
        temp_avg = inject(temp_avg, s, ln, 1.2)
    if kind == "heat":
        temp_avg = inject(temp_avg, s, ln, 4.5)
        do_avg = inject(do_avg, s, ln, -2.0)
    if kind == "ph":
        ph_avg = inject(ph_avg, s, ln, -2.8)
    if kind == "feed":
        turb_avg = inject(turb_avg, s, ln, 35.0)
        do_avg = inject(do_avg, s, ln, -1.5)

temp_avg = np.clip(temp_avg, 18, 40)
do_avg = np.clip(do_avg, 0.5, 12)
ph_avg = np.clip(ph_avg, 3.5, 10)
turb_avg = np.clip(turb_avg, 0.5, 120)
water_avg = np.clip(water_avg, 20, 80)


def minmax(avg, jit, spike_p=0.03, mag=3.0, sign=-1):
    n = len(avg)
    spread = np.abs(np.random.normal(jit, jit * 0.4, n))
    lo = avg - spread
    hi = avg + spread
    sp = (np.random.random(n) < spike_p) * np.random.uniform(mag * 0.4, mag, n)
    if sign < 0:
        lo -= sp
    else:
        hi += sp
    return lo, hi


def order(lo, avg, hi, a, b):
    return np.clip(np.minimum(lo, avg), a, b), np.clip(np.maximum(hi, avg), a, b)


tl, th = minmax(temp_avg, 0.15, mag=1.0, sign=1)
temp_min, temp_max = order(tl, temp_avg, th, 15, 42)
dl, dh = minmax(do_avg, 0.20, mag=2.5, sign=-1)
do_min, do_max = order(dl, do_avg, dh, 0.1, 13)
pl, ph = minmax(ph_avg, 0.05, mag=1.2, sign=-1)
ph_min, ph_max = order(pl, ph_avg, ph, 3.0, 10.5)
ul, uh = minmax(turb_avg, 0.80, mag=15.0, sign=1)
turb_min, turb_max = order(ul, turb_avg, uh, 0.1, 140)
wl, wh = minmax(water_avg, 0.30, mag=1.0, sign=-1)
water_min, water_max = order(wl, water_avg, wh, 15, 85)

df = pd.DataFrame(
    {
        "timestamp": [START + timedelta(minutes=INTERVAL_MIN * i) for i in range(ROWS)],
        "temp_avg": temp_avg,
        "temp_min": temp_min,
        "temp_max": temp_max,
        "pH_avg": ph_avg,
        "pH_min": ph_min,
        "pH_max": ph_max,
        "DO_avg": do_avg,
        "DO_min": do_min,
        "DO_max": do_max,
        "turbidity_avg": turb_avg,
        "turbidity_min": turb_min,
        "turbidity_max": turb_max,
        "waterLevel_avg": water_avg,
        "waterLevel_min": water_min,
        "waterLevel_max": water_max,
    }
).round(2)

df.to_csv("sensor_dataset.csv", index=False)
print(f"Wrote sensor_dataset.csv ({len(df):,} rows)")
