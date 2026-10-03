"""Convert the external five-minute fishpond CSV to CrayCare's four-sensor grain.

The source file is read-only. The derived CSV deliberately excludes class labels,
sample IDs, and the three sensors not used by CrayCare WQAD.
"""

import argparse
import numpy as np
import pandas as pd


SOURCE_COLUMNS = {
    "temp_C": "temperature",
    "pH": "ph_level",
    "do_mgL": "dissolved_oxygen",
    "turbidity_NTU": "turbidity",
}


def prepare_dataset(source_path):
    frame = pd.read_csv(source_path)
    required = {"timestamp", *SOURCE_COLUMNS}
    missing = sorted(required - set(frame.columns))
    if missing:
        raise ValueError(f"Source CSV is missing required columns: {', '.join(missing)}")

    frame = frame[["timestamp", *SOURCE_COLUMNS]].copy()
    frame["timestamp"] = pd.to_datetime(frame["timestamp"], errors="coerce")
    for source, target in SOURCE_COLUMNS.items():
        frame[target] = pd.to_numeric(frame[source], errors="coerce")
    frame = frame.drop(columns=list(SOURCE_COLUMNS)).dropna(subset=["timestamp"])
    frame = frame.sort_values("timestamp")
    if frame["timestamp"].duplicated().any():
        raise ValueError("Source CSV contains duplicate timestamps; resolve them before resampling.")

    sensors = list(SOURCE_COLUMNS.values())
    valid = np.isfinite(frame[sensors]).all(axis=1) & (frame[sensors] >= 0).all(axis=1)
    frame = frame.loc[valid].set_index("timestamp")
    if frame.empty:
        raise ValueError("No complete, finite, nonnegative four-sensor rows remain.")

    # Source timestamps are five minutes apart. Keep only complete 10-minute
    # buckets with exactly two readings; never interpolate missing observations.
    grouped = frame[sensors].resample(
        "10min", origin="start_day", closed="left", label="right"
    )
    counts = grouped.size()
    means = grouped.mean()
    prepared = means.loc[counts == 2].dropna().reset_index()
    if prepared.empty:
        raise ValueError("No complete 10-minute buckets containing two readings were found.")
    return prepared[["timestamp", *sensors]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", required=True, help="Path to the original Zenodo CSV.")
    parser.add_argument("--output", required=True, help="Path for the derived four-sensor CSV.")
    args = parser.parse_args()

    prepared = prepare_dataset(args.dataset)
    prepared.to_csv(args.output, index=False)
    print(f"Prepared rows: {len(prepared):,}")
    print(f"Columns: {', '.join(prepared.columns)}")
    print(f"Start: {prepared['timestamp'].min()}")
    print(f"End: {prepared['timestamp'].max()}")
    print(f"Saved derived copy: {args.output}")
    print("Source labels and unused sensor columns were excluded; source CSV was not modified.")


if __name__ == "__main__":
    main()
