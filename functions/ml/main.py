import os
import json
from datetime import datetime, timedelta, timezone

# Global state for lazy-loaded model
_bundle = None
_recs = None
_db = None

_MODEL_PATH = os.path.join(os.path.dirname(__file__), "wqc_model.joblib")
_RECS_PATH = os.path.join(os.path.dirname(__file__), "recommendations.json")


def _get_db():
    """Lazy initialize Firestore client (avoids timeout during code loading)."""
    global _db
    if _db is None:
        import firebase_admin

        try:
            firebase_admin.get_app()
        except ValueError:
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
        print("[WQC] No trained model found, will use rule-based fallback")
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


def _predict_wqc(df):
    """Run Water Quality Classification (ML or rule-based) on a sensor DataFrame.

    Thin wrapper around the shared features.predict_wqc() — kept here so
    on_sensor_update() doesn't need to know about model/recs loading.
    """
    from features import predict_wqc

    bundle, recs = _load_model()
    return predict_wqc(df, bundle, recs)


def _fetch_sensor_history(tank_id: str, hours: int = 24):
    """Fetch one tank's canonical history documents from the final schema."""
    import pandas as pd

    db = _get_db()
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    now_utc = datetime.now(timezone.utc)
    rows = []

    # History is partitioned by Manila date: tanks/{tankId}/sensor_readings_history/{date}/entries.
    manila_now = now_utc + timedelta(hours=8)
    manila_cutoff = cutoff + timedelta(hours=8)
    current_day = manila_cutoff.date()
    while current_day <= manila_now.date():
        date_key = current_day.strftime("%Y-%m-%d")
        try:
            docs = (
                db.collection("tanks").document(tank_id)
                .collection("sensor_readings_history").document(date_key)
                .collection("entries").where("recorded_at", ">=", cutoff).get()
            )
            for doc in docs:
                data = doc.to_dict()
                recorded_at = data.get("recorded_at")
                if not recorded_at:
                    continue
                # The ML feature pipeline uses these aggregate-style field names.
                # Each canonical history document is one snapshot, so min/max/avg are equal.
                temp = data.get("temperature", 0.0)
                ph = data.get("ph_level", 0.0)
                do = data.get("dissolved_oxygen", 0.0)
                turb = data.get("turbidity", 0.0)
                water = data.get("water_level", 0.0)
                rows.append({
                    "timestamp": recorded_at.timestamp(),
                    "temp_avg": temp, "temp_min": temp, "temp_max": temp,
                    "pH_avg": ph, "pH_min": ph, "pH_max": ph,
                    "DO_avg": do, "DO_min": do, "DO_max": do,
                    "turbidity_avg": turb, "turbidity_min": turb, "turbidity_max": turb,
                    "waterLevel_avg": water, "waterLevel_min": water, "waterLevel_max": water,
                })
        except Exception as e:
            print(f"[WQC] Error fetching {tank_id}/{date_key}: {e}")
        current_day += timedelta(days=1)

    return pd.DataFrame(rows).sort_values("timestamp") if rows else pd.DataFrame()


from firebase_functions import firestore_fn


@firestore_fn.on_document_written(
    document="tanks/{tankId}/sensor_readings/latest", region="asia-southeast1"
)
def on_sensor_update(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot]]) -> None:
    """Triggered when a tank's canonical latest sensor document is written."""

    after_data = event.data.after.to_dict() if event.data.after else None
    if not after_data:
        return

    tank_id = event.params.get("tankId", "")
    if not tank_id:
        return
    tank = _get_db().collection("tanks").document(tank_id).get()
    owner_uid = (tank.to_dict() or {}).get("owner_uid", "") if tank.exists else ""

    df = _fetch_sensor_history(tank_id)
    db = _get_db()

    if df.empty or len(df) < 36:
        print(f"[WQC] Insufficient data ({len(df)} rows), need at least 36")
        result = {
            "level": "Insufficient",
            "confidence": 0,
            "driver": "N/A",
            "problem": "Not enough data collected yet",
            "insight": "Not enough data collected yet.",
            "action": "Continue collecting data. Need at least 6 hours of readings.",
            "source": "System",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        db.collection("healthRisk").document(tank_id).set(result)
        return

    result = _predict_wqc(df)
    result["tank_id"] = tank_id
    if owner_uid:
        result["uid"] = owner_uid

    db.collection("healthRisk").document(tank_id).set(result)
    print(
        f"[WQC] Classification: {result['level']} (confidence={result['confidence']}%, driver={result['driver']})"
    )
