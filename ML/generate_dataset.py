import random
import pandas as pd
import os

os.makedirs("dataset", exist_ok=True)

NUM_SEQUENCES = 3000
READINGS_PER_SEQUENCE = 20
TOTAL_ROWS = NUM_SEQUENCES * READINGS_PER_SEQUENCE

rows = []
all_statuses = []

for seq_idx in range(NUM_SEQUENCES):
    temp_min = round(random.uniform(22.0, 26.0), 1)
    temp_max = round(random.uniform(28.0, 32.0), 1)
    ph_min = round(random.uniform(6.5, 7.5), 1)
    ph_max = round(random.uniform(8.0, 9.0), 1)
    do_min = round(random.uniform(4.0, 6.0), 1)
    turb_max = round(random.uniform(20.0, 40.0), 1)
    wl_min = round(random.uniform(100.0, 140.0), 1)
    wl_max = round(random.uniform(160.0, 200.0), 1)

    temp = random.uniform(temp_min + 1.5, temp_max - 1.5)
    ph = random.uniform(ph_min + 0.4, ph_max - 0.4)
    do = random.uniform(do_min + 0.8, do_min + 2.5)
    turb = random.uniform(1.0, turb_max * 0.4)
    wl = random.uniform(wl_min + 15, wl_max - 15)

    temp_drift = random.choice([-0.25, -0.12, 0, 0.12, 0.25])
    ph_drift = random.choice([-0.04, -0.02, 0, 0.02, 0.04])
    do_drift = random.choice([-0.12, -0.06, 0, 0.06])
    turb_drift = random.choice([-0.4, 0, 0.4, 0.8, 1.5])
    wl_drift = random.choice([-0.8, -0.3, 0, 0.3, 0.8])

    prev_temp = temp
    prev_ph = ph
    prev_do = do
    prev_turb = turb
    prev_wl = wl

    for rd_idx in range(READINGS_PER_SEQUENCE):
        temp += temp_drift + random.uniform(-0.08, 0.08)
        ph += ph_drift + random.uniform(-0.015, 0.015)
        do += do_drift + random.uniform(-0.04, 0.04)
        turb += turb_drift + random.uniform(-0.15, 0.15)
        wl += wl_drift + random.uniform(-0.4, 0.4)

        temp = max(18.0, min(35.0, temp))
        ph = max(5.5, min(10.0, ph))
        do = max(1.0, min(10.0, do))
        turb = max(0.0, min(100.0, turb))
        wl = max(80.0, min(220.0, wl))

        if rd_idx == 0:
            temp_rate = round(random.uniform(-0.08, 0.08), 3)
            ph_rate = round(random.uniform(-0.015, 0.015), 3)
            do_rate = round(random.uniform(-0.04, 0.04), 3)
            turb_rate = round(random.uniform(-0.15, 0.15), 3)
            wl_rate = round(random.uniform(-0.4, 0.4), 3)
        else:
            temp_rate = round(temp - prev_temp, 3)
            ph_rate = round(ph - prev_ph, 3)
            do_rate = round(do - prev_do, 3)
            turb_rate = round(turb - prev_turb, 3)
            wl_rate = round(wl - prev_wl, 3)

        prev_temp, prev_ph = temp, ph
        prev_do, prev_turb, prev_wl = do, turb, wl

        def label_status(val, vmin, vmax, rate, rate_threshold):
            is_max_bound = vmax < 999.0
            range_span = (vmax - vmin) if is_max_bound else vmin
            warn_span = range_span * 0.15

            if val < vmin or (is_max_bound and val > vmax):
                return "CRITICAL"

            near_lower = (val - vmin) < warn_span
            near_upper = is_max_bound and (vmax - val) < warn_span

            if near_lower or near_upper:
                return "WARNING"

            if rate is not None and rate_threshold is not None:
                if (
                    rate > 0
                    and rate > rate_threshold
                    and is_max_bound
                    and (vmax - val) < warn_span * 2
                ):
                    return "WARNING"
                if (
                    rate < 0
                    and abs(rate) > rate_threshold
                    and (val - vmin) < warn_span * 2
                ):
                    return "WARNING"

            return "OPTIMAL"

        temp_status = label_status(temp, temp_min, temp_max, temp_rate, 0.15)
        ph_status = label_status(ph, ph_min, ph_max, ph_rate, 0.03)
        do_status = label_status(do, do_min, 999.0, do_rate, 0.08)
        turb_status = label_status(turb, 0.0, turb_max, turb_rate, 1.0)
        wl_status = label_status(wl, wl_min, wl_max, wl_rate, 0.5)

        status_order = {"OPTIMAL": 0, "WARNING": 1, "CRITICAL": 2}
        all_sensor_statuses = [
            temp_status,
            ph_status,
            do_status,
            turb_status,
            wl_status,
        ]
        max_level = max(status_order[s] for s in all_sensor_statuses)
        overall_status = {0: "OPTIMAL", 1: "WARNING", 2: "CRITICAL"}[max_level]

        rows.append(
            {
                "temperature": round(temp, 2),
                "phLevel": round(ph, 2),
                "dissolvedOxygen": round(do, 2),
                "turbidity": round(turb, 2),
                "waterLevel": round(wl, 2),
                "temp_rate": temp_rate,
                "ph_rate": ph_rate,
                "do_rate": do_rate,
                "turb_rate": turb_rate,
                "wl_rate": wl_rate,
                "temp_min": temp_min,
                "temp_max": temp_max,
                "ph_min": ph_min,
                "ph_max": ph_max,
                "do_min": do_min,
                "turb_max": turb_max,
                "wl_min": wl_min,
                "wl_max": wl_max,
                "temp_status": temp_status,
                "ph_status": ph_status,
                "do_status": do_status,
                "turb_status": turb_status,
                "wl_status": wl_status,
                "status": overall_status,
            }
        )
        all_statuses.append(overall_status)

df = pd.DataFrame(rows)
df.to_csv("dataset/craycare_dataset.csv", index=False)
print(f"Generated {len(df)} rows with per-sensor labels.")
print(f"Columns: {list(df.columns)}")
print(f"\nOverall Status distribution:")
print(df["status"].value_counts())
print(f"\nPer-sensor status distribution:")
for col in ["temp_status", "ph_status", "do_status", "turb_status", "wl_status"]:
    print(f"\n{col}:")
    print(df[col].value_counts())
