"""Train CSI-XGBoost -> csi_model.joblib"""

import pandas as pd
import numpy as np
import joblib
from xgboost import XGBClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix

df = (
    pd.read_csv("sensor_labeled.csv", parse_dates=["timestamp"])
    .sort_values("timestamp")
    .reset_index(drop=True)
)

SENSORS = ["temp", "pH", "DO", "turbidity", "waterLevel"]
base_cols = []
for s in SENSORS:
    base_cols += [f"{s}_avg", f"{s}_min", f"{s}_max"]

feat = df[base_cols].copy()
for s in SENSORS:
    a = df[f"{s}_avg"]
    feat[f"{s}_volatility"] = df[f"{s}_max"] - df[f"{s}_min"]
    feat[f"{s}_roll6h"] = a.rolling(36, min_periods=1).mean()
    feat[f"{s}_roll24h"] = a.rolling(144, min_periods=1).mean()
    feat[f"{s}_trend"] = a.diff().rolling(6, min_periods=1).mean()

feat["DO_hrs_low"] = (df["DO_min"] < 5.0).rolling(36, min_periods=1).sum() / 6.0
feat["temp_hrs_hi"] = (df["temp_max"] > 31.0).rolling(36, min_periods=1).sum() / 6.0
feat["pH_hrs_bad"] = ((df["pH_min"] < 6.5) | (df["pH_max"] > 8.5)).rolling(
    36, min_periods=1
).sum() / 6.0

feat = feat.bfill().fillna(0)

X, y = feat, df["csi_class"]
Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, shuffle=False)

model = XGBClassifier(
    n_estimators=400,
    max_depth=5,
    learning_rate=0.05,
    subsample=0.9,
    colsample_bytree=0.9,
    objective="multi:softprob",
    num_class=4,
    eval_metric="mlogloss",
    random_state=42,
)
model.fit(Xtr, ytr)

pred = model.predict(Xte)
print(
    classification_report(
        yte, pred, target_names=["Low", "Moderate", "High", "Critical"]
    )
)
print("Confusion matrix:\n", confusion_matrix(yte, pred))

imp = pd.Series(model.feature_importances_, index=X.columns).sort_values(
    ascending=False
)
print("\nTop 10 features:\n", imp.head(10))

joblib.dump({"model": model, "features": list(X.columns)}, "csi_model.joblib")
print("\nSaved csi_model.joblib")
