"""Feature engineering and inference for CrayCare WQAD.

WQAD is an unsupervised multivariate anomaly detector. It learns the usual
joint behaviour of sensor readings and temporal changes; it does not use
water-quality thresholds or threshold-generated class labels.
"""

from __future__ import annotations

from datetime import datetime, timezone

SENSORS = ["temp", "pH", "DO", "turbidity", "waterLevel"]
SENSOR_LABELS = {
    "temp": "Temperature", "pH": "pH Level", "DO": "Dissolved Oxygen",
    "turbidity": "Turbidity", "waterLevel": "Water Level",
}
SENSOR_UNITS = {
    "temp": "°C", "pH": "", "DO": "mg/L", "turbidity": "NTU",
    "waterLevel": "cm",
}


def build_anomaly_features(df):
    """Create leakage-safe temporal features from 10-minute sensor windows."""
    import numpy as np
    import pandas as pd

    feat = pd.DataFrame(index=df.index)
    for sensor in SENSORS:
        avg = pd.to_numeric(df[f"{sensor}_avg"], errors="coerce")
        low = pd.to_numeric(df[f"{sensor}_min"], errors="coerce")
        high = pd.to_numeric(df[f"{sensor}_max"], errors="coerce")
        feat[f"{sensor}_avg"] = avg
        feat[f"{sensor}_spread"] = high - low
        feat[f"{sensor}_delta"] = avg.diff()
        feat[f"{sensor}_roll1h_mean"] = avg.rolling(6, min_periods=2).mean()
        feat[f"{sensor}_roll1h_std"] = avg.rolling(6, min_periods=2).std()
        feat[f"{sensor}_roll2h_mean"] = avg.rolling(12, min_periods=3).mean()
        feat[f"{sensor}_roll2h_std"] = avg.rolling(12, min_periods=3).std()
        feat[f"{sensor}_trend30m"] = avg.diff().rolling(3, min_periods=2).mean()
        feat[f"{sensor}_trend1h"] = avg.diff().rolling(6, min_periods=3).mean()
        scale = feat[f"{sensor}_roll2h_std"].clip(lower=1e-6)
        feat[f"{sensor}_baseline_deviation"] = (
            avg - feat[f"{sensor}_roll2h_mean"]
        ) / scale

    if "timestamp" in df:
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


def _contributors(latest, bundle):
    import numpy as np

    centers = bundle.get("robust_centers", {})
    scales = bundle.get("robust_scales", {})
    contributions = []
    for sensor in SENSORS:
        names = [
            f"{sensor}_avg", f"{sensor}_spread", f"{sensor}_delta",
            f"{sensor}_trend30m", f"{sensor}_trend1h",
            f"{sensor}_baseline_deviation",
        ]
        z_values = []
        for name in names:
            center = float(centers.get(name, 0.0))
            scale = max(float(scales.get(name, 1.0)), 1e-6)
            z_values.append(abs((float(latest.get(name, 0.0)) - center) / scale))
        contribution = float(np.mean(sorted(z_values, reverse=True)[:3]))
        trend = float(latest.get(f"{sensor}_trend30m", 0.0))
        deviation = float(latest.get(f"{sensor}_baseline_deviation", 0.0))
        direction_value = trend if abs(trend) > 1e-9 else deviation
        direction = "increasing" if direction_value > 0 else (
            "decreasing" if direction_value < 0 else "stable"
        )
        contributions.append({
            "sensor": sensor, "label": SENSOR_LABELS[sensor],
            "unit": SENSOR_UNITS[sensor],
            "value": round(float(latest.get(f"{sensor}_avg", 0.0)), 3),
            "direction": direction,
            "contribution_score": round(contribution, 3),
        })
    return sorted(contributions, key=lambda item: item["contribution_score"], reverse=True)


def detect_water_quality_anomaly(df, bundle, recommendations):
    """Return a WQAD result for the latest complete sensor window."""
    if bundle is None:
        return {
            "status": "Insufficient", "is_anomaly": False, "anomaly_score": 0.0,
            "driver": "N/A", "driver_label": "Model unavailable",
            "insight": "The anomaly-detection model is not available.",
            "recommendation": "Deploy a trained WQAD model before interpreting sensor patterns.",
            "contributors": [], "source": "Model unavailable",
        }

    features = build_anomaly_features(df)
    expected = bundle["features"]
    latest = features.iloc[[-1]].copy()
    for missing in set(expected) - set(latest.columns):
        latest[missing] = 0.0
    latest = latest[expected]
    model = bundle["model"]
    raw_value = -float(model.decision_function(latest)[0])
    anomaly_score = _percentile_score(raw_value, bundle.get("calibration_scores", []))
    is_anomaly = raw_value >= float(bundle["decision_threshold_raw"])
    contributors = _contributors(latest.iloc[0], bundle)

    from anomaly_interpreter import interpret_anomaly
    interpreted = interpret_anomaly(is_anomaly, anomaly_score, contributors, recommendations)
    return {
        "status": "Unusual" if is_anomaly else "Normal",
        "is_anomaly": is_anomaly,
        "anomaly_score": anomaly_score,
        "driver": contributors[0]["sensor"] if contributors else "overall",
        "driver_label": contributors[0]["label"] if contributors else "Combined water pattern",
        "driver_value": contributors[0]["value"] if contributors else None,
        "driver_unit": contributors[0]["unit"] if contributors else "",
        "contributors": contributors[:3],
        "insight": interpreted["insight"],
        "recommendation": interpreted["recommendation"],
        "source": bundle.get("model_version", "WQAD model"),
        "model_algorithm": bundle.get("algorithm", "IsolationForest"),
        "model_version": bundle.get("model_version", ""),
        "training_data_origin": bundle.get("training_data_origin", "unknown"),
        "training_label_origin": "none_unsupervised",
        "model_feature_count": len(expected),
        "analysis_window_minutes": bundle.get("analysis_window_minutes", 120),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
