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
        print("[Water Quality Assessment] No trained model found; using rule-based fallback")
    try:
        with open(_RECS_PATH, encoding="utf-8") as f:
            _recs = json.load(f)
    except Exception:
        _recs = {
            "overall": {"problem": "Water-quality assessment", "action": "Continue monitoring."},
            "DO": {"problem": "Low dissolved oxygen", "action": "Increase aeration immediately"},
            "turbidity": {"problem": "High turbidity", "action": "Partial water change"},
            "pH": {"problem": "pH imbalance", "action": "Adjust pH to 7.0-8.5"},
            "temp": {"problem": "Temperature stress", "action": "Add shade or cooling"},
            "waterLevel": {"problem": "Abnormal water level", "action": "Adjust water level"},
        }
    return _bundle, _recs


def _run_water_quality_assessment(df):
    """Run the Water Quality Assessment using the recent sensor window.

    A classification model determines the overall class, while the assessment
    layer adds trend analysis, insight, and recommendations.
    """
    from features import assess_water_quality
    from assessment_interpreter import enrich_assessment

    bundle, recs = _load_model()
    result = assess_water_quality(df, bundle, recs)
    return enrich_assessment(result, df, recs)


def _fetch_sensor_history(tank_id: str, hours: int = 24):
    """Fetch one tank's canonical history documents from the final schema."""
    import pandas as pd

    db = _get_db()
    cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
    now_utc = datetime.now(timezone.utc)
    rows = []

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
                temp = data.get("temp_avg", data.get("temperature"))
                ph = data.get("pH_avg", data.get("ph_level"))
                do = data.get("DO_avg", data.get("dissolved_oxygen"))
                turb = data.get("turbidity_avg", data.get("turbidity"))
                water = data.get("waterLevel_avg", data.get("water_level"))
                base_values = (temp, ph, do, turb, water)
                if any(v is None or not isinstance(v, (int, float)) or v < 0 for v in base_values):
                    print(f"[Water Quality Assessment] Skipping incomplete/invalid history doc {doc.id}")
                    continue
                rows.append({
                    "timestamp": recorded_at.timestamp(),
                    "temp_avg": temp, "temp_min": data.get("temp_min", temp), "temp_max": data.get("temp_max", temp),
                    "pH_avg": ph, "pH_min": data.get("pH_min", ph), "pH_max": data.get("pH_max", ph),
                    "DO_avg": do, "DO_min": data.get("DO_min", do), "DO_max": data.get("DO_max", do),
                    "turbidity_avg": turb, "turbidity_min": data.get("turbidity_min", turb), "turbidity_max": data.get("turbidity_max", turb),
                    "waterLevel_avg": water, "waterLevel_min": data.get("waterLevel_min", water), "waterLevel_max": data.get("waterLevel_max", water),
                })
        except Exception as e:
            print(f"[Water Quality Assessment] Error fetching {tank_id}/{date_key}: {e}")
        current_day += timedelta(days=1)

    return pd.DataFrame(rows).sort_values("timestamp") if rows else pd.DataFrame()


from firebase_functions import scheduler_fn


def _analyze_tank(tank_id: str) -> None:
    """Run one complete one-hour water-quality assessment for a tank."""
    db = _get_db()
    tank = db.collection("tanks").document(tank_id).get()
    owner_uid = (tank.to_dict() or {}).get("owner_uid", "") if tank.exists else ""
    df = _fetch_sensor_history(tank_id)

    if df.empty or len(df) < 6:
        print(f"[Water Quality Assessment] Insufficient data ({len(df)} rows); at least 6 are required")
        result = {
            "level": "Insufficient",
            "confidence": 0,
            "driver": "N/A",
            "driver_label": "Collecting sensor history",
            "problem": "Not enough data collected yet",
            "insight": "A minimum of six 10-minute history readings is required.",
            "action": "Continue collecting data. The first Water Quality Assessment will be available after about one hour.",
            "concerns": [],
            "secondary_concerns": [],
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    else:
        result = _run_water_quality_assessment(df)
        result["tank_id"] = tank_id
        if owner_uid:
            result["uid"] = owner_uid

    result["ts_epoch"] = int(datetime.now(timezone.utc).timestamp())

    assessments = (db.collection("tanks").document(tank_id)
                   .collection("machine_learning_assessments"))
    assessments.document("current").set(result)

    hist_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    assessments.document(hist_id).set(result)
    print(f"[Water Quality Assessment] Tank {tank_id}: {result['level']} (confidence={result['confidence']}%, driver={result['driver']})")


@scheduler_fn.on_schedule(
    schedule="every 1 hours",
    timezone="Asia/Manila",
    region="asia-southeast1",
)
def run_hourly_wqc(event) -> None:
    """Run the Water Quality Assessment for the assigned tank each hour.

    The exported function name remains stable so existing Firebase schedules
    continue to invoke the same deployment without duplication.
    """
    db = _get_db()
    assignment = db.collection("hardware_system").document("currentOwner").get()
    data = assignment.to_dict() if assignment.exists else None
    tank_id = (data or {}).get("tank_id")
    if not tank_id:
        print("[Water Quality Assessment] No hardware owner/tank assigned; hourly analysis skipped.")
        return
    _analyze_tank(tank_id)
