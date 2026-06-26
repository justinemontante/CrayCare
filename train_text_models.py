"""
train_text_models.py
Trains two ML classifiers for CrayAI text generation:

1. Insight Classifier     → predicts insight type (OPTIMAL, COMBO_*, ALL_CRITICAL, WARNING_GENERAL, CRITICAL_GENERAL)
2. Recommendation Classifier → predicts recommendation type (OPTIMAL, COMBO_*, ACTION_NEEDED, INSPECT, WARNING_SOME)

Input features (6 dims): 5 sensor statuses + 1 overall status
Each status = OPTIMAL(0) / WARNING(1) / CRITICAL(2)

Run: python train_text_models.py
"""

import itertools, pickle, os
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import cross_val_score

STATUS_MAP = {"OPTIMAL": 0, "WARNING": 1, "CRITICAL": 2}
SENSORS = ["temp", "ph", "do", "turb", "wl"]
SENSOR_STATUS_KEYS = [f"{s}_status" for s in SENSORS]
FEATURE_COLS = [
    "temp_status",
    "ph_status",
    "do_status",
    "turb_status",
    "wl_status",
    "overall_status",
]

INSIGHT_LABEL_NAMES = {
    0: "OPTIMAL",
    1: "COMBO_TEMP_DO",
    2: "COMBO_PH_DO",
    3: "COMBO_TURB_DO",
    4: "COMBO_TEMP_TURB",
    5: "COMBO_PH_TURB",
    6: "COMBO_PH_DO_ALK",
    7: "ALL_CRITICAL",
    8: "WARNING_GENERAL",
    9: "CRITICAL_GENERAL",
}

REC_LABEL_NAMES = {
    0: "OPTIMAL",
    1: "COMBO_TEMP_DO",
    2: "COMBO_PH_DO",
    3: "COMBO_TURB_DO",
    4: "COMBO_TEMP_TURB",
    5: "COMBO_PH_TURB",
    6: "COMBO_PH_DO_ALK",
    7: "ACTION_NEEDED",
    8: "INSPECT",
    9: "WARNING_SOME",
}


def sensor_statuses_to_features(sensor_statuses, overall_status):
    return np.array(
        [STATUS_MAP[sensor_statuses.get(sk, "OPTIMAL")] for sk in SENSOR_STATUS_KEYS]
        + [
            0
            if overall_status == "OPTIMAL"
            else (1 if overall_status == "WARNING" else 2)
        ]
    )


def make_sensor_statuses(combo):
    return {
        f"{s}_status": ["OPTIMAL", "WARNING", "CRITICAL"][v]
        for s, v in zip(SENSORS, combo)
    }


def get_insight_label_id(overall_status, sensor_statuses):
    if overall_status == "OPTIMAL":
        return 0

    temp_s = sensor_statuses.get("temp_status", "OPTIMAL")
    ph_s = sensor_statuses.get("ph_status", "OPTIMAL")
    do_s = sensor_statuses.get("do_status", "OPTIMAL")
    turb_s = sensor_statuses.get("turb_status", "OPTIMAL")

    if temp_s != "OPTIMAL" and do_s != "OPTIMAL":
        return 1  # COMBO_TEMP_DO
    if ph_s != "OPTIMAL" and do_s != "OPTIMAL":
        return 2  # COMBO_PH_DO
    if turb_s != "OPTIMAL" and do_s != "OPTIMAL":
        return 3  # COMBO_TURB_DO
    if temp_s != "OPTIMAL" and turb_s != "OPTIMAL":
        return 4  # COMBO_TEMP_TURB
    if ph_s != "OPTIMAL" and turb_s != "OPTIMAL":
        return 5  # COMBO_PH_TURB
    if ph_s != "OPTIMAL" and do_s != "OPTIMAL":
        return 6  # COMBO_PH_DO_ALK

    critical_count = sum(
        1
        for s in [
            temp_s,
            ph_s,
            do_s,
            turb_s,
            sensor_statuses.get("wl_status", "OPTIMAL"),
        ]
        if s == "CRITICAL"
    )

    if critical_count == 5:
        return 7  # ALL_CRITICAL
    if overall_status == "WARNING":
        return 8  # WARNING_GENERAL
    return 9  # CRITICAL_GENERAL


def get_rec_label_id(overall_status, sensor_statuses):
    if overall_status == "OPTIMAL":
        return 0

    temp_s = sensor_statuses.get("temp_status", "OPTIMAL")
    ph_s = sensor_statuses.get("ph_status", "OPTIMAL")
    do_s = sensor_statuses.get("do_status", "OPTIMAL")
    turb_s = sensor_statuses.get("turb_status", "OPTIMAL")
    wl_s = sensor_statuses.get("wl_status", "OPTIMAL")

    if temp_s != "OPTIMAL" and do_s != "OPTIMAL":
        return 1  # COMBO_TEMP_DO
    if ph_s != "OPTIMAL" and do_s != "OPTIMAL":
        return 2  # COMBO_PH_DO
    if turb_s != "OPTIMAL" and do_s != "OPTIMAL":
        return 3  # COMBO_TURB_DO
    if temp_s != "OPTIMAL" and turb_s != "OPTIMAL":
        return 4  # COMBO_TEMP_TURB
    if ph_s != "OPTIMAL" and turb_s != "OPTIMAL":
        return 5  # COMBO_PH_TURB
    if ph_s != "OPTIMAL" and do_s != "OPTIMAL":
        return 6  # COMBO_PH_DO_ALK

    bitmask = 0
    if turb_s == "CRITICAL":
        bitmask |= 1 << 0
    if turb_s == "WARNING":
        bitmask |= 1 << 1
    if do_s == "CRITICAL":
        bitmask |= 1 << 2
    if do_s == "WARNING":
        bitmask |= 1 << 3
    if ph_s == "CRITICAL":
        bitmask |= 1 << 4
    if ph_s == "WARNING":
        bitmask |= 1 << 5
    if temp_s == "CRITICAL":
        bitmask |= 1 << 6
    if temp_s == "WARNING":
        bitmask |= 1 << 7
    if wl_s == "CRITICAL":
        bitmask |= 1 << 8
    if wl_s == "WARNING":
        bitmask |= 1 << 9

    if bitmask & 0x155:
        return 7  # ACTION_NEEDED
    if bitmask == 0:
        return 8  # INSPECT
    return 9  # WARNING_SOME


def main():
    # ── Generate training data ─────────────────────────────────────
    print("[1] Generating training data (3^5 = 243 sensor status combinations)...")

    data = []
    for combo in itertools.product([0, 1, 2], repeat=5):
        sensor_statuses = make_sensor_statuses(combo)

        if all(v == 0 for v in combo):
            overall_statuses = ["OPTIMAL", "WARNING", "CRITICAL"]
        else:
            overall_statuses = []
            if sum(1 for v in combo if v > 0) == 1:
                overall_statuses.append("WARNING")
            overall_statuses.append("CRITICAL")

        for overall_status in overall_statuses:
            features = sensor_statuses_to_features(sensor_statuses, overall_status)
            row = dict(zip(FEATURE_COLS, features))
            row["insight_label"] = get_insight_label_id(overall_status, sensor_statuses)
            row["rec_label"] = get_rec_label_id(overall_status, sensor_statuses)
            data.append(row)

    df = pd.DataFrame(data)
    print(f"   {len(df)} samples")
    print(f"   Insight labels: {sorted(df['insight_label'].unique())}")
    print(f"   Rec labels:      {sorted(df['rec_label'].unique())}")

    X = df[FEATURE_COLS].values
    y_insight = df["insight_label"].values
    y_rec = df["rec_label"].values

    # ── Train Insight Classifier ────────────────────────────────────
    print("\n[2] Training Insight Classifier (Random Forest, 200 trees)...")
    insight_model = RandomForestClassifier(n_estimators=200, random_state=42, n_jobs=-1)
    insight_model.fit(X, y_insight)
    scores = cross_val_score(insight_model, X, y_insight, cv=5, scoring="accuracy")
    print(f"   5-Fold CV Accuracy: {scores.mean():.3f} (+/- {scores.std():.3f})")
    for lbl, cnt in zip(*np.unique(y_insight, return_counts=True)):
        print(f"   {lbl:2d} ({INSIGHT_LABEL_NAMES[lbl]}): {cnt} samples")

    # ── Train Recommendation Classifier ────────────────────────────
    print("\n[3] Training Recommendation Classifier (Random Forest, 200 trees)...")
    rec_model = RandomForestClassifier(n_estimators=200, random_state=42, n_jobs=-1)
    rec_model.fit(X, y_rec)
    scores = cross_val_score(rec_model, X, y_rec, cv=5, scoring="accuracy")
    print(f"   5-Fold CV Accuracy: {scores.mean():.3f} (+/- {scores.std():.3f})")
    for lbl, cnt in zip(*np.unique(y_rec, return_counts=True)):
        print(f"   {lbl:2d} ({REC_LABEL_NAMES[lbl]}): {cnt} samples")

    # ── Save ────────────────────────────────────────────────────────
    OUT = "ml-hf/models"
    os.makedirs(OUT, exist_ok=True)

    with open(f"{OUT}/insight_classifier.pkl", "wb") as f:
        pickle.dump(insight_model, f)
    with open(f"{OUT}/rec_classifier.pkl", "wb") as f:
        pickle.dump(rec_model, f)
    with open(f"{OUT}/text_models_feature_cols.pkl", "wb") as f:
        pickle.dump(FEATURE_COLS, f)
    with open(f"{OUT}/insight_label_names.pkl", "wb") as f:
        pickle.dump(INSIGHT_LABEL_NAMES, f)

    print(f"\n[OK] Models saved to {OUT}/:")
    for fname in [
        "insight_classifier.pkl",
        "rec_classifier.pkl",
        "text_models_feature_cols.pkl",
        "insight_label_names.pkl",
    ]:
        size = os.path.getsize(f"{OUT}/{fname}")
        print(f"  {fname} ({size:,} bytes)")


if __name__ == "__main__":
    main()
