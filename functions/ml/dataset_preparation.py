"""Prepare the checked-in aquaculture dataset for CrayCare WQAD.

Stations stay separate, invalid rows are discarded, and no missing sensor
reading is interpolated or invented.
"""

import numpy as np
import pandas as pd


SOURCE_COLUMNS = {
    "TEMP": "temperature",
    "PH": "ph_level",
    "DO": "dissolved_oxygen",
    "TURBIDITY": "turbidity",
}


def prepare_dataset(source):
    frame = pd.read_csv(source, low_memory=False) if not isinstance(source, pd.DataFrame) else source.copy()
    station_column = next((name for name in ("station", "Station") if name in frame), None)
    required = {"Date", "Time", *SOURCE_COLUMNS}
    missing = sorted(required - set(frame.columns))
    if station_column is None or missing:
        details = ", ".join(missing or ["station"])
        raise ValueError(f"Dataset is missing required columns: {details}")

    prepared = pd.DataFrame()
    prepared["series_id"] = frame[station_column].astype("string").str.strip().str.lower()
    prepared["timestamp"] = pd.to_datetime(
        frame["Date"].astype("string") + " " + frame["Time"].astype("string"),
        dayfirst=True,
        errors="coerce",
        utc=True,
    )
    for source_name, target in SOURCE_COLUMNS.items():
        prepared[target] = pd.to_numeric(frame[source_name], errors="coerce")

    sensors = list(SOURCE_COLUMNS.values())
    valid = prepared["series_id"].notna() & prepared["timestamp"].notna()
    valid &= np.isfinite(prepared[sensors]).all(axis=1)
    valid &= (prepared[sensors] >= 0).all(axis=1)
    valid &= prepared["ph_level"].le(14)
    prepared = prepared.loc[valid].sort_values(["series_id", "timestamp"], kind="stable")
    prepared = prepared.drop_duplicates(["series_id", "timestamp"], keep="last")
    return prepared.reset_index(drop=True)
