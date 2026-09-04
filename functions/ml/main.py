"""Scheduled backend for CrayCare Water Quality Anomaly Detection (WQAD)."""

import json
import math
import os
from datetime import datetime, timedelta, timezone

from firebase_functions import options, scheduler_fn

_bundle = None
_recommendations = None
_db = None
_ROOT = os.path.dirname(__file__)
_MODEL_PATH = os.path.join(_ROOT, "wqad_model.joblib")
_RECOMMENDATIONS_PATH = os.path.join(_ROOT, "anomaly_recommendations.json")


def _get_db():
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


def _load_wqad():
    global _bundle, _recommendations
    if _recommendations is None:
        with open(_RECOMMENDATIONS_PATH, encoding="utf-8") as handle:
            _recommendations = json.load(handle)
    if _bundle is None:
        import joblib
        try:
            _bundle = joblib.load(_MODEL_PATH)
        except Exception as error:
            print(f"[WQAD] Model unavailable: {error}")
    return _bundle, _recommendations


def _run_water_quality_anomaly_detection(frame):
    from anomaly_features import detect_water_quality_anomaly
    bundle, recommendations = _load_wqad()
    return detect_water_quality_anomaly(frame, bundle, recommendations)


def _valid_history_row(row):
    for sensor in ("temp", "pH", "DO", "turbidity", "waterLevel"):
        keys = (f"{sensor}_min", f"{sensor}_avg", f"{sensor}_max")
        values = [row.get(key) for key in keys]
        if any(value is None or not isinstance(value, (int, float))
               or not math.isfinite(float(value)) or float(value) < 0 for value in values):
            return False
        minimum, average, maximum = map(float, values)
        if not minimum <= average <= maximum:
            return False
    return True


def _fetch_sensor_history(tank_id, hours=24):
    import pandas as pd
    db = _get_db()
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(hours=hours)
    rows = []
    current_day = (cutoff + timedelta(hours=8)).date()
    last_day = (now + timedelta(hours=8)).date()
    while current_day <= last_day:
        date_key = current_day.strftime("%Y-%m-%d")
        try:
            docs = (db.collection("tanks").document(tank_id)
                    .collection("sensor_readings_history").document(date_key)
                    .collection("entries").where("recorded_at", ">=", cutoff).get())
            for doc in docs:
                data = doc.to_dict()
                recorded_at = data.get("recorded_at")
                if recorded_at is None:
                    continue
                temp = data.get("temp_avg", data.get("temperature"))
                ph = data.get("pH_avg", data.get("ph_level"))
                dissolved_oxygen = data.get("DO_avg", data.get("dissolved_oxygen"))
                turbidity = data.get("turbidity_avg", data.get("turbidity"))
                water_level = data.get("waterLevel_avg", data.get("water_level"))
                row = {
                    "timestamp": recorded_at.timestamp(),
                    "temp_avg": temp, "temp_min": data.get("temp_min", temp), "temp_max": data.get("temp_max", temp),
                    "pH_avg": ph, "pH_min": data.get("pH_min", ph), "pH_max": data.get("pH_max", ph),
                    "DO_avg": dissolved_oxygen, "DO_min": data.get("DO_min", dissolved_oxygen), "DO_max": data.get("DO_max", dissolved_oxygen),
                    "turbidity_avg": turbidity, "turbidity_min": data.get("turbidity_min", turbidity), "turbidity_max": data.get("turbidity_max", turbidity),
                    "waterLevel_avg": water_level, "waterLevel_min": data.get("waterLevel_min", water_level), "waterLevel_max": data.get("waterLevel_max", water_level),
                }
                if _valid_history_row(row):
                    rows.append(row)
                else:
                    print(f"[WQAD] Skipping invalid history document {doc.id}")
        except Exception as error:
            print(f"[WQAD] History read failed for {tank_id}/{date_key}: {error}")
        current_day += timedelta(days=1)
    return pd.DataFrame(rows).sort_values("timestamp") if rows else pd.DataFrame()


def _insufficient_result(data_status):
    stale = data_status == "stale"
    return {
        "status": "Insufficient",
        "is_anomaly": False,
        "anomaly_score": 0.0,
        "driver": "N/A",
        "driver_label": "Sensor history is stale" if stale else "Collecting sensor history",
        "driver_value": None,
        "driver_unit": "",
        "contributors": [],
        "insight": (
            "The latest sensor record is over 20 minutes old."
            if stale else
            "At least twelve continuous 10-minute readings are required to establish the current two-hour pattern."
        ),
        "recommendation": (
            "Check ESP32 connectivity and wait for fresh, continuous sensor history."
            if stale else
            "Continue collecting calibrated sensor data."
        ),
        "source": "Stale sensor history" if stale else "Insufficient data",
        "model_algorithm": "Not applied",
        "model_version": "",
        "training_data_origin": "none",
        "training_label_origin": "none_unsupervised",
        "model_feature_count": 0,
        "analysis_window_minutes": 120,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def _analyze_tank(tank_id):
    db = _get_db()
    tank_snapshot = db.collection("tanks").document(tank_id).get()
    owner_uid = (tank_snapshot.to_dict() or {}).get("owner_uid", "") if tank_snapshot.exists else ""
    frame = _fetch_sensor_history(tank_id)
    from anomaly_window import anomaly_window
    now = datetime.now(timezone.utc)
    frame, data_status, source_at = anomaly_window(frame, now.timestamp())
    result = (_run_water_quality_anomaly_detection(frame)
              if data_status == "ready" else _insufficient_result(data_status))
    result["data_status"] = data_status
    result["source_recorded_at"] = (
        datetime.fromtimestamp(source_at, timezone.utc).isoformat() if source_at is not None else None
    )
    result["source_age_seconds"] = (
        max(0, int(now.timestamp() - source_at)) if source_at is not None else None
    )
    result["tank_id"] = tank_id
    if owner_uid:
        result["uid"] = owner_uid
    result["ts_epoch"] = int(now.timestamp())

    collection = (db.collection("tanks").document(tank_id)
                  .collection("water_quality_anomaly_detections"))
    collection.document("current").set(result)
    collection.document(now.strftime("%Y%m%dT%H%M%S")).set(result)
    print(f"[WQAD] Tank {tank_id}: {result['status']} (score={result['anomaly_score']}, driver={result['driver']})")


@scheduler_fn.on_schedule(
    schedule="every 1 hours",
    timezone="Asia/Manila",
    region="asia-southeast1",
    memory=options.MemoryOption.MB_512,
)
def run_hourly_wqad(event) -> None:
    """Run WQAD for the single active hardware assignment."""
    db = _get_db()
    assignment = db.collection("hardware_system").document("currentOwner").get()
    data = assignment.to_dict() if assignment.exists else {}
    uid, tank_id = data.get("uid"), data.get("tank_id")
    if not uid or not tank_id:
        print("[WQAD] No hardware owner/tank assigned; skipped.")
        return
    user_snapshot = db.collection("users").document(str(uid)).get()
    if not user_snapshot.exists:
        print("[WQAD] Assigned owner profile is missing; skipped.")
        return
    user = user_snapshot.to_dict() or {}
    tank_snapshot = db.collection("tanks").document(str(tank_id)).get()
    tank = tank_snapshot.to_dict() if tank_snapshot.exists else {}
    if (str(user.get("role", "owner")).lower() != "owner"
            or str(user.get("status", "active")).lower() != "active"
            or str(tank.get("owner_uid", "")) != str(uid)):
        print("[WQAD] Assignment is not an active owner/tank pair; skipped.")
        return
    _analyze_tank(str(tank_id))
