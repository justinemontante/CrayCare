"""Feature engineering and inference for CrayCare WQAD.

WQAD is an unsupervised multivariate anomaly detector. It learns the usual
joint behaviour of sensor readings and temporal changes; it does not use
water-quality thresholds or threshold-generated class labels.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sensor_history import SENSORS, SENSOR_VALUE_FIELDS, normalize_history, timestamp_seconds


def build_anomaly_features(df, sensors=None, version=1):
    """Create leakage-safe temporal features from 10-minute sensor windows."""
    import numpy as np
    import pandas as pd

    sensors = list(sensors or SENSORS)
    feat = pd.DataFrame(index=df.index)
    time_index = None
    if version >= 3:
        time_index = pd.to_datetime(
            df["timestamp"].map(timestamp_seconds), unit="s", utc=True, errors="coerce"
        )

    def time_rolling(values, window, min_periods, operation):
        """Return a time-based rolling statistic without changing row indexes."""
        series = pd.Series(values.to_numpy(), index=time_index)
        rolled = getattr(series.rolling(window, min_periods=min_periods), operation)()
        return pd.Series(rolled.to_numpy(), index=df.index)
    for sensor in sensors:
        value_column = next(
            (name for name in SENSOR_VALUE_FIELDS[sensor] if name in df), None
        )
        if value_column is None:
            raise ValueError(
                f"{sensor} readings require a canonical sensor field or legacy average field."
            )
        avg = pd.to_numeric(df[value_column], errors="coerce")
        feat[f"{sensor}_avg"] = avg
        delta = avg.diff()
        if version >= 2:
            elapsed = df['timestamp'].map(timestamp_seconds).diff() / 600.0
            delta = delta / elapsed.where(elapsed > 0)
        feat[f"{sensor}_delta"] = delta
        if version >= 3:
            feat[f"{sensor}_roll1h_mean"] = time_rolling(avg, "60min", 2, "mean")
            feat[f"{sensor}_roll1h_std"] = time_rolling(avg, "60min", 2, "std")
            feat[f"{sensor}_roll2h_mean"] = time_rolling(avg, "120min", 3, "mean")
            feat[f"{sensor}_roll2h_std"] = time_rolling(avg, "120min", 3, "std")
            feat[f"{sensor}_trend30m"] = time_rolling(delta, "30min", 2, "mean")
            feat[f"{sensor}_trend1h"] = time_rolling(delta, "60min", 3, "mean")
        else:
            feat[f"{sensor}_roll1h_mean"] = avg.rolling(6, min_periods=2).mean()
            feat[f"{sensor}_roll1h_std"] = avg.rolling(6, min_periods=2).std()
            feat[f"{sensor}_roll2h_mean"] = avg.rolling(12, min_periods=3).mean()
            feat[f"{sensor}_roll2h_std"] = avg.rolling(12, min_periods=3).std()
            feat[f"{sensor}_trend30m"] = delta.rolling(3, min_periods=2).mean()
            feat[f"{sensor}_trend1h"] = delta.rolling(6, min_periods=3).mean()
        scale = feat[f"{sensor}_roll2h_std"].clip(lower=1e-6)
        feat[f"{sensor}_baseline_deviation"] = (
            avg - feat[f"{sensor}_roll2h_mean"]
        ) / scale

    if "timestamp" in df and version == 1:
        numeric = pd.to_numeric(df["timestamp"], errors="coerce")
        timestamp = pd.to_datetime(numeric, unit="s", utc=True, errors="coerce")
        if timestamp.isna().all():
            timestamp = pd.to_datetime(df["timestamp"], utc=True, errors="coerce")
        hour = timestamp.dt.hour + timestamp.dt.minute / 60.0
        feat["time_hour_sin"] = np.sin(2 * np.pi * hour / 24.0)
        feat["time_hour_cos"] = np.cos(2 * np.pi * hour / 24.0)

    return feat.replace([np.inf, -np.inf], np.nan).ffill().fillna(0.0)


def _percentile_score(raw_value, calibration_scores):
    import numpy as np

    scores = np.asarray(calibration_scores, dtype=float)
    if scores.size == 0:
        return 0.0
    rank = np.searchsorted(np.sort(scores), raw_value, side="right")
    return round(float(rank / scores.size * 100.0), 1)


def _contributors(latest, bundle, sensors):
    import numpy as np

    centers = bundle.get("robust_centers", {})
    scales = bundle.get("robust_scales", {})
    contributions = []
    for sensor in sensors:
        names = [
            f"{sensor}_avg",
            f"{sensor}_delta",
            f"{sensor}_trend30m",
            f"{sensor}_trend1h",
            f"{sensor}_baseline_deviation",
        ]
        z_values = []
        for name in names:
            center = float(centers.get(name, 0.0))
            scale = max(float(scales.get(name, 1.0)), 1e-6)
            z_values.append(abs((float(latest.get(name, 0.0)) - center) / scale))
        contribution = float(np.mean(sorted(z_values, reverse=True)[:3]))
        trend = float(latest.get(f"{sensor}_trend30m", 0.0))
        direction = (
            "increasing"
            if trend > 1e-9
            else ("decreasing" if trend < -1e-9 else "stable")
        )
        contributions.append(
            {
                "sensor": sensor,
                "value": round(float(latest.get(f"{sensor}_avg", 0.0)), 3),
                "direction": direction,
                "contribution_score": round(contribution, 3),
            }
        )
    return sorted(
        contributions, key=lambda item: item["contribution_score"], reverse=True
    )


def _model_contributors(latest, bundle, raw_value):
    """Score reduction when a sensor's features are replaced by fit medians.

    This sensitivity diagnostic is not a causal explanation or a SHAP value.
    Correlated feature replacement can be outside the observed distribution.
    """
    import pandas as pd
    variants = []
    for sensor in SENSORS:
        replaced = latest.copy()
        for name in latest.columns:
            if name.startswith(sensor + '_'):
                replaced[name] = bundle['feature_medians'][name]
        variants.append(replaced)
    scores = -bundle['model'].score_samples(pd.concat(variants, ignore_index=True))
    items = []
    for sensor, score in zip(SENSORS, scores):
        effect = max(0.0, raw_value - float(score))
        if effect <= 1e-10:
            continue
        trend = float(latest.iloc[0][sensor + '_trend30m'])
        deadband = float(bundle.get('trend_deadbands', {}).get(sensor, 0.0))
        direction = 'stable' if abs(trend) <= deadband else ('increasing' if trend > 0 else 'decreasing')
        items.append({'sensor': sensor, 'value': round(float(latest.iloc[0][sensor + '_avg']), 3),
                      'direction': direction, 'contribution_score': round(effect, 6)})
    return sorted(items, key=lambda item: item['contribution_score'], reverse=True)


def detect_water_quality_anomaly(df, bundle, recommendations):
    """Return a WQAD result for the latest complete sensor window."""
    if bundle is None:
        return {
            "status": "Insufficient",
            "is_anomaly": False,
            "anomaly_score": 0.0,
            "insight": "The anomaly-detection model is not available.",
            "recommendation": "Deploy a trained WQAD model before interpreting sensor patterns.",
            "contributors": [],
            "source": "Model unavailable",
        }

    # WQAD uses only the four water-quality sensors. Never fall back to
    # water-level inputs for older model bundles.
    sensors = list(bundle.get("sensors", SENSORS))
    if sensors != SENSORS:
        raise ValueError("WQAD model must use exactly temp, pH, DO, and turbidity.")
    version = int(bundle.get('feature_version', -1))
    if version != 3 or bundle.get('algorithm') != 'IsolationForest':
        raise ValueError('WQAD requires the trained feature-version-3 Isolation Forest bundle.')
    if version >= 2:
        from anomaly_window import anomaly_window
        try:
            df = normalize_history(df)
        except (ValueError, TypeError):
            df = df.iloc[:0]
        if not df.empty:
            df, status, _ = anomaly_window(df, float(df.timestamp.iloc[-1]))
        else:
            status = 'insufficient'
        if status != 'ready':
            return {'status': 'Insufficient', 'is_anomaly': False, 'anomaly_score': 0.0,
                    'contributors': [], 'source': 'Insufficient data',
                    'insight': 'A complete recent window of valid sensor readings is required.',
                    'recommendation': 'Check sensor connectivity and calibration, then collect more readings.'}
    features = build_anomaly_features(df, sensors=sensors, version=version)
    expected = bundle["features"]
    latest = features.iloc[[-1]].copy()
    if set(expected) - set(latest.columns):
        raise ValueError('Model feature schema does not match inference; retrain the bundle.')
    latest = latest[expected]
    model = bundle["model"]
    raw_value = -float(model.score_samples(latest)[0] if version >= 2 else model.decision_function(latest)[0])
    anomaly_score = _percentile_score(raw_value, bundle.get("calibration_scores", []))
    is_anomaly = (raw_value > float(bundle["decision_threshold_raw"]) if version >= 2
                  else raw_value >= float(bundle["decision_threshold_raw"]))
    contributors = (_model_contributors(latest, bundle, raw_value) if version >= 2
                    else _contributors(latest.iloc[0], bundle, sensors))

    from anomaly_interpreter import interpret_anomaly

    interpreted = interpret_anomaly(
        is_anomaly, anomaly_score, contributors, recommendations
    )
    return {
        "status": "Unusual" if is_anomaly else "Normal",
        "is_anomaly": is_anomaly,
        "anomaly_score": anomaly_score,
        "contributors": contributors[:3],
        "insight": interpreted["insight"],
        "recommendation": interpreted["recommendation"],
        "source": "WQAD model",
        "processed_at": datetime.now(timezone.utc),
    }
