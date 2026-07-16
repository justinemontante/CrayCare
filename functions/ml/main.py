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


def _predict_csi(df):
    """Run CSI prediction (ML or rule-based) on a sensor DataFrame.

    Returns a dict with score, level, confidence, driver, recommendation.
    The 0-100 score always comes from the deterministic CSI formula so it
    stays consistent whether the ML model is loaded or not.
    """
    from features import SENSORS, build_features, compute_csi_score, classify, CLASS_NAMES
    from features import DO_MIN, PH_OPTIMAL_MIN, PH_OPTIMAL_MAX, TEMP_MIN, TEMP_MAX, TURB_MAX

    bundle, recs = _load_model()
    feat, _ = build_features(df)
    latest_feat = feat.iloc[[-1]]

    # Always compute the deterministic CSI score — consistent metric
    csi_series = compute_csi_score(df)
    score = round(float(csi_series.iloc[-1]), 1)

    if bundle is not None:
        import numpy as np
        import pandas as pd

        model = bundle["model"]
        FEATURES = bundle["features"]
        model_type = bundle.get("type", "classifier")
        missing = set(FEATURES) - set(latest_feat.columns)
        for m in missing:
            latest_feat[m] = 0.0
        latest_feat = latest_feat[FEATURES]

        if model_type == "regressor":
            # Regressor predicts CSI score directly (0-100)
            pred_score = float(model.predict(latest_feat)[0])
            pred_score = max(0.0, min(100.0, pred_score))
            score = round(pred_score, 1)
            _, level = classify(score)

            # Confidence: high when model agrees with rule-based CSI
            diff = abs(pred_score - float(csi_series.iloc[-1]))
            if diff < 5:
                confidence = 92
            elif diff < 10:
                confidence = 85
            elif diff < 20:
                confidence = 75
            else:
                confidence = 65
        else:
            # Classifier (legacy format)
            raw_pred = model.predict(latest_feat)
            pred_1d = raw_pred.argmax(axis=1) if raw_pred.shape[1] > 1 else raw_pred
            cls = int(pred_1d[0])
            proba = model.predict_proba(latest_feat)[0]
            confidence = round(proba[cls] * 100)
            level = CLASS_NAMES[cls]

        imp = pd.Series(model.feature_importances_, index=FEATURES)
        driver = max(
            SENSORS,
            key=lambda s: imp[[c for c in FEATURES if c.startswith(s)]].sum(),
        )
    else:
        # Rule-based fallback: derive driver from CSI hazard sub-scores
        import numpy as np

        cls_num, level = classify(score)
        confidence = 85

        # Compute per-sensor hazard contributions from the latest row
        last = df.iloc[-1]
        hazards = {
            "DO": float(np.clip(DO_MIN - last["DO_min"], 0, None) / DO_MIN),
            "pH": float(max(
                np.clip(PH_OPTIMAL_MIN - last["pH_min"], 0, None) / 1.5,
                np.clip(last["pH_max"] - PH_OPTIMAL_MAX, 0, None) / 1.5,
            )),
            "temp": float(max(
                np.clip(last["temp_max"] - TEMP_MAX, 0, None) / 4.0,
                np.clip(TEMP_MIN - last["temp_min"], 0, None) / 4.0,
            )),
            "turbidity": float(np.clip(last["turbidity_max"] - TURB_MAX, 0, None) / TURB_MAX),
        }
        driver = max(hazards, key=hazards.get) if max(hazards.values()) > 0 else "DO"

    rec = recs.get(driver, recs["DO"])
    action_key = "critical_action" if level == "Critical" else "action"
    action = rec.get(action_key, rec["action"])
    return {
        "score": score,
        "level": level,
        "confidence": confidence,
        "driver": driver,
        "problem": rec["problem"],
        "action": action,
        "source": rec["source"],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


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
            print(f"[CSI] Error fetching history for {date_str}: {e}")

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
    if uid:
        result["uid"] = uid

    db.collection("healthRisk").document("latest").set(result)
    print(
        f"[CSI] Result: {result['level']} (score={result['score']}, driver={result['driver']})"
    )
