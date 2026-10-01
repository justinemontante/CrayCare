"""Prepare real or synthetic history without labels or crossing offline gaps."""
import numpy as np
import pandas as pd
from anomaly_features import SENSORS, build_anomaly_features


def prepare_history(frame):
    frame = frame.copy()
    frame['timestamp'] = pd.to_datetime(frame['timestamp'], utc=True, errors='coerce')
    aliases = {
        'temp_avg': ('temperature', 'temp_avg'),
        'pH_avg': ('ph_level', 'pH_avg'),
        'DO_avg': ('dissolved_oxygen', 'DO_avg'),
        'turbidity_avg': ('turbidity', 'turbidity_avg'),
        'waterLevel': ('water_level', 'waterLevel', 'waterLevel_avg'),
    }
    value_columns = []
    for target, candidates in aliases.items():
        source = next((name for name in candidates if name in frame), None)
        if source is None:
            raise ValueError(f'Missing required sensor average: {candidates[0]}.')
        frame[target] = pd.to_numeric(frame[source], errors='coerce')
        value_columns.append(target)
    valid = (
        frame['timestamp'].notna()
        & np.isfinite(frame[value_columns]).all(axis=1)
        & (frame[value_columns] >= 0).all(axis=1)
    )
    frame = frame.loc[valid].sort_values('timestamp').drop_duplicates('timestamp', keep='last').reset_index(drop=True)
    gaps = frame['timestamp'].diff().dt.total_seconds()
    segment = (~gaps.between(480, 720)).cumsum()
    parts = []
    for _, rows in frame.groupby(segment):
        # Match inference's twelve-row, trailing window exactly. Never fill
        # through missing buckets or treat a long outage as a ten-minute step.
        if len(rows) >= 12:
            window = rows.copy()
            window['timestamp'] = window['timestamp'].map(lambda value: value.timestamp())
            parts.append(build_anomaly_features(window).iloc[11:])
    if not parts:
        raise ValueError('Need at least twelve contiguous valid ten-minute readings.')
    features = pd.concat(parts)
    return frame.loc[features.index].copy(), features
