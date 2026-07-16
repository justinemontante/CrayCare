import os
import json
from datetime import datetime, timedelta, timezone

# Global state for lazy-loaded model
_bundle = None
_recs = None
_db = None

_MODEL_PATH = os.path.join(os.path.dirname(__file__), "wqri_model.joblib")
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
        print("[WQRI] No trained model found, will use rule-based fallback")
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


def _predict_wqri(df):
    """Run WQRI prediction (ML or rule-based) on a sensor DataFrame.

    Thin wrapper around the shared features.predict_wqri() — kept here so
    on_sensor_update() doesn't need to know about model/recs loading.
    """
    from features import predict_wqri

    bundle, recs = _load_model()
    return predict_wqri(df, bundle, recs)


def _fetch_sensor_history(hours: int = 24):
    """Fetch sensor readings from Firestore for the last N hours.

    Uses Firestore .where() filtering to minimise data transfer.
    """
    import pandas as pd
    from firebase_admin import firestore

    db = _get_db()
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    now_utc = datetime.now(timezone.utc)
    cutoff_ts = cutoff.timestamp()

    # Collect all date strings in the window (may span multiple days)
    date_set = set()
    cur = cutoff.date()
    while cur <= now_utc.date():
        date_set.add(cur.strftime("%Y-%m-%d"))
        cur += timedelta(days=1)

    rows = []
    for date_str in sorted(date_set):
        try:
            # Use indexed Firestore filter instead of fetching everything
            docs = (
                db.collection("sensorReadings")
                .document("history")
                .collection(date_str)
                .where("timestamp", ">=", cutoff_ts)
                .order_by("timestamp")
                .get()
            )
            for d in docs:
                rows.append(d.to_dict())
        except Exception as e:
            print(f"[WQRI] Error fetching history for {date_str}: {e}")

    # Fallback: grab the most recent 144 rows from today's collection
    if not rows:
        today_str = now_utc.strftime("%Y-%m-%d")
        try:
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
            print(f"[WQRI] Fallback fetch error: {e}")

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
    """Triggered when sensorReadings/latest is written. Runs ML WQRI prediction."""

    after_data = event.data.after.to_dict() if event.data.after else None
    if not after_data:
        return

    uid = os.environ.get("TANK_OWNER_UID", "")

    df = _fetch_sensor_history()
    db = _get_db()

    if df.empty or len(df) < 36:
        print(f"[WQRI] Insufficient data ({len(df)} rows), need at least 36")
        result = {
            "score": 0,
            "level": "Insufficient",
            "confidence": 0,
            "driver": "N/A",
            "problem": "Not enough data collected yet",
            "insight": "Not enough data collected yet.",
            "action": "Continue collecting data. Need at least 6 hours of readings.",
            "source": "System",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        db.collection("healthRisk").document("latest").set(result)
        return

    result = _predict_wqri(df)
    if uid:
        result["uid"] = uid

    db.collection("healthRisk").document("latest").set(result)
    print(
        f"[WQRI] Result: {result['level']} (score={result['score']}, driver={result['driver']})"
    )
