"""Auto-label sensor_dataset.csv -> sensor_labeled.csv

Uses shared WQRI scoring from features.py.

NOTE: This is AUTO-labeling via a deterministic formula, not independent
expert/biological labeling. See features.py module docstring for why this
matters when reporting model accuracy in the thesis.
"""

import pandas as pd
import numpy as np

from features import compute_wqri_score, classify

df = (
    pd.read_csv("sensor_dataset.csv", parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

wqri_score = compute_wqri_score(df)
df["wqri_score"] = wqri_score.round(1)
df["wqri_class"] = wqri_score.apply(lambda v: classify(v)[0])

df.to_csv("sensor_labeled.csv", index=False)
print(df["wqri_class"].value_counts().sort_index())
print("Wrote sensor_labeled.csv")
