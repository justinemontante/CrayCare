"""Auto-label sensor_dataset.csv -> sensor_labeled.csv"""

import pandas as pd
import numpy as np

df = (
    pd.read_csv("sensor_dataset.csv", parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

s = pd.DataFrame(index=df.index)
s["DO"] = np.clip(5.0 - df["DO_min"], 0, None) / 5.0
s["pH_lo"] = np.clip(6.5 - df["pH_min"], 0, None) / 1.5
s["pH_hi"] = np.clip(df["pH_max"] - 8.5, 0, None) / 1.5
s["temp"] = np.clip(df["temp_max"] - 31.0, 0, None) / 4.0
s["temp_lo"] = np.clip(24.0 - df["temp_min"], 0, None) / 4.0
s["turb"] = np.clip(df["turbidity_max"] - 25.0, 0, None) / 25.0

row_hazard = s.sum(axis=1)
WIN = 36
csi_raw = row_hazard.rolling(WIN, min_periods=1).sum()
csi_score = np.clip(csi_raw / csi_raw.quantile(0.99) * 100, 0, 100)


def to_class(x):
    if x < 25:
        return 0
    if x < 50:
        return 1
    if x < 75:
        return 2
    return 3


df["csi_score"] = csi_score.round(1)
df["csi_class"] = csi_score.apply(to_class)

df.to_csv("sensor_labeled.csv", index=False)
print(df["csi_class"].value_counts().sort_index())
print("Wrote sensor_labeled.csv")
