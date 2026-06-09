import os
import pandas as pd
import joblib

from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

os.makedirs("models", exist_ok=True)

df = pd.read_csv("dataset/craycare_dataset.csv")

print("Dataset loaded.")
print("Rows:", len(df))
print(df["status"].value_counts())

X = df[
    [
        "temperature",
        "phLevel",
        "dissolvedOxygen",
        "turbidity",
        "waterLevel",
    ]
]

y = df["status"]

X_train, X_test, y_train, y_test = train_test_split(
    X,
    y,
    test_size=0.2,
    random_state=42,
    stratify=y,
)

model = RandomForestClassifier(
    n_estimators=100,
    random_state=42,
    class_weight="balanced",
)

model.fit(X_train, y_train)

predictions = model.predict(X_test)

print("\nAccuracy:")
print(accuracy_score(y_test, predictions))

print("\nClassification Report:")
print(classification_report(y_test, predictions))

joblib.dump(model, "models/craycare_model.pkl")

print("\nModel saved to models/craycare_model.pkl")