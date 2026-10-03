"""Shared validation for training files and Firestore sensor observations."""
import math
from datetime import datetime, timezone
from numbers import Real

SENSORS = ['temp', 'pH', 'DO', 'turbidity']
SENSOR_VALUE_FIELDS = {
    'temp': ('temperature', 'temp_avg'),
    'pH': ('ph_level', 'pH_avg'),
    'DO': ('dissolved_oxygen', 'DO_avg'),
    'turbidity': ('turbidity', 'turbidity_avg'),
}


def timestamp_seconds(value):
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, datetime):
        try:
            result = (value if value.tzinfo else value.replace(tzinfo=timezone.utc)).timestamp()
        except (ValueError, OverflowError):
            return None
        return result if math.isfinite(result) else None
    if isinstance(value, Real):
        value = float(value)
        if not math.isfinite(value) or value <= 0:
            return None
        return value / 1000 if value >= 100_000_000_000 else value
    if isinstance(value, str):
        try:
            return timestamp_seconds(float(value))
        except ValueError:
            try:
                return timestamp_seconds(datetime.fromisoformat(value.strip().replace('Z', '+00:00')))
            except ValueError:
                pass
    return None


def valid_sensor_value(value, sensor):
    if isinstance(value, bool) or not isinstance(value, Real):
        return False
    value = float(value)
    # Data-integrity limits only; these are not species safety thresholds.
    return math.isfinite(value) and value >= 0 and (sensor != 'pH' or value <= 14)


def normalize_history(frame):
    """Canonical values win over old aliases; invalid rows leave observable gaps."""
    import pandas as pd
    rows = frame.copy()
    if 'timestamp' not in rows:
        raise ValueError('Missing timestamp column.')
    rows['timestamp'] = rows['timestamp'].map(timestamp_seconds)
    valid = rows.timestamp.notna()
    for sensor, aliases in SENSOR_VALUE_FIELDS.items():
        source = next((name for name in aliases if name in rows), None)
        if source is None:
            raise ValueError(f'Missing required sensor: {aliases[0]}.')
        values = rows[source]
        booleans = values.map(lambda value: isinstance(value, bool))
        numeric = pd.to_numeric(values, errors='coerce')
        valid &= ~booleans & numeric.map(lambda value: valid_sensor_value(value, sensor))
        rows[aliases[0]] = numeric
    return (rows.loc[valid].sort_values('timestamp', kind='stable')
            .drop_duplicates('timestamp', keep='last').reset_index(drop=True))
