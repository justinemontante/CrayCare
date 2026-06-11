import random
import pandas as pd
import os

os.makedirs("dataset", exist_ok=True)

STAGES = ["early_juvenile", "advanced_juvenile", "pre_adult", "market_size"]

STAGE_RANGES = {
    "early_juvenile": {
        "temperature": {"min": 26.0, "max": 28.0},
        "phLevel": {"min": 7.5, "max": 8.0},
        "dissolvedOxygen": {"min": 5.0, "max": 999.0},
        "turbidity": {"min": 0.0, "max": 25.0},
        "waterLevel": {"min": 120.0, "max": 160.0},
    },
    "advanced_juvenile": {
        "temperature": {"min": 25.0, "max": 30.0},
        "phLevel": {"min": 7.0, "max": 8.5},
        "dissolvedOxygen": {"min": 5.0, "max": 999.0},
        "turbidity": {"min": 0.0, "max": 30.0},
        "waterLevel": {"min": 120.0, "max": 170.0},
    },
    "pre_adult": {
        "temperature": {"min": 24.0, "max": 30.0},
        "phLevel": {"min": 7.0, "max": 8.5},
        "dissolvedOxygen": {"min": 4.5, "max": 999.0},
        "turbidity": {"min": 0.0, "max": 35.0},
        "waterLevel": {"min": 130.0, "max": 180.0},
    },
    "market_size": {
        "temperature": {"min": 24.0, "max": 28.0},
        "phLevel": {"min": 7.0, "max": 8.0},
        "dissolvedOxygen": {"min": 4.0, "max": 999.0},
        "turbidity": {"min": 0.0, "max": 40.0},
        "waterLevel": {"min": 130.0, "max": 180.0},
    },
}

SENSOR_SPREAD = {
    "temperature": {"global_min": 20.0, "global_max": 35.0},
    "phLevel": {"global_min": 6.0, "global_max": 9.5},
    "dissolvedOxygen": {"global_min": 2.0, "global_max": 9.0},
    "turbidity": {"global_min": 0.0, "global_max": 80.0},
    "waterLevel": {"global_min": 90.0, "global_max": 210.0},
}

SENSOR_KEYS = ["temperature", "phLevel", "dissolvedOxygen", "turbidity", "waterLevel"]


def generate_optimal(ranges):
    vals = {}
    for key in SENSOR_KEYS:
        r = ranges[key]
        vals[key] = round(random.uniform(r["min"], r["max"]), 2)
    return vals


def generate_critical(ranges):
    vals = {}
    for key in SENSOR_KEYS:
        r = ranges[key]
        spread = SENSOR_SPREAD[key]
        if random.random() < 0.5:
            below_min = spread["global_min"]
            vals[key] = round(
                random.uniform(below_min, max(below_min, r["min"] - 0.1)), 2
            )
        else:
            above_max = spread["global_max"]
            vals[key] = round(
                random.uniform(min(above_max, r["max"] + 0.1), above_max), 2
            )
    return vals


def generate_for_stage(stage: str, num_rows: int = 10000):
    ranges = STAGE_RANGES[stage]
    half = num_rows // 2
    rows = []

    for _ in range(half):
        val = generate_optimal(ranges)
        val["status"] = "OPTIMAL"
        rows.append(val)

    for _ in range(num_rows - half):
        val = generate_critical(ranges)
        val["status"] = "CRITICAL"
        rows.append(val)

    random.shuffle(rows)
    df = pd.DataFrame(rows)
    path = f"dataset/{stage}.csv"
    df.to_csv(path, index=False)
    print(f"Saved {path}: {len(df)} rows ({df['status'].value_counts().to_dict()})")
    return df


all_dfs = []
for stage in STAGES:
    df = generate_for_stage(stage)
    df["stage"] = stage
    all_dfs.append(df)

combined = pd.concat(all_dfs, ignore_index=True)
combined.to_csv("dataset/craycare_dataset.csv", index=False)
print(f"\nCombined: {len(combined)} rows total")
