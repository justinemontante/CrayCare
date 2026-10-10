"""Prepare sensor history using the same window rules as inference."""
import numpy as np
import pandas as pd
from anomaly_features import SENSORS, build_anomaly_features
from sensor_history import normalize_history


def prepare_history(frame, sensors=None, version=1):
    sensors = list(sensors or SENSORS)
    if sensors != SENSORS:
        raise ValueError('WQAD requires exactly temp,pH,DO,turbidity.')
    parts = []
    prepared_rows = []
    series_column = next((name for name in ('series_id', 'station', 'Station') if name in frame), None)
    groups = frame.groupby(series_column, sort=False, dropna=False) if series_column else [("default", frame)]
    for series_id, source_rows in groups:
        normalized = normalize_history(source_rows)
        if normalized.empty:
            continue
        normalized['series_id'] = str(series_id)
        gaps = normalized.timestamp.diff()
        if version >= 3:
            positive_gaps = gaps[gaps > 0]
            cadence = float(positive_gaps.median()) if not positive_gaps.empty else 600.0
            if not 480 <= cadence <= 1800:
                raise ValueError(f'Unsupported cadence for series {series_id}: {cadence:.0f} seconds.')
            # A gap of more than 2.2 expected intervals starts a fresh window.
            segment = ((gaps <= 0) | (gaps > cadence * 2.2)).cumsum()
        else:
            segment = (~gaps.between(480, 1320 if version >= 2 else 720)).cumsum()
        for _, rows in normalized.groupby(segment):
            minimum_rows = 6 if version >= 3 else 12
            if len(rows) < minimum_rows:
                continue
            features = build_anomaly_features(rows, sensors=sensors, version=version)
            if version >= 3:
                elapsed = rows.timestamp - float(rows.timestamp.iloc[0])
                ready = pd.Series((elapsed >= 110 * 60).to_numpy(), index=rows.index)
            else:
                ready = pd.Series(np.arange(len(rows)) >= 11, index=rows.index)
                if version >= 2:
                    ready &= rows.timestamp.diff().gt(720).rolling(11, min_periods=11).sum().le(1)
            selected = rows.loc[ready].copy()
            selected_features = features.loc[ready].copy()
            if not selected.empty:
                offset = sum(len(part) for part in prepared_rows)
                selected.index = pd.RangeIndex(offset, offset + len(selected))
                selected_features.index = selected.index
                prepared_rows.append(selected)
                parts.append(selected_features)
    if not parts or not any(len(part) for part in parts):
        raise ValueError('Need enough continuous valid readings to build a two-hour history window.')
    features = pd.concat(parts)
    result = pd.concat(prepared_rows)
    result['timestamp'] = pd.to_datetime(result.timestamp, unit='s', utc=True)
    return result, features
