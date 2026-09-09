"""Prepare real or synthetic history without labels or crossing offline gaps."""
import numpy as np
import pandas as pd
from anomaly_features import SENSORS, build_anomaly_features


def prepare_history(frame):
    frame = frame.copy()
    frame['timestamp'] = pd.to_datetime(frame['timestamp'], utc=True, errors='coerce')
    columns = [f'{sensor}_{stat}' for sensor in SENSORS for stat in ('min', 'avg', 'max')]
    for column in columns:
        frame[column] = pd.to_numeric(frame[column], errors='coerce')
    valid = frame['timestamp'].notna() & np.isfinite(frame[columns]).all(axis=1)
    for sensor in SENSORS:
        low, avg, high = (frame[f'{sensor}_{stat}'] for stat in ('min', 'avg', 'max'))
        valid &= (low >= 0) & (low <= avg) & (avg <= high)
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
