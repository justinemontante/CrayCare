"""Prepare sensor history using the same window rules as inference."""
import numpy as np
import pandas as pd
from anomaly_features import SENSORS, build_anomaly_features
from sensor_history import normalize_history


def prepare_history(frame, sensors=None, version=1):
    sensors = list(sensors or SENSORS)
    if sensors != SENSORS:
        raise ValueError('WQAD requires exactly temp,pH,DO,turbidity.')
    frame = normalize_history(frame)
    gaps = frame.timestamp.diff()
    segment = (~gaps.between(480, 1320 if version >= 2 else 720)).cumsum()
    parts = []
    for _, rows in frame.groupby(segment):
        if len(rows) >= 12:
            features = build_anomaly_features(rows, sensors=sensors, version=version)
            ready = pd.Series(np.arange(len(rows)) >= 11, index=rows.index)
            if version >= 2:
                ready &= rows.timestamp.diff().gt(720).rolling(11, min_periods=11).sum().le(1)
            parts.append(features.loc[ready])
    if not parts or not any(len(part) for part in parts):
        raise ValueError('Need at least twelve recent valid ten-minute readings.')
    features = pd.concat(parts)
    result = frame.loc[features.index].copy()
    result['timestamp'] = pd.to_datetime(result.timestamp, unit='s', utc=True)
    return result, features
