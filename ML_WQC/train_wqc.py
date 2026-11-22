from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.dummy import DummyClassifier
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
)

BASE_DIR = Path(__file__).resolve().parent
DATASET_PATH = BASE_DIR / "datasets" / "craycare_water_quality_dataset.csv"
MODEL_DIR = BASE_DIR / "model"
MODEL_OUT = MODEL_DIR / "wqc_random_forest.joblib"
REPORT_OUT = MODEL_DIR / "model_evaluation_report.json"
FUNCTION_MODEL_OUT = (
    BASE_DIR.parent
    / "functions"
    / "backend"
    / "water_quality_classification"
    / "wqc_random_forest.json"
)

SENSOR_FEATURES = ["temperature", "ph_level", "dissolved_oxygen", "turbidity"]
MODEL_FEATURES = SENSOR_FEATURES + ["do_temp_ratio"]
CLASS_NAMES = {0: "Critical", 1: "Poor", 2: "Good"}
MODEL_VERSION = "wqc-rf-v5-3class"
TIME_FORMAT = "%m/%d/%Y %H:%M"
TIME_GAP = pd.Timedelta(hours=2)
TIMEZONE_NAME = "Asia/Manila"


def parse_timestamps(values: pd.Series) -> pd.Series:
    return pd.to_datetime(values.astype(str).str.strip(), format=TIME_FORMAT, errors="coerce")


def derive_rule_labels(frame: pd.DataFrame) -> np.ndarray:
    """Apply the aquaculturist-approved per-sensor bands; worst band wins."""
    temperature = frame["temperature"].to_numpy(dtype=float)
    ph = frame["ph_level"].to_numpy(dtype=float)
    dissolved_oxygen = frame["dissolved_oxygen"].to_numpy(dtype=float)
    turbidity = frame["turbidity"].to_numpy(dtype=float)

    temp_class = np.select(
        [(temperature < 15.0) | (temperature >= 34.0),
         (temperature < 26.0) | (temperature > 29.0)],
        [0, 1], default=2,
    )
    ph_class = np.select(
        [(ph < 5.5) | (ph > 9.5), (ph < 6.5) | (ph > 8.5)],
        [0, 1], default=2,
    )
    do_class = np.select(
        [dissolved_oxygen < 2.0, dissolved_oxygen < 5.0], [0, 1], default=2,
    )
    turbidity_class = np.select(
        [turbidity > 50.0, turbidity > 25.0], [0, 1], default=2,
    )
    return np.min(np.column_stack([temp_class, ph_class, do_class, turbidity_class]), axis=1)


def _read_sensor_csv(path: Path) -> pd.DataFrame:
    if not path.is_file():
        raise FileNotFoundError(f"Dataset not found: {path}")
    frame = pd.read_csv(path, low_memory=False)
    required = {"timestamp", *SENSOR_FEATURES}
    missing = sorted(required - set(frame.columns))
    if missing:
        raise ValueError(f"{path.name} is missing columns: {', '.join(missing)}")
    frame = frame.copy()
    frame["timestamp_local"] = parse_timestamps(frame["timestamp"])
    for column in SENSOR_FEATURES:
        frame[column] = pd.to_numeric(frame[column], errors="coerce")
    return frame


def _usable_mask(frame: pd.DataFrame) -> np.ndarray:
    values = frame[SENSOR_FEATURES].to_numpy(dtype=float)
    return (
        frame["timestamp_local"].notna().to_numpy()
        & np.isfinite(values).all(axis=1)
        & (frame["temperature"].between(0.0, 50.0)).to_numpy()
        & (frame["ph_level"].between(0.0, 14.0)).to_numpy()
        & (frame["dissolved_oxygen"].between(0.0, 30.0)).to_numpy()
        & (frame["turbidity"].between(0.0, 5000.0)).to_numpy()
    )


def load_training_sources() -> tuple[pd.DataFrame, pd.DataFrame, dict[str, Any]]:
    if not DATASET_PATH.is_file():
        raise FileNotFoundError(f"Dataset not found: {DATASET_PATH}")
    master = pd.read_csv(DATASET_PATH, low_memory=False)

    # 1. Observed IoT readings (for chronological 70/15/15 split)
    observed_raw = master.loc[master["data_type"] == "IoT Sensor Reading"].copy()
    observed_raw["timestamp_local"] = parse_timestamps(observed_raw["timestamp"])
    for col in SENSOR_FEATURES:
        observed_raw[col] = pd.to_numeric(observed_raw[col], errors="coerce").round(2)
    observed_raw["class_code"] = pd.to_numeric(observed_raw["class_code"], errors="coerce").astype(int)
    observed_raw["class_label"] = observed_raw["class_label"].astype(str)

    expected_labels = observed_raw["class_code"].map(CLASS_NAMES)
    if not expected_labels.equals(observed_raw["class_label"]):
        raise ValueError("Observed class labels do not match their class codes.")

    observed_usable = _usable_mask(observed_raw)
    observed_excluded = int((~observed_usable).sum())
    observed = observed_raw.loc[observed_usable].copy()
    observed_expected = derive_rule_labels(observed)
    if not np.array_equal(observed["class_code"].to_numpy(), observed_expected):
        raise ValueError("Observed class labels do not match the approved range rules.")
    observed = observed.sort_values("timestamp_local").reset_index(drop=True)

    # 2. Benchmark & Baseline training scenarios (fit only)
    scenarios = master.loc[master["data_type"] != "IoT Sensor Reading"].copy()
    for col in SENSOR_FEATURES:
        scenarios[col] = pd.to_numeric(scenarios[col], errors="coerce").round(2)
    scenarios["class_code"] = pd.to_numeric(scenarios["class_code"], errors="coerce").astype(int)
    scenarios["class_label"] = scenarios["class_label"].astype(str)

    metadata = {
        "dataset_file": DATASET_PATH.name,
        "total_master_rows": int(len(master)),
        "observed_source_rows": int(len(observed_raw)),
        "observed_usable_rows": int(len(observed)),
        "observed_excluded_invalid_rows": observed_excluded,
        "standards_and_baseline_scenarios_rows": int(len(scenarios)),
        "observed_class_counts": {
            CLASS_NAMES[int(code)]: int(count)
            for code, count in observed["class_code"].value_counts().sort_index().items()
        },
        "observed_start": observed["timestamp_local"].min().isoformat(),
        "observed_end": observed["timestamp_local"].max().isoformat(),
    }
    return observed, scenarios, metadata


def build_standards_scenarios(seed: int = 42) -> pd.DataFrame:
    """Generate training-only Good, Poor, and Critical boundary scenarios
    across all approved per-sensor ranges so the 3-class RF learns exact cutoffs."""
    rng = np.random.default_rng(seed)
    rows: list[dict[str, float]] = []

    def rand_good(n: int) -> dict[str, np.ndarray]:
        return {
            "temperature": rng.uniform(26.0, 29.0, n),
            "ph_level": rng.uniform(7.0, 8.5, n),
            "dissolved_oxygen": rng.uniform(5.0, 12.0, n),
            "turbidity": rng.uniform(0.1, 25.0, n),
        }

    def add_batch(overrides: dict[str, np.ndarray], n: int) -> None:
        base = rand_good(n)
        base.update(overrides)
        for i in range(n):
            rows.append({col: round(float(base[col][i]), 2) for col in SENSOR_FEATURES})

    # 1) Full-range Good + tight boundary Good near cutoffs
    add_batch({}, 400)
    add_batch({"dissolved_oxygen": rng.uniform(5.0, 5.5, 150)}, 150)

    # 2) Poor bands + tight boundary coverage near Good and Critical cutoffs
    add_batch({"temperature": rng.uniform(15.0, 25.99, 250)}, 250)
    add_batch({"temperature": rng.uniform(15.0, 16.5, 100)}, 100)
    add_batch({"temperature": rng.uniform(29.01, 33.99, 350)}, 350)
    add_batch({"temperature": rng.uniform(29.5, 32.0, 150)}, 150)

    add_batch({"ph_level": rng.uniform(5.5, 6.49, 250)}, 250)
    add_batch({"ph_level": rng.uniform(5.5, 5.8, 100)}, 100)
    add_batch({"ph_level": rng.uniform(8.51, 9.5, 350)}, 350)
    add_batch({"ph_level": rng.uniform(8.55, 9.0, 150)}, 150)

    add_batch({"dissolved_oxygen": rng.uniform(2.0, 4.99, 300)}, 300)
    add_batch({"dissolved_oxygen": rng.uniform(2.0, 2.3, 120)}, 120)
    add_batch({"dissolved_oxygen": rng.uniform(4.5, 4.99, 120)}, 120)

    add_batch({"turbidity": rng.uniform(25.01, 50.0, 250)}, 250)
    add_batch({"turbidity": rng.uniform(48.0, 50.0, 100)}, 100)

    # 3) Critical boundary bands right outside the cutoffs
    add_batch({"temperature": rng.uniform(10.0, 14.99, 120)}, 120)
    add_batch({"temperature": rng.uniform(34.0, 36.0, 120)}, 120)
    add_batch({"ph_level": rng.uniform(4.0, 5.49, 120)}, 120)
    add_batch({"ph_level": rng.uniform(9.51, 10.5, 120)}, 120)
    add_batch({"dissolved_oxygen": rng.uniform(0.5, 1.99, 150)}, 150)
    add_batch({"turbidity": rng.uniform(50.01, 60.0, 120)}, 120)

    df = pd.DataFrame(rows)
    df["class_code"] = derive_rule_labels(df)
    df["class_label"] = df["class_code"].map(CLASS_NAMES)
    return df


def chronological_split(observed: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    if len(observed) < 30:
        raise ValueError("Too few observed readings for chronological train/validation/holdout splits.")
    train_cut = observed["timestamp_local"].iloc[int(len(observed) * 0.70)]
    validation_cut = observed["timestamp_local"].iloc[int(len(observed) * 0.85)]
    timestamps = observed["timestamp_local"]
    train = observed.loc[timestamps < train_cut].copy()
    validation = observed.loc[(timestamps >= train_cut + TIME_GAP) & (timestamps < validation_cut)].copy()
    holdout = observed.loc[timestamps >= validation_cut + TIME_GAP].copy()
    if train.empty or validation.empty or holdout.empty:
        raise ValueError("Chronological split produced an empty set; check the input dates.")
    if train["timestamp_local"].max() + TIME_GAP > validation["timestamp_local"].min():
        raise ValueError("Train/validation time gap is shorter than two hours.")
    if validation["timestamp_local"].max() + TIME_GAP > holdout["timestamp_local"].min():
        raise ValueError("Validation/holdout time gap is shorter than two hours.")
    return train, validation, holdout


def make_model_features(frame: pd.DataFrame) -> pd.DataFrame:
    features = frame[SENSOR_FEATURES].copy()
    features["do_temp_ratio"] = features["dissolved_oxygen"] / features["temperature"].clip(lower=1.0)
    return features[MODEL_FEATURES]


def metric_block(y_true: np.ndarray, y_pred: np.ndarray) -> dict[str, Any]:
    detail = classification_report(
        y_true, y_pred, labels=[0, 1, 2], target_names=["Critical", "Poor", "Good"],
        output_dict=True, zero_division=0,
    )
    return {
        "rows": int(len(y_true)),
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "balanced_accuracy": float(balanced_accuracy_score(y_true, y_pred)),
        "confusion_matrix_labels_0_1_2": confusion_matrix(y_true, y_pred, labels=[0, 1, 2]).tolist(),
        "per_class": {
            name: {
                "precision": float(detail[name]["precision"]),
                "recall": float(detail[name]["recall"]),
                "f1": float(detail[name]["f1-score"]),
                "support": int(detail[name]["support"]),
            }
            for name in ("Critical", "Poor", "Good")
        },
        "macro_f1": float(detail["macro avg"]["f1-score"]),
        "weighted_f1": float(detail["weighted avg"]["f1-score"]),
    }


def count_classes(frame: pd.DataFrame) -> dict[str, int]:
    return {
        CLASS_NAMES[int(code)]: int(count)
        for code, count in frame["class_code"].value_counts().sort_index().items()
    }


def train() -> dict[str, Any]:
    observed, scenarios, source_audit = load_training_sources()
    observed_train, validation, holdout = chronological_split(observed)

    fit_data = pd.concat([observed_train, scenarios], ignore_index=True)

    # Sensor-realistic noise regularization (simulates physical sensor noise/imprecision)
    noise_rng = np.random.default_rng(42)
    fit_data["temperature"] += noise_rng.normal(0, 0.15, len(fit_data))
    fit_data["ph_level"] += noise_rng.normal(0, 0.03, len(fit_data))
    fit_data["dissolved_oxygen"] += noise_rng.normal(0, 0.10, len(fit_data))
    fit_data["turbidity"] += noise_rng.normal(0, 1.00, len(fit_data))

    x_train = make_model_features(fit_data)
    y_train = fit_data["class_code"].astype(int)

    x_val = make_model_features(validation)
    y_val = validation["class_code"].astype(int)
    x_holdout = make_model_features(holdout)
    y_holdout = holdout["class_code"].astype(int)

    model = RandomForestClassifier(
        n_estimators=300,
        max_depth=12,
        min_samples_leaf=2,
        max_features=None,
        class_weight="balanced_subsample",
        random_state=42,
        n_jobs=-1,
    )
    model.fit(x_train, y_train)

    validation_metrics = metric_block(y_val.to_numpy(), model.predict(x_val))
    holdout_metrics = metric_block(y_holdout.to_numpy(), model.predict(x_holdout))

    majority = DummyClassifier(strategy="most_frequent").fit(x_train, y_train)
    majority_metrics = metric_block(y_holdout.to_numpy(), majority.predict(x_holdout))
    rule_predictions = derive_rule_labels(holdout)
    rule_metrics = metric_block(y_holdout.to_numpy(), rule_predictions)

    bundle = {
        "model": model,
        "algorithm": "RandomForestClassifier",
        "model_version": MODEL_VERSION,
        "features": MODEL_FEATURES,
        "class_codes": CLASS_NAMES,
        "classes": model.classes_.tolist(),
        "trained_at_utc": pd.Timestamp.now(tz="UTC").isoformat(),
        "sklearn_version": sklearn.__version__,
        "training_provenance": "100% Machine Learning 3-class Random Forest (Critical, Poor, Good) trained on observed readings and standards-based boundary scenarios.",
    }
    report = {
        "algorithm": "RandomForestClassifier",
        "model_version": MODEL_VERSION,
        "features": MODEL_FEATURES,
        "class_codes": CLASS_NAMES,
        "parameters": {
            "n_estimators": 300,
            "max_depth": 12,
            "min_samples_leaf": 2,
            "class_weight": "balanced_subsample",
            "max_features": None,
            "random_state": 42,
        },
        "label_method": "100% Machine Learning 3-class classification: Critical (0), Poor (1), and Good (2) are directly predicted by the Random Forest model.",
        "provenance": source_audit,
        "training_scenarios": {
            "standards_fit_only_rows": int(len(scenarios)),
            "scenario_source": f"Integrated inside {DATASET_PATH.name} (data_type != 'IoT Sensor Reading')",
            "note": "Generated standards boundary scenarios enable 3-class learning across all sensor cutoffs without modifying evaluation sets.",
        },
        "split": {
            "method": "chronological observed-data split: first 70% fit, next 15% validation, final 15% holdout",
            "gap_between_sets_hours": 2,
            "observed_fit_rows": int(len(observed_train)),
            "observed_validation_rows": int(len(validation)),
            "observed_holdout_rows": int(len(holdout)),
            "fit_class_counts_including_standards": count_classes(fit_data),
            "validation_class_counts": count_classes(validation),
            "holdout_class_counts": count_classes(holdout),
            "fit_period": [observed_train["timestamp_local"].min().isoformat(), observed_train["timestamp_local"].max().isoformat()],
            "validation_period": [validation["timestamp_local"].min().isoformat(), validation["timestamp_local"].max().isoformat()],
            "holdout_period": [holdout["timestamp_local"].min().isoformat(), holdout["timestamp_local"].max().isoformat()],
        },
        "validation_metrics": validation_metrics,
        "holdout_metrics": holdout_metrics,
        "majority_baseline_holdout_metrics": majority_metrics,
        "threshold_rule_baseline_holdout_metrics": rule_metrics,
    }

    MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)
    REPORT_OUT.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(bundle, MODEL_OUT, compress=3)
    REPORT_OUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    export_model_for_functions(model, MODEL_FEATURES)
    return report


def export_model_for_functions(model: RandomForestClassifier, features: list[str]) -> None:
    """Write the trained forest in the compact format consumed by Node.js."""
    trees = []
    for estimator in model.estimators_:
        tree = estimator.tree_
        raw_values = tree.value.tolist()
        trees.append({
            "left": tree.children_left.tolist(),
            "right": tree.children_right.tolist(),
            "feature": tree.feature.tolist(),
            "threshold": [round(float(value), 6) for value in tree.threshold.tolist()],
            "value": [node[0] for node in raw_values],
        })

    payload = {
        "model_version": MODEL_VERSION,
        "n_classes": int(model.n_classes_),
        "classes": model.classes_.tolist(),
        "n_features": int(model.n_features_in_),
        "feature_names": features,
        "scaler": None,
        "trees": trees,
    }
    FUNCTION_MODEL_OUT.parent.mkdir(parents=True, exist_ok=True)
    FUNCTION_MODEL_OUT.write_text(
        json.dumps(payload, separators=(",", ":")),
        encoding="utf-8",
    )


def format_classification_report(metrics: dict[str, Any]) -> str:
    """Format saved metrics like sklearn's console classification report for 3 classes."""
    names = ("Critical", "Poor", "Good")
    per_class = metrics["per_class"]
    total = metrics["rows"]
    active_names = [name for name in names if per_class[name]["support"] > 0]
    macro = {key: sum(per_class[name][key] for name in active_names) / len(active_names)
             for key in ("precision", "recall", "f1")} if active_names else {"precision": 0, "recall": 0, "f1": 0}
    weighted = {
        key: sum(
            per_class[name][key] * per_class[name]["support"]
            for name in names
        ) / total if total else 0.0
        for key in ("precision", "recall", "f1")
    }

    lines = [
        "              precision    recall  f1-score   support",
        "",
    ]
    for name in names:
        item = per_class[name]
        lines.append(
            f"{name:>12} {item['precision']:>10.4f} {item['recall']:>9.4f} "
            f"{item['f1']:>9.4f} {item['support']:>9d}"
        )
    lines.extend([
        "",
        f"{'accuracy':>12} {'':>10} {'':>9} {metrics['accuracy']:>9.4f} {total:>9d}",
        f"{'macro avg':>12} {macro['precision']:>10.4f} {macro['recall']:>9.4f} "
        f"{macro['f1']:>9.4f} {total:>9d}",
        f"{'weighted avg':>12} {weighted['precision']:>10.4f} {weighted['recall']:>9.4f} "
        f"{weighted['f1']:>9.4f} {total:>9d}",
    ])
    return "\n".join(lines)


if __name__ == "__main__":
    result = train()
    validation = result["validation_metrics"]
    holdout = result["holdout_metrics"]

    print("=== CrayCare Random Forest Classifier Training (3-Class) ===")
    print(f"  Model version : {MODEL_VERSION}")
    print("  RF scope      : 100% Machine Learning (Critical, Poor, Good)")
    print(f"  Master dataset: {DATASET_PATH.name} (Single Unified Dataset)")
    print(f"  Scenarios rows: {result['training_scenarios']['standards_fit_only_rows']} (fit only)")
    print(f"\n  Validation Accuracy : {validation['accuracy'] * 100:.2f}%")
    print(f"  Holdout Accuracy    : {holdout['accuracy'] * 100:.2f}%")

    print("\n--- VALIDATION SET ---")
    print(format_classification_report(validation))
    print("--- HOLDOUT / TEST SET ---")
    print(format_classification_report(holdout))
    print("Confusion Matrix (Validation) [Critical / Poor / Good]:")
    print(np.asarray(validation["confusion_matrix_labels_0_1_2"]))
    print("\nConfusion Matrix (Holdout) [Critical / Poor / Good]:")
    print(np.asarray(holdout["confusion_matrix_labels_0_1_2"]))

    print(f"\n  Model saved -> {MODEL_OUT}")
    print(f"  Firebase model exported -> {FUNCTION_MODEL_OUT}")
    print(f"  Report saved -> {REPORT_OUT}")

    bundle = joblib.load(MODEL_OUT)
    tests = [
        ("Screenshot case (DO 4.63)", 26.6, 7.94, 4.63, 11.9, "Poor"),
        ("All Good",                  26.6, 7.94, 5.50, 11.9, "Good"),
        ("DO Critical (1.80)",        26.6, 7.94, 1.80, 11.9, "Critical"),
        ("Low Temp Poor (23.95)",     23.95, 7.20, 6.20, 1.0, "Poor"),
        ("High Temp Poor (30.5)",     30.5, 7.50, 6.00, 5.0,  "Poor"),
        ("High pH Poor (8.80)",       27.5, 8.80, 6.00, 5.0,  "Poor"),
        ("Low pH Poor (6.00)",        27.5, 6.00, 6.00, 5.0,  "Poor"),
        ("Turbidity Poor (35.0)",     27.5, 7.50, 6.00, 35.0, "Poor"),
        ("High Temp Critical (34.5)", 34.5, 7.50, 6.00, 5.0,  "Critical"),
        ("Low Temp Critical (12.0)",  12.0, 7.50, 6.00, 5.0,  "Critical"),
        ("Low pH Critical (5.0)",     27.5, 5.00, 6.00, 5.0,  "Critical"),
        ("High pH Critical (9.8)",    27.5, 9.80, 6.00, 5.0,  "Critical"),
        ("Turbidity Critical (55.0)", 27.5, 7.50, 6.00, 55.0, "Critical"),
    ]
    print("\n--- SANITY CHECKS ---")
    for name, t, p, d, tb, expected in tests:
        row = pd.DataFrame([{"temperature": t, "ph_level": p, "dissolved_oxygen": d, "turbidity": tb}])
        pred = CLASS_NAMES[int(bundle["model"].predict(make_model_features(row))[0])]
        status = "OK" if pred == expected else "MISMATCH"
        print(f"  [{status}] {name}: predicted={pred}, expected={expected}")
