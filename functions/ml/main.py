import os
import json
from datetime import datetime, timedelta, timezone

# Global state for lazy-loaded model
_bundle = None
_recs = None
_db = None

_MODEL_PATH = os.path.join(os.path.dirname(__file__), "csi_model.joblib")
_RECS_PATH = os.path.join(os.path.dirname(__file__), "recommendations.json")


def _get_db():
    """Lazy initialize Firestore client (avoids timeout during code loading)."""
    global _db
    if _db is None:
        import firebase_admin
        if not firebase_admin._apps:
            firebase_admin.initialize_app()
        from firebase_admin import firestore
        _db = firestore.client()
    return _db


def _load_model():
    """Lazy load ML model and recommendations."""
    global _bundle, _recs
    if _bundle is not None:
        return _bundle, _recs
    import joblib
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


def _compute_csi_score(df):
    import numpy as np
    import pandas as pd

    PH_OPTIMAL_MIN = 6.5
    PH_OPTIMAL_MAX = 8.5
    TEMP_MAX = 31.0
    TEMP_MIN = 24.0
    DO_MIN = 5.0
    TURB_MAX = 25.0

    s = pd.DataFrame(index=df.index)
    s["DO"] = np.clip(DO_MIN - df["DO_min"], 0, None) / DO_MIN
    s["pH_lo"] = np.clip(PH_OPTIMAL_MIN - df["pH_min"], 0, None) / 1.5
    s["pH_hi"] = np.clip(df["pH_max"] - PH_OPTIMAL_MAX, 0, None) / 1.5
    s["temp"] = np.clip(df["temp_max"] - TEMP_MAX, 0, None) / 4.0
    s["temp_lo"] = np.clip(TEMP_MIN - df["temp_min"], 0, None) / 4.0
    s["turb"] = np.clip(df["turbidity_max"] - TURB_MAX, 0, None) / TURB_MAX
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


def _build_features(df):
    import numpy as np
    import pandas as pd

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

    PH_OPTIMAL_MIN = 6.5
    PH_OPTIMAL_MAX = 8.5
    TEMP_MAX = 31.0
    DO_MIN = 5.0

    feat["DO_hrs_low"] = (df["DO_min"] < DO_MIN).rolling(36, min_periods=1).sum() / 6.0
    feat["temp_hrs_hi"] = (df["temp_max"] > TEMP_MAX).rolling(
        36, min_periods=1
    ).sum() / 6.0
    feat["pH_hrs_bad"] = (
        (df["pH_min"] < PH_OPTIMAL_MIN) | (df["pH_max"] > PH_OPTIMAL_MAX)
    ).rolling(36, min_periods=1).sum() / 6.0
    feat = feat.bfill().fillna(0)
    return feat, SENSORS


def _predict_csi(df):
    bundle, recs = _load_model()
    feat, SENSORS = _build_features(df)
    latest = feat.iloc[[-1]]

    if bundle is not None:
        import numpy as np
        import pandas as pd

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

        score = round(float(proba.argmax() * 25 + proba.max() * 20), 1)
    else:
        csi_score = _compute_csi_score(df)
        cls_num, level = _classify(csi_score.iloc[-1])
        confidence = 85
        driver = "DO"
        score = round(float(csi_score.iloc[-1]), 1)

    rec = recs.get(driver, recs["DO"])
    return {
        "score": score,
        "level": level,
        "confidence": confidence,
        "driver": driver,
        "problem": rec["problem"],
        "action": rec["action"],
        "source": rec["source"],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def _fetch_sensor_history(hours: int = 24):
    import pandas as pd

    db = _get_db()
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    now_utc = datetime.now(timezone.utc)

    # Collect all date strings in the window (may span multiple days)
    date_set = set()
    cur = cutoff.date()
    while cur <= now_utc.date():
        date_set.add(cur.strftime("%Y-%m-%d"))
        cur += timedelta(days=1)

    rows = []
    for date_str in sorted(date_set):
        try:
            docs = (
                db.collection("sensorReadings")
                .document("history")
                .collection(date_str)
                .order_by("timestamp")
                .get()
            )
            for d in docs:
                data = d.to_dict()
                # Filter to only rows within the actual time window
                ts = data.get("timestamp", 0)
                if isinstance(ts, (int, float)) and ts >= cutoff.timestamp():
                    rows.append(data)
        except Exception as e:
            print(f"[CSI] Error fetching history for {date_str}: {e}")

    # Fallback: if still no rows, grab last 144 docs from today's collection
    if not rows:
        today_str = now_utc.strftime("%Y-%m-%d")
        try:
            from firebase_admin import firestore
            docs = (
                db.collection("sensorReadings")
                .document("history")
                .collection(today_str)
                .order_by("timestamp", direction=firestore.Query.DESCENDING)
                .limit(144)
                .get()
            )
            for d in docs:
                rows.append(d.to_dict())
        except Exception as e:
            print(f"[CSI] Fallback fetch error: {e}")

    if not rows:
        return pd.DataFrame()

    df = pd.DataFrame(rows)
    required = {
        "temp_avg", "temp_min", "temp_max",
        "pH_avg", "pH_min", "pH_max",
        "DO_avg", "DO_min", "DO_max",
        "turbidity_avg", "turbidity_min", "turbidity_max",
        "waterLevel_avg", "waterLevel_min", "waterLevel_max",
    }
    missing = required - set(df.columns)
    for m in missing:
        df[m] = 0.0
    df = df.sort_values("timestamp")
    return df


from firebase_functions import firestore_fn


@firestore_fn.on_document_written(
    document="sensorReadings/latest",
    region="asia-southeast1"
)
def on_sensor_update(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    """Triggered when sensorReadings/latest is written. Runs ML CSI prediction."""

    after_data = event.data.after.to_dict() if event.data.after else None
    if not after_data:
        return

    uid = os.environ.get("TANK_OWNER_UID", "")

    df = _fetch_sensor_history()
    db = _get_db()

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
