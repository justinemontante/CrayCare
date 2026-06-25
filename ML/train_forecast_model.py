import pandas as pd
import numpy as np
import pickle
import os
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import GroupShuffleSplit, GroupKFold
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import mean_absolute_error, r2_score

# ── Load EXISTING v2 dataset — parehong CSV, walang bagong generation ──
df = pd.read_csv("dataset/craycare_dataset_v2.csv")
print(f"[OK] Loaded {len(df):,} rows")

SENSOR_KEYS = ["temp", "ph", "do", "turb", "wl"]
COL_MAP = {
    "temp": "temperature", "ph": "phLevel", "do": "dissolvedOxygen",
    "turb": "turbidity", "wl": "waterLevel",
}

# ── Hakbang 1: gawin ang FUTURE VALUE label — i-shift pasulong ng 1 ROW ──
# sa parehong seq_id (= 5 minuto mula ngayon). Pansin: hindi na "zone"
# ang ishi-shift natin, kundi ang MISMONG NUMERIC VALUE ng sensor —
# kaya regression ito, hindi classification.
SHIFT_ROWS = 1
for s in SENSOR_KEYS:
    val_col = COL_MAP[s]
    df[f"future_{s}_value"] = df.groupby("seq_id")[val_col].shift(-SHIFT_ROWS)

before = len(df)
TARGET_COLS = [f"future_{s}_value" for s in SENSOR_KEYS]
df = df.dropna(subset=TARGET_COLS).reset_index(drop=True)
print(f"[OK] {before:,} rows -> {len(df):,} rows after dropping tail rows without future label")

print("\nFuture value ranges per sensor:")
for s in SENSOR_KEYS:
    col = f"future_{s}_value"
    print(f"  {s}: {df[col].min():.2f} - {df[col].max():.2f}")

# ── Hakbang 2: parehong FEATURE_COLS gaya ng v2/forecast model — ────────
# walang binago, current values/rates/duration/thresholds/stage lang.
FEATURE_COLS = [
    "temperature", "phLevel", "dissolvedOxygen", "turbidity", "waterLevel",
    "temp_rate", "ph_rate", "do_rate", "turb_rate", "wl_rate",
    "temp_minutes_in_zone", "ph_minutes_in_zone", "do_minutes_in_zone",
    "turb_minutes_in_zone", "wl_minutes_in_zone",
    "temp_min", "temp_max", "ph_min", "ph_max",
    "do_min", "do_max", "turb_min", "turb_max", "wl_min", "wl_max",
    "growth_stage",
]

le_stage = LabelEncoder()
df["growth_stage"] = le_stage.fit_transform(df["growth_stage"])

# ── Hakbang 3: grouped split, parehong dahilan (walang leakage) ────────
X = df[FEATURE_COLS]
y = df[TARGET_COLS]          # 5 continuous columns — multi-output regression
groups = df["seq_id"]

gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)
train_idx, test_idx = next(gss.split(X, y, groups=groups))

X_train, X_test = X.iloc[train_idx], X.iloc[test_idx]
y_train, y_test = y.iloc[train_idx], y.iloc[test_idx]

print(f"\n[OK] Train: {len(X_train):,} rows ({df['seq_id'].iloc[train_idx].nunique()} sequences)")
print(f"[OK] Test:  {len(X_test):,} rows ({df['seq_id'].iloc[test_idx].nunique()} sequences)")

# ── Hakbang 4: train MULTI-OUTPUT Random Forest REGRESSOR ──────────────
# Parehong native multi-output support gaya ng Classifier kanina —
# isang model, 5 numeric outputs sabay-sabay.
print("\n[Training] Multi-output Forecast Regressor (5 minutes ahead)...")
model = RandomForestRegressor(
    n_estimators=200,
    max_depth=None,
    min_samples_split=5,
    random_state=42,
    n_jobs=-1,
)
model.fit(X_train, y_train)

# ── Hakbang 5: evaluate per sensor — REGRESSION metrics, hindi accuracy ─
# MAE (Mean Absolute Error) = average na pagkakamali sa parehong unit ng
# sensor (e.g. "nagkakamali kami ng 0.4°C on average" para sa temp)
# R² = gaano kalapit ang predictions sa totoong values (1.0 = perfect,
# 0 = parang kinuha lang average, negative = mas masama pa sa average)
y_pred = model.predict(X_test)   # shape: (n_samples, 5)

print("\n[Results] Forecast error per sensor (5 minutes ahead):")
for i, sensor in enumerate(SENSOR_KEYS):
    mae = mean_absolute_error(y_test.iloc[:, i], y_pred[:, i])
    r2 = r2_score(y_test.iloc[:, i], y_pred[:, i])
    unit = {"temp": "°C", "ph": "", "do": "mg/L", "turb": "NTU", "wl": "cm"}[sensor]
    print(f"  {sensor.upper():5s} — MAE: {mae:.3f}{unit}  |  R²: {r2:.4f}")

# ── Hakbang 6: grouped cross-validation (manual loop, multi-output) ────
print("\n[5-Fold GROUPED Cross-Validation] (per sensor, MAE)")
gkf = GroupKFold(n_splits=5)
fold_mae = {s: [] for s in SENSOR_KEYS}

for tr_idx, va_idx in gkf.split(X, y, groups=groups):
    fold_model = RandomForestRegressor(
        n_estimators=200, max_depth=None, min_samples_split=5,
        random_state=42, n_jobs=-1,
    )
    fold_model.fit(X.iloc[tr_idx], y.iloc[tr_idx])
    fold_pred = fold_model.predict(X.iloc[va_idx])
    for i, sensor in enumerate(SENSOR_KEYS):
        mae = mean_absolute_error(y.iloc[va_idx].iloc[:, i], fold_pred[:, i])
        fold_mae[sensor].append(mae)

for sensor in SENSOR_KEYS:
    scores = np.array(fold_mae[sensor])
    unit = {"temp": "°C", "ph": "", "do": "mg/L", "turb": "NTU", "wl": "cm"}[sensor]
    print(f"  {sensor.upper():5s}: MAE {scores.mean():.3f}{unit} (+/- {scores.std():.3f})")

# ── Hakbang 7: save model + encoder ──────────────────────────────────────
os.makedirs("models", exist_ok=True)
with open("models/forecast_regressor.pkl", "wb") as f:
    pickle.dump(model, f)
with open("models/forecast_regressor_encoders.pkl", "wb") as f:
    pickle.dump({"growth_stage": le_stage}, f)
with open("models/forecast_regressor_feature_cols.pkl", "wb") as f:
    pickle.dump(FEATURE_COLS, f)

print("\n[OK] Saved:")
print("  models/forecast_regressor.pkl              <- multi-output Random Forest Regressor")
print("  models/forecast_regressor_encoders.pkl      <- growth_stage encoder")
print("  models/forecast_regressor_feature_cols.pkl  <- feature column list")