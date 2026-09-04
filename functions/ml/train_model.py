"""Train the CrayCare WQAD Isolation Forest prototype.

The Isolation Forest fit receives sensor-derived features only. The synthetic
event columns are used after fitting to evaluate the bootstrap prototype and
are never used as model inputs or training labels.
"""

import os
import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.ensemble import IsolationForest
from sklearn.metrics import precision_recall_fscore_support, confusion_matrix

from anomaly_features import build_anomaly_features

ROOT = os.path.dirname(os.path.abspath(__file__))
DATASET_PATH = os.path.join(ROOT, "sensor_dataset.csv")
MODEL_PATH = os.path.join(ROOT, "wqad_model.joblib")
TRAIN_DAYS = 60
WARMUP_ROWS = 12
REFERENCE_ALERT_PERCENTILE = 98.0

df = pd.read_csv(DATASET_PATH)
df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)
features = build_anomaly_features(df.assign(timestamp=df["timestamp"].astype("int64") / 1e9))
split_at = df["timestamp"].min() + pd.Timedelta(days=TRAIN_DAYS)
train_mask = df["timestamp"] < split_at
test_mask = ~train_mask

X_train = features.loc[train_mask].iloc[WARMUP_ROWS:].copy()
X_test = features.loc[test_mask].copy()
y_test = df.loc[test_mask, "is_injected_anomaly"].astype(int).to_numpy()
event_test = df.loc[test_mask, "event_type"].astype(str).to_numpy()

model = IsolationForest(
    n_estimators=600,
    max_samples=min(4096, len(X_train)),
    max_features=0.85,
    contamination="auto",
    bootstrap=False,
    random_state=42,
    n_jobs=-1,
)
model.fit(X_train)

train_raw = -model.decision_function(X_train)
threshold = float(np.percentile(train_raw, REFERENCE_ALERT_PERCENTILE))
test_raw = -model.decision_function(X_test)
pred = (test_raw >= threshold).astype(int)
precision, recall, f1, _ = precision_recall_fscore_support(
    y_test, pred, average="binary", zero_division=0
)
tn, fp, fn, tp = confusion_matrix(y_test, pred, labels=[0, 1]).ravel()

event_detection = {}
for event_name in sorted(set(event_test) - {"normal"}):
    mask = event_test == event_name
    event_detection[event_name] = {
        "rows": int(mask.sum()),
        "detected_rows": int(pred[mask].sum()),
        "detection_rate": round(float(pred[mask].mean()), 4),
        "event_detected": bool(pred[mask].any()),
    }

centers = X_train.median()
mad = (X_train - centers).abs().median() * 1.4826
fallback_scale = X_train.std().replace(0, 1.0).fillna(1.0)
scales = mad.where(mad > 1e-8, fallback_scale).replace(0, 1.0).fillna(1.0)

bundle = {
    "model": model,
    "features": list(X_train.columns),
    "algorithm": "IsolationForest",
    "model_version": f"wqad-isolation-forest-bootstrap-sklearn-{sklearn.__version__}",
    "trained_at_utc": pd.Timestamp.now(tz="UTC").isoformat(),
    "training_rows": len(X_train),
    "training_data_origin": "synthetic_bootstrap_not_field_validated",
    "training_labels_used": False,
    "decision_basis": "98th_percentile_of_unsupervised_training_anomaly_scores",
    "decision_threshold_raw": threshold,
    "calibration_scores": np.sort(train_raw).astype(float),
    "robust_centers": centers.astype(float).to_dict(),
    "robust_scales": scales.astype(float).to_dict(),
    "analysis_window_minutes": 120,
    "minimum_history_rows": 12,
    "validation_strategy": "chronological_60_day_reference_and_30_day_holdout",
    "prototype_metrics": {
        "precision": round(float(precision), 4),
        "recall": round(float(recall), 4),
        "f1": round(float(f1), 4),
        "true_negative": int(tn), "false_positive": int(fp),
        "false_negative": int(fn), "true_positive": int(tp),
        "event_detection": event_detection,
    },
}
joblib.dump(bundle, MODEL_PATH, compress=3)

print("CrayCare Machine Learning-Based Water Quality Anomaly Detection")
print(f"Algorithm: Isolation Forest; features: {len(X_train.columns)}; training rows: {len(X_train):,}")
print(f"Holdout precision={precision:.3f}, recall={recall:.3f}, F1={f1:.3f}")
print(f"Confusion matrix: TN={tn}, FP={fp}, FN={fn}, TP={tp}")
for name, metrics in event_detection.items():
    print(f"  {name}: {metrics['detected_rows']}/{metrics['rows']} rows ({metrics['detection_rate']:.1%})")
print(f"Saved {MODEL_PATH}")
print("WARNING: bootstrap validation only; retrain and validate with real Cherax RAS history.")
