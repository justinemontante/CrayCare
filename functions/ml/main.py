"""History-record-triggered CrayCare Water Quality Anomaly Detection (WQAD)."""

import json
import math
import os
from datetime import datetime, timedelta, timezone

from firebase_functions import firestore_fn, options

_bundle = None
_recommendations = None
_db = None
_ROOT = os.path.dirname(__file__)
_MODEL_PATH = os.path.join(_ROOT, "trained_wqad_model.joblib")
_RECOMMENDATIONS_PATH = os.path.join(_ROOT, "anomaly_recommendations.json")
_WQAD_SENSORS = ["temp", "pH", "DO", "turbidity"]
_HISTORY_FIELDS = {
    "temp": ("temp_avg", "temperature"),
    "pH": ("pH_avg", "ph_level"),
    "DO": ("DO_avg", "dissolved_oxygen"),
    "turbidity": ("turbidity_avg", "turbidity"),
}


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
            loaded = joblib.load(_MODEL_PATH)
            if (not isinstance(loaded, dict)
                    or loaded.get("feature_version") != 3
                    or loaded.get("algorithm") != "IsolationForest"
                    or loaded.get("sensors") != _WQAD_SENSORS):
                raise ValueError("The deployed WQAD artifact is not the current four-sensor model.")
            _bundle = loaded
        except Exception as error:
            print(f"[WQAD] Model unavailable: {error}")
    return _bundle, _recommendations


def _run_water_quality_anomaly_detection(frame):
    from anomaly_features import detect_water_quality_anomaly

    bundle, recommendations = _load_wqad()
    return detect_water_quality_anomaly(frame, bundle, recommendations)


def _valid_history_row(row, sensors=None):
    sensors = list(sensors or _WQAD_SENSORS)
    for sensor in sensors:
        fields = _HISTORY_FIELDS.get(sensor)
        if fields is None:
            return False
        value = next((row.get(key) for key in fields if row.get(key) is not None), None)
        if (
            value is None
            or not isinstance(value, (int, float))
            or not math.isfinite(float(value))
            or float(value) < 0
        ):
            return False
    return True


def _timestamp_seconds(value):
    """Normalize Firestore/legacy timestamp representations to Unix seconds."""
    if value is None:
        return None
    if isinstance(value, datetime):
        normalized = (
            value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
        )
        return normalized.timestamp()
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        numeric = float(value)
        if not math.isfinite(numeric) or numeric <= 0:
            return None
        # Legacy exports may contain epoch milliseconds instead of seconds.
        return numeric / 1000.0 if numeric >= 100_000_000_000 else numeric
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            numeric = float(text)
        except ValueError:
            numeric = None
        if numeric is not None:
            return _timestamp_seconds(numeric)
        try:
            normalized_text = text[:-1] + "+00:00" if text.endswith("Z") else text
            parsed = datetime.fromisoformat(normalized_text)
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            return parsed.timestamp()
        except ValueError:
            return None
    return None


def _fetch_sensor_history(tank_id, hours=2.5, sensors=None):
    import pandas as pd

    db = _get_db()
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(hours=hours)
    cutoff_seconds = cutoff.timestamp()
    latest_allowed_seconds = now.timestamp() + 60.0
    rows = []
    current_day = (cutoff + timedelta(hours=8)).date()
    last_day = (now + timedelta(hours=8)).date()
    while current_day <= last_day:
        date_key = current_day.strftime("%Y-%m-%d")
        try:
            # Canonical ESP history uses Firestore timestamps. Filter on the
            # server so one event does not read every record in a whole day.
            docs = (
                db.collection("tanks")
                .document(tank_id)
                .collection("sensor_readings_history")
                .document(date_key)
                .collection("entries")
                .where("recorded_at", ">=", cutoff)
                .get()
            )
            for doc in docs:
                try:
                    data = doc.to_dict() or {}
                    recorded_seconds = _timestamp_seconds(data.get("recorded_at"))
                    if recorded_seconds is None:
                        print(
                            f"[WQAD] Skipping history document {doc.id} with invalid timestamp"
                        )
                        continue
                    if (
                        recorded_seconds < cutoff_seconds
                        or recorded_seconds > latest_allowed_seconds
                    ):
                        continue

                    temp = data.get("temperature", data.get("temp_avg"))
                    ph = data.get("ph_level", data.get("pH_avg"))
                    dissolved_oxygen = data.get("dissolved_oxygen", data.get("DO_avg"))
                    turbidity = data.get("turbidity", data.get("turbidity_avg"))
                    row = {
                        "timestamp": recorded_seconds,
                        "temp_avg": temp,
                        "pH_avg": ph,
                        "DO_avg": dissolved_oxygen,
                        "turbidity_avg": turbidity,
                    }
                    if _valid_history_row(row, sensors=sensors):
                        rows.append(row)
                    else:
                        print(f"[WQAD] Skipping invalid history document {doc.id}")
                except Exception as error:
                    print(
                        f"[WQAD] Skipping malformed history document {doc.id}: {error}"
                    )
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
        "contributors": [],
        "insight": (
            "The latest sensor record is over 20 minutes old."
            if stale
            else "A continuous two-hour window of valid sensor readings is needed."
        ),
        "recommendation": (
            "Check ESP32 connectivity and wait for enough fresh sensor readings."
            if stale
            else "Continue collecting calibrated sensor data."
        ),
        "source": "Stale sensor history" if stale else "Insufficient data",
    }


def _persist_history_result(db, tank_id, now, result, source_id=None):
    """Append one result; source-keyed creates make event retries idempotent."""
    detection_id = source_id or now.strftime("%Y%m%dT%H%M%S")
    history = (
        db.collection("tanks")
        .document(tank_id)
        .collection("water_quality_anomaly_detection_history")
    )
    if source_id:
        from google.api_core.exceptions import AlreadyExists

        try:
            history.document(detection_id).create(result)
        except AlreadyExists:
            print(f"[WQAD] Source {source_id} already analyzed; skipped duplicate.")
            return None
    else:
        history.document(detection_id).set(result)
    return detection_id


def _analyze_tank(tank_id, source_id=None, source_at=None):
    db = _get_db()
    bundle, _ = _load_wqad()
    required_sensors = list(bundle.get("sensors", _WQAD_SENSORS)) if bundle else _WQAD_SENSORS
    if required_sensors != _WQAD_SENSORS:
        raise ValueError("Deployed WQAD model must use exactly four water-quality sensors.")
    tank_snapshot = db.collection("tanks").document(tank_id).get()
    owner_uid = (
        (tank_snapshot.to_dict() or {}).get("owner_uid", "")
        if tank_snapshot.exists
        else ""
    )
    frame = _fetch_sensor_history(tank_id, sensors=required_sensors)
    from anomaly_window import anomaly_window

    now = datetime.now(timezone.utc)
    frame, data_status, latest_at = anomaly_window(frame, now.timestamp())
    if source_at is not None and (latest_at is None or latest_at > source_at + 1):
        print("[WQAD] A newer sensor record is already available; skipped old event.")
        return
    result = (
        _run_water_quality_anomaly_detection(frame)
        if data_status == "ready"
        else _insufficient_result(data_status)
    )
    result["tank_id"] = tank_id
    if owner_uid:
        result["uid"] = owner_uid
    result["processed_at"] = now
    if latest_at is not None:
        result["source_recorded_at"] = datetime.fromtimestamp(latest_at, timezone.utc)

    detection_id = _persist_history_result(db, tank_id, now, result, source_id)
    if detection_id is None:
        return
    print(
        f"[WQAD] Tank {tank_id}: {result['status']} "
        f"(score={result['anomaly_score']}, "
        f"main_sensor={result['contributors'][0]['sensor'] if result['contributors'] else 'N/A'})"
    )
    if source_id is None:
        _prune_history(db, tank_id, now)


def _prune_history(db, tank_id, now, retain_days=30, max_deletes=100):
    """Prune old results during an explicit manual diagnostic run.

    New results are written only to the dedicated history collection. Old
    timestamped records in the former collection are pruned during transition;
    its legacy `current` document is retained but is no longer read or updated.
    Pruning failures are logged so they cannot break detection.
    """
    try:
        cutoff = now - timedelta(days=retain_days)
        tank = db.collection("tanks").document(tank_id)
        collections = [
            tank.collection("water_quality_anomaly_detection_history"),
            tank.collection("water_quality_anomaly_detections"),
        ]
        deleted = 0
        for collection in collections:
            if deleted >= max_deletes:
                break
            for doc in collection.where("processed_at", "<", cutoff).limit(max_deletes - deleted).get():
                if deleted >= max_deletes:
                    break
                if doc.id != "current":
                    doc.delete()
                    deleted += 1
        if deleted:
            print(f"[WQAD] Pruned {deleted} history docs for {tank_id}.")
    except Exception as error:
        print(f"[WQAD] History prune failed for {tank_id}: {error}")


@firestore_fn.on_document_created(
    document="tanks/{tank_id}/sensor_readings_history/{date}/entries/{entry_id}",
    region="asia-southeast1",
    memory=options.MemoryOption.MB_512,
)
def run_wqad_analysis(event) -> None:
    """Analyze fresh history for the active tank once per captured record."""
    if event.data is None:
        return
    data = event.data.to_dict() or {}
    tank_id = event.params["tank_id"]
    source_at = _timestamp_seconds(data.get("recorded_at"))
    now = datetime.now(timezone.utc).timestamp()
    if source_at is None or source_at > now + 60 or now - source_at > 20 * 60:
        print("[WQAD] Invalid, future, or offline-backfilled history; skipped.")
        return
    owner = _active_assignment(tank_id)
    if owner is None:
        return
    uid, assignment = owner
    assigned_at = _timestamp_seconds(assignment.get("assigned_at"))
    source_assignment = data.get("source_assignment_at_ms")
    if (
        assigned_at is None
        or source_at < assigned_at
        or (data.get("source_tank_id") is not None and data["source_tank_id"] != tank_id)
        or (data.get("source_owner_uid") is not None and data["source_owner_uid"] != uid)
        or (source_assignment is not None and source_assignment != int(assigned_at * 1000))
    ):
        print("[WQAD] History does not match the current hardware assignment; skipped.")
        return
    source_id = f"{round(source_at * 1000):013d}_{event.params['entry_id']}"
    _analyze_tank(tank_id, source_id=source_id, source_at=source_at)


def run_wqad_now() -> None:
    """Run the same WQAD flow from a local/manual entry point."""
    _process_assigned_tank()


def _active_assignment(expected_tank_id=None):
    """Return the validated active owner and assignment for one tank."""
    db = _get_db()
    assignment = db.collection("hardware_system").document("currentOwner").get()
    data = assignment.to_dict() if assignment.exists else {}
    uid, tank_id = data.get("uid"), data.get("tank_id")
    if not uid or not tank_id:
        print("[WQAD] No hardware owner/tank assigned; skipped.")
        return None
    if expected_tank_id is not None and str(tank_id) != str(expected_tank_id):
        print("[WQAD] History belongs to a non-active tank; skipped.")
        return None
    user_snapshot = db.collection("users").document(str(uid)).get()
    if not user_snapshot.exists:
        print("[WQAD] Assigned owner profile is missing; skipped.")
        return None
    user = user_snapshot.to_dict() or {}
    tank_snapshot = db.collection("tanks").document(str(tank_id)).get()
    tank = tank_snapshot.to_dict() if tank_snapshot.exists else {}
    if (
        str(user.get("role", "owner")).lower() != "owner"
        or str(user.get("status", "active")).lower() != "active"
        or str(tank.get("owner_uid", "")) != str(uid)
    ):
        print("[WQAD] Assignment is not an active owner/tank pair; skipped.")
        return None
    return str(uid), data


def _process_assigned_tank() -> None:
    """Manual local analysis entry point, retained for diagnostic runs."""
    owner = _active_assignment()
    if owner is not None:
        _analyze_tank(str(owner[1]["tank_id"]))
