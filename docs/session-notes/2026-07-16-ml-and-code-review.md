# Session Notes — July 16, 2026

Debugging session covering the ML pipeline, a security issue, and a broader
code review. Summarized here for reference; see the linked commits for full
diffs.

## 1. ML crash fix — `functions/ml/main.py`

**Bug:** `raw_pred.shape[1] > 1` threw `IndexError` on every single
prediction in production, because `XGBClassifier.predict()` returns a 1D
array. Every `on_sensor_update` invocation was crashing.

**Fix:** matched the safe check already used in `predict.py`:
`len(raw_pred.shape) == 2`.

**Commit:** `116963f`

## 2. Security — leaked `tmp_auth_export.json`

**Issue:** a Firebase Auth export containing real user emails and a
password hash + salt for the `esp32@craycare.com` service account was
committed, unignored, to this public repo.

**Fixed so far:**
- Removed the file from the current commit
- Added `.gitignore` rules for auth exports, `.env`, `*.pem`, `*.key`

**Still needed (manual, outside this session):**
- Rotate the `esp32@craycare.com` password in the Firebase console
- Purge the file from git history with `git filter-repo` (it's still
  recoverable from old commits until this is done)

**Commit:** `dd5ffab`

## 3. ML model retraining — was never actually trained properly

Three compounding issues, all fixed:

1. `sensor_labeled.csv` was stale — still had the old `csi_score`/
   `csi_class` columns from before the CSI→WQRI rename, so
   `train_model.py` couldn't even run (`KeyError: wqri_class`).
2. The deployed `wqri_model.joblib` was a renamed leftover file, never
   actually produced by the current `train_model.py` (mismatched
   regressor vs. classifier).
3. `generate_dataset.py` injected each fault type (aerator failure, heat
   spike, pH drop, overfeeding) only **once** across the 45-day synthetic
   run, so later `TimeSeriesSplit` CV folds tested on fault patterns the
   model had never seen in training. Fixed by repeating each fault kind
   4x, staggered + jittered across the timeline.
4. `build_features()` only exposed boolean hour-count features and
   rolling averages — never the continuous hazard magnitude that
   `compute_wqri_score()` actually sums to build the label. Added
   `*_hazard_roll6h` features mirroring the WQRI formula's own per-sensor
   hazard computation.

**Result:**

| Metric | Before | After |
|---|---|---|
| Mean CV accuracy | 51.0% | 91.2% |
| High-class recall | 0% | ~100% |
| Final holdout accuracy | 71% | 100% |
| vs. rule-based baseline (96%) | worse | better |

**Commit:** `1ac853f` (also includes the `movable_ai_logo.dart` "CSI v1" →
"WQRI v1" label fix)

## 4. Code review findings (in progress)

| # | File | Bug | Severity | Status |
|---|---|---|---|---|
| 1 | `functions/ml/export_firestore.py` | Wrong Firestore collection path (`sensor_logs` vs. actual `sensorReadings/history/{date}`) | Medium | Open |
| 2 | `lib/services/ml_service.dart` | Listens to wrong collection (`mlPredictions` vs. `healthRisk`); appears to be dead code — no UI reads its state | Low–Medium | Open |
| 3 | `lib/services/device_log_service.dart` | Race condition: if `init()` runs before Firebase Auth resolves the persisted session, device logs silently never load for the rest of the app session | **High** | Open |
| 4 | `lib/services/auth_service.dart` | `changePassword()` retries the exact same failed call on `requires-recent-login` — no-op retry | Low | Open |
| 5 | `lib/services/database_service.dart` | `getSensorHistory()` uses a `collectionGroup` name that doesn't match any actual subcollection; dead code, unused | Low | Open |

Code review was still in progress (services reviewed: `esp_service`,
`storage_service`, `background_service`, `ml_service`, `device_log_service`,
`settings_service`, `auth_service`, `database_service`,
`background_helper`). Not yet reviewed: `sensor_service.dart`,
`feeder_service.dart`, `tank_service.dart`, `notification_service.dart`,
`functions/notifications/index.js`, and the `lib/screens`/`lib/widgets`
UI layer.
