# CrayCare — Project Overview

Flutter + Firebase aquaculture monitoring app for crayfish farming. Tracks water quality via ESP32 sensors, runs an XGBoost ML classification pipeline via Python Cloud Functions, and pushes results to a Flutter mobile UI.

---

## Stack

| Layer | Tech |
|---|---|
| Mobile | Flutter (Dart), Android target |
| Backend | Firebase (Firestore, Auth, Cloud Functions) |
| ML | Python 3 + XGBoost, deployed as Cloud Function |
| Hardware | ESP32 sensors (pH, DO, temperature, turbidity, water level) |
| Repo | GitHub → `justinemontante/CrayCare`, branch `main` |

---

## Architecture

```
ESP32 → writes sensorReadings/latest
         └─ triggers Python Cloud Function (functions/ml/main.py)
                └─ fetches last 24h from sensorReadings/history/{date}
                └─ runs XGBoost classification
                └─ writes to healthRisk/latest
                       └─ Flutter HealthRiskService listens via real-time snapshot
                              └─ updates UI (dashboard card + AI insights sheet)
```

No polling. Purely event-driven on new sensor records (every ~10 min).

---

## ML Pipeline (functions/ml/)

| File | Role |
|---|---|
| `generate_dataset.py` | Generates synthetic training data (12,960 rows × 90 days @ 10-min intervals, 8 fault types) |
| `train_model.py` | Trains XGBoost classifier → saves `wqc_model.joblib` (92% accuracy) |
| `features.py` | Feature engineering + `compute_wqc_score()` + `predict_wqc()` |
| `main.py` | Cloud Function entry point — `_predict_wqc()`, reads Firestore, writes result |
| `predict.py` | Local test runner for end-to-end verification |
| `agency_standards.py` | Reference thresholds (DENR, DA-BFAR, FAO) |
| `wqc_model.joblib` | Trained model artifact (committed to repo) |

**Model output written to `healthRisk/latest`:**
```
level       — "Low" | "Moderate" | "High" | "Critical"
confidence  — integer 0–100
driver      — sensor name (e.g. "pH", "DO")
problem     — short description
insight     — detailed analysis with citations
action      — recommended corrective action
source      — "ml" or "insufficient_data"
timestamp   — ISO string
```

> ⚠️ NO `score` field — removed. The 0–100 score was internal only.
> ⚠️ Model is called WQC (Water Quality Classification), NOT WQRI.

---

## Key Firestore Collections

| Collection | Purpose | UID isolation |
|---|---|---|
| `users/{uid}` | User profiles | ✓ by path |
| `users/{uid}/batches/{batchId}/...` | Tank batch data (new structure) | ✓ by path |
| `batches/`, `sampling/`, `mortality/`, `activities/`, `harvests/` | Old flat structure (transitional) | ✓ by `uid` field |
| `sensorReadings/latest` | Latest ESP32 reading | ✓ by `ownerUid` stamp |
| `sensorReadings/history/{date}/{doc}` | Historical readings | ✓ by `ownerUid` stamp |
| `healthRisk/latest` | ML classification result | ⚠️ no uid filter (single device) |
| `config/{uid}` | Per-user sensor thresholds | ✓ by path |
| `config/default` | Shared ESP32 defaults | ⚠️ mirrored from user write |
| `feederSchedules`, `feederStatus`, `feederCommands` | Feeder control | ⚠️ no uid filter |
| `notifPrefs/{uid}` | Notification preferences | ✓ by path |
| `notifications/{docId}` | Per-user notifications | ✓ by `uid` field |

---

## Flutter Structure

```
lib/
  main.dart
  firebase_options.dart
  models/          — CrayfishBatch, NotificationItem, SensorDefaults, ControlTypes
  screens/         — dashboard, analytics, controls, production, settings, login, admin
  services/        — auth, sensor, feeder, tank, health_risk, ml, notification, settings, database, ...
  widgets/
    analytics/     — movable_ai_logo.dart (AI insights sheet), analytics_charts.dart
    dashboard/     — health_risk_card.dart
    controls/      — feeder_tab.dart, devices_tab.dart
    production/    — crayfish batch/sampling/harvest UI
    settings/      — threshold settings, profile, notif prefs
  theme/           — AppColors, AppTheme
```

### Key service: HealthRiskService (`lib/services/health_risk_service.dart`)
- `HealthRiskResult` model — fields: `level`, `confidence`, `driver`, `problem`, `action`, `source`, `timestamp`
- **No `score` field** (removed — it no longer comes from Firestore)
- Listens to `healthRisk/latest` via real-time Firestore stream

### Key widget: movable_ai_logo.dart
- Floating AI logo on analytics screen → opens bottom sheet with AI insights
- Replaced `_buildScoreCard()` (showed 0–100 number) with `_buildClassificationCard()` (shows level badge + confidence % + driver chip)

---

## Firestore Rules Summary (`firestore.rules`)
- `sensorReadings` — stamped with `ownerUid` by Cloud Function; ESP writes unauthenticated
- `feederSchedules/Status/Commands` — any authenticated user (no uid filter — known limitation)
- `healthRisk` — any authenticated user can read (no uid filter — single device assumption)
- `config/deviceOwner` — admin-only write; identifies which uid owns the hardware

---

## Known Limitations / Future Work
- `feederSchedules`, `feederStatus`, `feederDispatched`, `deviceModes` have no per-uid isolation — multi-tenant risk
- `healthRisk/latest` and `config/default` are global (single-device assumption)
- Old flat collections (`/batches`, `/sampling`, etc.) still exist for migration — remove after migration script runs
- `wqri_model.joblib` was deleted; `wqc_model.joblib` is the active model

---

## User Preferences
- Push to GitHub after every significant change
- Keep WQRI terminology fully removed (use WQC everywhere)
- No `score` field anywhere in the codebase
