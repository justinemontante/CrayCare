"""Generate a reproducible bootstrap dataset for CrayCare WQAD.

The generated data are synthetic and are only for integration testing and
prototype validation. Event labels are never supplied to Isolation Forest;
they are retained solely to measure detection performance on the holdout.
Replace this dataset with calibrated, real Cherax RAS history before final
field validation or deployment claims.
"""

from datetime import datetime, timedelta, timezone
import os

import numpy as np
import pandas as pd

SEED = 42
N_DAYS = 90
INTERVAL_MINUTES = 10
TRAIN_DAYS = 60
ROWS = N_DAYS * 24 * (60 // INTERVAL_MINUTES)
START = datetime(2026, 1, 1, tzinfo=timezone.utc)
rng = np.random.default_rng(SEED)

t_hours = np.arange(ROWS) * INTERVAL_MINUTES / 60.0
day_cycle = 2 * np.pi * t_hours / 24.0
slow_cycle = 2 * np.pi * t_hours / (24.0 * 14.0)


def smooth_noise(scale):
    raw = rng.normal(0.0, scale, ROWS)
    return pd.Series(raw).rolling(5, min_periods=1, center=True).mean().to_numpy()


# Correlated, physically plausible operating profile. These values describe a
# sample tank; they are not WQAD decision thresholds.
temp = 26.4 + 1.25 * np.sin(day_cycle - 1.1) + 0.35 * np.sin(slow_cycle) + smooth_noise(0.18)
ph = 7.55 + 0.22 * np.sin(day_cycle - 0.4) + 0.05 * (temp - 26.4) + smooth_noise(0.045)
do = 6.45 - 0.46 * (temp - 26.4) + 0.34 * np.sin(day_cycle + 1.8) + smooth_noise(0.16)
turbidity = 10.8 + 0.55 * np.sin(day_cycle + 0.5) + smooth_noise(0.55)
# A repeatable two-day drawdown/refill cycle prevents the reference period from
# drifting into a permanently different distribution than the holdout period.
refill_cycle = (t_hours % 48.0) / 48.0
water_level = 18.25 - 0.55 * refill_cycle + 0.08 * np.sin(day_cycle) + smooth_noise(0.045)

signals = {"temp": temp, "pH": ph, "DO": do, "turbidity": turbidity, "waterLevel": water_level}
event_type = np.full(ROWS, "normal", dtype=object)
is_anomaly = np.zeros(ROWS, dtype=int)


def inject_event(name, start, duration, changes):
    end = min(start + duration, ROWS)
    n = end - start
    # Plateau with smooth entry/exit avoids unrealistic one-tick rectangles.
    ramp = max(2, min(12, n // 5))
    shape = np.ones(n)
    shape[:ramp] = np.linspace(0.08, 1.0, ramp)
    shape[-ramp:] = np.linspace(1.0, 0.08, ramp)
    for sensor, delta in changes.items():
        signals[sensor][start:end] += delta * shape
    event_type[start:end] = name
    is_anomaly[start:end] = 1


# Holdout-only operational anomalies. Their names—not sensor thresholds—form
# evaluation ground truth. The model never receives either label column.
holdout_start = TRAIN_DAYS * 24 * (60 // INTERVAL_MINUTES)
event_specs = [
    ("aeration_disruption", 2, 6, {"DO": -2.1, "turbidity": 3.5, "temp": 0.5}),
    ("filter_loading", 6, 8, {"turbidity": 18.0, "DO": -0.8}),
    ("acidic_source_water", 10, 5, {"pH": -1.05, "waterLevel": 1.1}),
    ("thermal_excursion", 14, 7, {"temp": 4.2, "DO": -1.35}),
    ("possible_leak", 18, 10, {"waterLevel": -4.0}),
    ("alkaline_drift", 22, 7, {"pH": 1.15, "DO": 0.55}),
    ("organic_load_event", 26, 8, {"turbidity": 24.0, "DO": -1.8, "pH": -0.35}),
]
for name, day_offset, duration_hours, changes in event_specs:
    start = holdout_start + day_offset * 24 * (60 // INTERVAL_MINUTES) + 8 * (60 // INTERVAL_MINUTES)
    inject_event(name, start, duration_hours * (60 // INTERVAL_MINUTES), changes)

# A separate sensor-stuck event is expressed as flat data rather than a value
# crossing a biological boundary.
stuck_start = holdout_start + 24 * 24 * (60 // INTERVAL_MINUTES)
stuck_duration = 7 * (60 // INTERVAL_MINUTES)
signals["DO"][stuck_start:stuck_start + stuck_duration] = signals["DO"][stuck_start]
event_type[stuck_start:stuck_start + stuck_duration] = "do_sensor_stuck"
is_anomaly[stuck_start:stuck_start + stuck_duration] = 1

physical_bounds = {
    "temp": (8.0, 42.0), "pH": (3.0, 11.0), "DO": (0.0, 15.0),
    "turbidity": (0.0, 200.0), "waterLevel": (0.0, 35.0),
}
for sensor, (low, high) in physical_bounds.items():
    signals[sensor] = np.clip(signals[sensor], low, high)


def window_triplet(sensor, spread_scale):
    avg = signals[sensor]
    spread = np.abs(rng.normal(spread_scale, spread_scale * 0.25, ROWS))
    low = avg - spread
    high = avg + spread
    if sensor == "DO":
        low[stuck_start:stuck_start + stuck_duration] = avg[stuck_start:stuck_start + stuck_duration]
        high[stuck_start:stuck_start + stuck_duration] = avg[stuck_start:stuck_start + stuck_duration]
    bound_low, bound_high = physical_bounds[sensor]
    return np.clip(low, bound_low, bound_high), avg, np.clip(high, bound_low, bound_high)


data = {
    "timestamp": [START + timedelta(minutes=i * INTERVAL_MINUTES) for i in range(ROWS)],
    "is_injected_anomaly": is_anomaly,
    "event_type": event_type,
}
for sensor, scale in {"temp": 0.10, "pH": 0.025, "DO": 0.09, "turbidity": 0.35, "waterLevel": 0.04}.items():
    low, avg, high = window_triplet(sensor, scale)
    data[f"{sensor}_avg"] = avg
    data[f"{sensor}_min"] = low
    data[f"{sensor}_max"] = high

df = pd.DataFrame(data)
numeric_columns = df.select_dtypes(include=["number"]).columns
df[numeric_columns] = df[numeric_columns].round(4)
output_path = os.path.join(os.path.dirname(__file__), "sensor_dataset.csv")
df.to_csv(output_path, index=False)
print(f"Wrote {output_path}")
print(f"Rows: {len(df):,}; training profile: first {TRAIN_DAYS} days; holdout: {N_DAYS - TRAIN_DAYS} days")
print(f"Injected holdout anomaly rows: {int(df['is_injected_anomaly'].sum()):,}")
print("Synthetic bootstrap data only — replace with real Cherax RAS history for field validation.")
