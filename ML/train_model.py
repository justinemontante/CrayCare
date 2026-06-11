import os
import pandas as pd
import joblib

from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

os.makedirs("models", exist_ok=True)

STAGES = ["early_juvenile", "advanced_juvenile", "pre_adult", "market_size"]
FEATURES = ["temperature", "phLevel", "dissolvedOxygen", "turbidity", "waterLevel"]

for stage in STAGES:
    print(f"\n{'=' * 50}")
    print(f"Training model for stage: {stage}")
    print(f"{'=' * 50}")

    df = pd.read_csv(f"dataset/{stage}.csv")
    print(f"Rows: {len(df)}")
    print(df["status"].value_counts())

    X = df[FEATURES]
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
    acc = accuracy_score(y_test, predictions)
    print(f"\nAccuracy: {acc:.4f}")
    print("\nClassification Report:")
    print(classification_report(y_test, predictions, zero_division=0))

    path = f"models/craycare_model_{stage}.pkl"
    joblib.dump(model, path)
    print(f"Model saved to {path}")

print("\nAll per-stage models trained and saved.")
