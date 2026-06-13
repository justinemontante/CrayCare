import os
import pandas as pd
import joblib

from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

os.makedirs("models", exist_ok=True)

df = pd.read_csv("dataset/craycare_dataset.csv")
print(f"Loaded dataset with {len(df)} rows.")

FEATURES = [
    "temperature", "phLevel", "dissolvedOxygen", "turbidity", "waterLevel",
    "temp_rate", "do_rate", "turb_rate",
    "temp_min", "temp_max", "ph_min", "ph_max", "do_min", "turb_max", "wl_min", "wl_max"
]

X = df[FEATURES]
y_status = df["status"]

print("\nTraining Overall Status Model...")
X_train, X_test, y_train, y_test = train_test_split(X, y_status, test_size=0.2, random_state=42, stratify=y_status)
model_status = RandomForestClassifier(n_estimators=50, random_state=42, n_jobs=-1)
model_status.fit(X_train, y_train)
acc_status = accuracy_score(y_test, model_status.predict(X_test))
print(f"Overall Status Model Accuracy: {acc_status:.4f}")
print(classification_report(y_test, model_status.predict(X_test)))
joblib.dump(model_status, "models/craycare_status_model.pkl")
print("Saved models/craycare_status_model.pkl")

print("\nDynamic status model trained and saved.")
