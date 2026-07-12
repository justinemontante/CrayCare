import os
import json
import numpy as np
import pandas as pd
import joblib
from datetime import datetime, timedelta, timezone
from firebase_admin import initialize_app, firestore, credentials
import functions_framework

_PH_OPTIMAL_MIN = 6.5
_PH_OPTIMAL_MAX = 8.5
_TEMP_MAX = 31.0
_TEMP_MIN = 24.0
_DO_MIN = 5.0
_DO_CRITICAL = 3.0
_TURB_MAX = 25.0

_MODEL_PATH = os.path.join(os.path.dirname(__file__), "csi_model.joblib")
_RECS_PATH = os.path.join(os.path.dirname(__file__), "recommendations.json")

_bundle = None
_recs = None


def _load_model():
    global _bundle, _recs
    if _bundle is not None:
        return _bundle, _recs
    try:
        _bundle = joblib.load(_MODEL_PATH)
    except Exception:
        _bundle = None
        print("[CSI] No trained model found, will use rule-based fallback")
    try:
        with open(_RECS_PATH) as f:
            _recs = json.load(f)
    except Exception:
        _recs = {
            "DO": {
                "problem": "Low dissolved oxygen",
                "action": "Increase aeration immediately",
                "source": "Research-based",
            },
            "turbidity": {
                "problem": "High turbidity",
                "action": "Partial water change",
                "source": "Research-based",
            },
            "pH": {
                "problem": "pH imbalance",
                "action": "Adjust pH to 7.0-8.5",
                "source": "Research-based",
            },
            "temp": {
                "problem": "Temperature stress",
                "action": "Add shade or cooling",
                "source": "Research-based",
            },
            "waterLevel": {
                "problem": "Abnormal water level",
                "action": "Adjust water level",
                "source": "General practice",
            },
        }
    return _bundle, _recs


def _compute_csi_score(df: pd.DataFrame):
    s = pd.DataFrame(index=df.index)
    s["DO"] = np.clip(_DO_MIN - df["DO_min"], 0, None) / _DO_MIN
    s["pH_lo"] = np.clip(_PH_OPTIMAL_MIN - df["pH_min"], 0, None) / 1.5
    s["pH_hi"] = np.clip(df["pH_max"] - _PH_OPTIMAL_MAX, 0, None) / 1.5
    s["temp"] = np.clip(df["temp_max"] - _TEMP_MAX, 0, None) / 4.0
    s["temp_lo"] = np.clip(_TEMP_MIN - df["temp_min"], 0, None) / 4.0
    s["turb"] = np.clip(df["turbidity_max"] - _TURB_MAX, 0, None) / _TURB_MAX
    row_hazard = s.sum(axis=1)
    WIN = 36
    csi_raw = row_hazard.rolling(WIN, min_periods=1).sum()
    csi_score = (
        np.clip(csi_raw / csi_raw.quantile(0.99) * 100, 0, 100)
        if csi_raw.quantile(0.99) > 0
        else csi_raw * 0
    )
    return csi_score


def _classify(score):
    if score < 25:
        return 0, "Low"
    if score < 50:
        return 1, "Moderate"
    if score < 75:
        return 2, "High"
    return 3, "Critical"


def _build_features(df: pd.DataFrame):
    SENSORS = ["temp", "pH", "DO", "turbidity", "waterLevel"]
    base_cols = []
    for s in SENSORS:
        base_cols += [f"{s}_avg", f"{s}_min", f"{s}_max"]
    feat = df[base_cols].copy()
    for s in SENSORS:
        a = df[f"{s}_avg"]
        feat[f"{s}_volatility"] = df[f"{s}_max"] - df[f"{s}_min"]
        feat[f"{s}_roll6h"] = a.rolling(36, min_periods=1).mean()
        feat[f"{s}_roll24h"] = a.rolling(144, min_periods=1).mean()
        feat[f"{s}_trend"] = a.diff().rolling(6, min_periods=1).mean()
    feat["DO_hrs_low"] = (df["DO_min"] < _DO_MIN).rolling(36, min_periods=1).sum() / 6.0
    feat["temp_hrs_hi"] = (df["temp_max"] > _TEMP_MAX).rolling(
        36, min_periods=1
    ).sum() / 6.0
    feat["pH_hrs_bad"] = (
        (df["pH_min"] < _PH_OPTIMAL_MIN) | (df["pH_max"] > _PH_OPTIMAL_MAX)
    ).rolling(36, min_periods=1).sum() / 6.0
    feat = feat.fillna(method="bfill").fillna(0)
    return feat, SENSORS


def _predict_csi(df: pd.DataFrame):
    bundle, recs = _load_model()
    feat, SENSORS = _build_features(df)
    latest = feat.iloc[[-1]]

    if bundle is not None:
        model = bundle["model"]
        FEATURES = bundle["features"]
        missing = set(FEATURES) - set(latest.columns)
        for m in missing:
            latest[m] = 0.0
        latest = latest[FEATURES]
        cls = int(model.predict(latest)[0])
        proba = model.predict_proba(latest)[0]
        confidence = round(proba[cls] * 100)
        labels = ["Low", "Moderate", "High", "Critical"]
        level = labels[cls]

        imp = pd.Series(model.feature_importances_, index=FEATURES)
        driver = max(
            SENSORS, key=lambda s: imp[[c for c in FEATURES if c.startswith(s)]].sum()
        )
    else:
        csi_score = _compute_csi_score(df)
        cls_num, level = _classify(csi_score.iloc[-1])
        confidence = 85
        driver = "DO"
        csi_score_val = float(csi_score.iloc[-1])

    rec = recs.get(driver, recs["DO"])
    return {
        "score": float(csi_score.iloc[-1])
        if bundle is None
        else round(
            float(confidence >= 50) * 75
            + (1 if level == "Critical" else 0) * 25
            + csi_score.iloc[-1] * 0.5
            if False
            else float(proba.argmax() * 25 + proba.max() * 20),
            1,
        )
        if False
        else None,
        "level": level,
        "confidence": confidence,
        "driver": driver,
        "problem": rec["problem"],
        "action": rec["action"],
        "source": rec["source"],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def _fetch_sensor_history(db, uid: str, hours: int = 24) -> pd.DataFrame:
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    docs = (
        db.collection("sensorReadings")
        .document("history")
        .collection(cutoff.strftime("%Y-%m-%d"))
        .where("timestamp", ">=", cutoff.timestamp())
        .order_by("timestamp")
        .get()
    )
    if not docs:
        docs = (
            db.collection("sensorReadings")
            .document("history")
            .collection(cutoff.strftime("%Y-%m-%d"))
            .order_by("timestamp", direction=firestore.Query.DESCENDING)
            .limit(144)
            .get()
        )
    rows = []
    for d in docs:
        data = d.to_dict()
        rows.append(data)
    if not rows:
        return pd.DataFrame()
    df = pd.DataFrame(rows)
    required = {
        "temp_avg",
        "temp_min",
        "temp_max",
        "pH_avg",
        "pH_min",
        "pH_max",
        "DO_avg",
        "DO_min",
        "DO_max",
        "turbidity_avg",
        "turbidity_min",
        "turbidity_max",
        "waterLevel_avg",
        "waterLevel_min",
        "waterLevel_max",
    }
    missing = required - set(df.columns)
    for m in missing:
        df[m] = 0.0
    df = df.sort_values("timestamp")
    return df


@functions_framework.cloud_event
def on_sensor_update(cloud_event):
    try:
        data = cloud_event.data.get("value", {}).get("fields", {})
        affected_doc_path = cloud_event.data.get("value", {}).get("name", "")
    except Exception:
        affected_doc_path = ""
    initialize_app()
    db = firestore.client()

    uid = os.environ.get("TANK_OWNER_UID", "")
    if not uid:
        print("[CSI] TANK_OWNER_UID not set, trying auth...")
        uid = None

    df = _fetch_sensor_history(db, uid or "")
    if df.empty or len(df) < 36:
        print(f"[CSI] Insufficient data ({len(df)} rows), need at least 36")
        result = {
            "score": 0,
            "level": "Insufficient",
            "confidence": 0,
            "driver": "N/A",
            "problem": "Not enough data collected yet",
            "action": "Continue collecting data. Need at least 6 hours of readings.",
            "source": "System",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        db.collection("healthRisk").document("latest").set(result)
        return

    result = _predict_csi(df)
    result["uid"] = uid

    db.collection("healthRisk").document("latest").set(result)
    print(
        f"[CSI] Result: {result['level']} (score={result['score']}, driver={result['driver']})"
    )
