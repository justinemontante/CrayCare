import os
import pandas as pd
import joblib

from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

os.makedirs("models", exist_ok=True)

df = pd.read_csv("dataset/craycare_dataset.csv")
print(f"Loaded {len(df)} rows")

FEATURES = [
    "temperature",
    "phLevel",
    "dissolvedOxygen",
    "turbidity",
    "waterLevel",
    "temp_rate",
    "ph_rate",
    "do_rate",
    "turb_rate",
    "wl_rate",
    "temp_min",
    "temp_max",
    "ph_min",
    "ph_max",
    "do_min",
    "turb_max",
    "wl_min",
    "wl_max",
]

SENSOR_TARGETS = {
    "temp": "temp_status",
    "ph": "ph_status",
    "do": "do_status",
    "turb": "turb_status",
    "wl": "wl_status",
}

X = df[FEATURES]
results = []

for sensor_name, target_col in SENSOR_TARGETS.items():
    y = df[target_col]
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    model = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    cr = classification_report(y_test, y_pred, output_dict=True)

    results.append(
        {
            "model": sensor_name,
            "accuracy": acc,
            "precision": cr["weighted avg"]["precision"],
            "recall": cr["weighted avg"]["recall"],
            "f1": cr["weighted avg"]["f1-score"],
        }
    )

    print(f"\n{'=' * 50}")
    print(f"  {sensor_name.upper()} Model")
    print(f"{'=' * 50}")
    print(f"Accuracy: {acc:.4f}")
    print(classification_report(y_test, y_pred))

    joblib.dump(model, f"models/craycare_{sensor_name}_model.pkl")
    print(f"Saved models/craycare_{sensor_name}_model.pkl")

y_status = df["status"]
X_train, X_test, y_train, y_test = train_test_split(
    X, y_status, test_size=0.2, random_state=42, stratify=y_status
)

model_status = RandomForestClassifier(n_estimators=100, random_state=42, n_jobs=-1)
model_status.fit(X_train, y_train)

y_pred = model_status.predict(X_test)
acc_status = accuracy_score(y_test, y_pred)
cr_status = classification_report(y_test, y_pred, output_dict=True)

results.append(
    {
        "model": "overall",
        "accuracy": acc_status,
        "precision": cr_status["weighted avg"]["precision"],
        "recall": cr_status["weighted avg"]["recall"],
        "f1": cr_status["weighted avg"]["f1-score"],
    }
)

print(f"\n{'=' * 50}")
print(f"  OVERALL STATUS Model")
print(f"{'=' * 50}")
print(f"Accuracy: {acc_status:.4f}")
print(classification_report(y_test, y_pred))

joblib.dump(model_status, "models/craycare_status_model.pkl")
print("Saved models/craycare_status_model.pkl")

print(f"\n{'=' * 50}")
print(f"  SUMMARY")
print(f"{'=' * 50}")
summary_df = pd.DataFrame(results)
print(summary_df.to_string(index=False))

print("\nAll models trained successfully.")
