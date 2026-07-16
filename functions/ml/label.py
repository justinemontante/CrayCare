"""Auto-label sensor_dataset.csv -> sensor_labeled.csv

Uses shared CSI scoring from features.py.
"""

import pandas as pd
import numpy as np

from features import compute_csi_score, classify

df = (
    pd.read_csv("sensor_dataset.csv", parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

csi_score = compute_csi_score(df)
df["csi_score"] = csi_score.round(1)
df["csi_class"] = csi_score.apply(lambda v: classify(v)[0])

df.to_csv("sensor_labeled.csv", index=False)
print(df["csi_class"].value_counts().sort_index())
print("Wrote sensor_labeled.csv")
