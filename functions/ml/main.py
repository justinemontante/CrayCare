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
                # The ESP now writes 10-min window aggregates (min/max/avg), so
                # volatility/trend features get a REAL signal. Fall back to the
                # snapshot value for legacy entries where min/max/avg are absent.
                # Never convert a missing sensor into numeric zero: zero is a
                # real, often critical, measurement (especially for DO). A WQC
                # sample is usable only when all five required sensors exist.
                temp = data.get("temp_avg", data.get("temperature"))
                ph = data.get("pH_avg", data.get("ph_level"))
                do = data.get("DO_avg", data.get("dissolved_oxygen"))
                turb = data.get("turbidity_avg", data.get("turbidity"))
                water = data.get("waterLevel_avg", data.get("water_level"))
                base_values = (temp, ph, do, turb, water)
                if any(v is None or not isinstance(v, (int, float)) or v < 0 for v in base_values):
                    print(f"[WQC] Skipping incomplete/invalid history doc {doc.id}")
                    continue
                temp_min = data.get("temp_min", temp)
                temp_max = data.get("temp_max", temp)
                ph_min = data.get("pH_min", ph)
                ph_max = data.get("pH_max", ph)
                do_min = data.get("DO_min", do)
                do_max = data.get("DO_max", do)
                turb_min = data.get("turbidity_min", turb)
                turb_max = data.get("turbidity_max", turb)
                water_min = data.get("waterLevel_min", water)
                water_max = data.get("waterLevel_max", water)
                rows.append({
                    "timestamp": recorded_at.timestamp(),
                    "temp_avg": temp, "temp_min": temp_min, "temp_max": temp_max,
                    "pH_avg": ph, "pH_min": ph_min, "pH_max": ph_max,
                    "DO_avg": do, "DO_min": do_min, "DO_max": do_max,
                    "turbidity_avg": turb, "turbidity_min": turb_min, "turbidity_max": turb_max,
                    "waterLevel_avg": water, "waterLevel_min": water_min, "waterLevel_max": water_max,
                })
        except Exception as e:
            print(f"[WQC] Error fetching {tank_id}/{date_key}: {e}")
        current_day += timedelta(days=1)

    return pd.DataFrame(rows).sort_values("timestamp") if rows else pd.DataFrame()


from firebase_functions import scheduler_fn


def _analyze_tank(tank_id: str) -> None:
    """Run one complete 1-hour water-quality assessment for a tank."""
    db = _get_db()
    tank = db.collection("tanks").document(tank_id).get()
    owner_uid = (tank.to_dict() or {}).get("owner_uid", "") if tank.exists else ""
    df = _fetch_sensor_history(tank_id)

    if df.empty or len(df) < 6:
        print(f"[WQC] Insufficient data ({len(df)} rows), need at least 6")
        result = {
            "level": "Insufficient",
            "confidence": 0,
            "driver": "N/A",
            "driver_label": "Collecting sensor history",
            "problem": "Not enough data collected yet",
            "insight": "A minimum of six 10-minute history readings is required.",
            "action": "Continue collecting data. The first assessment will be available after about one hour.",
            "source": "System",
            "samples_analyzed": len(df),
            "required_samples": 6,
            "analysis_mode": "Waiting for one-hour history",
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    else:
        result = _predict_wqc(df)
        result["samples_analyzed"] = len(df)
        result["required_samples"] = 6
        result["tank_id"] = tank_id
        if owner_uid:
            result["uid"] = owner_uid

    (db.collection("tanks").document(tank_id)
       .collection("ml_predictions").document("current").set(result))
    print(f"[WQC] Tank {tank_id}: {result['level']} (confidence={result['confidence']}%, driver={result['driver']})")


@scheduler_fn.on_schedule(
    schedule="every 1 hours",
    timezone="Asia/Manila",
    region="asia-southeast1",
)
def run_hourly_wqc(event) -> None:
    """Analyze the one currently assigned ESP/tank once per hour."""
    db = _get_db()
    assignment = db.collection("hardware_system").document("currentOwner").get()
    data = assignment.to_dict() if assignment.exists else None
    tank_id = (data or {}).get("tank_id")
    if not tank_id:
        print("[WQC] No hardware owner/tank assigned; hourly analysis skipped.")
        return
    _analyze_tank(tank_id)

