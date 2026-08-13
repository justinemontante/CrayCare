# CrayCare Repository-Wide Consistency Audit

**Audit date:** 2026-08-13

**Scope:** Flutter application, ESP32 production firmware, Node.js Cloud Functions, Python ML Cloud Function, Firestore rules/indexes, schemas/documentation, dependency manifests, and available tests.

## Remediation status

The concrete code mismatches identified below were repaired in the same audit pass: hardware pin mapping and HC-SR04 implementation, analytics timestamps, duplicate scheduling, feed quantity handling, sensor fault checks/calibration, ML missing-data behavior and schema, runtime documentation, dependency updates, and Firestore rule scoping. The production ESP32 environment now compiles successfully. Remaining deployment prerequisites are physical wiring/calibration, Firebase rules/emulator acceptance testing, Flutter analysis on a machine with the Flutter SDK, and replacing anonymous device authentication with a provisioned device identity for public production use.

## Executive summary

The repository had a coherent intended architecture, but was **not internally consistent enough for production deployment before the remediation changes**. The most serious issues found were:

1. Production firmware pin assignments and sensor types do not match the hardware documentation.
2. Firestore's `isEspSession()` treats every signed-in account as an ESP device, allowing cross-tank device operations.
3. Historical analytics reads `timestamp`, while canonical history records contain `recorded_at`; historical charts can sort/plot records incorrectly.
4. Feeding can be triggered by both ESP-local scheduling and Android WorkManager, creating duplicate physical feed cycles and false “dispensed” logs.
5. The runtime ML schema/path contradicts the README, Firestore documentation, and repository memory notes.

The production firmware and Node/Python source files pass basic syntax checks where tools are available. Flutter and PlatformIO compilation could not be run because Flutter/Dart and PlatformIO are not installed in the audit environment. There are effectively no automated application/firmware tests in `test/` or `esp/CrayCare/test/`.

---

## Critical findings

### C1. Production firmware pinout does not match `PINS_CONFIG.txt`

**Documentation:** `esp/CrayCare/PINS_CONFIG.txt`

- DO: GPIO 36
- pH: GPIO 35
- Turbidity: GPIO 34
- Temperature: GPIO 4
- HC-SR04 water level: TRIG GPIO 32, ECHO GPIO 33

**Production firmware:** `esp/CrayCare/src/main.cpp:349-353`

- DO: GPIO 35
- pH: GPIO 32
- Turbidity: GPIO 34
- Temperature: GPIO 4
- Water level: one analog input on GPIO 33

There are several direct conflicts:

- Firmware DO GPIO 35 is documented as pH.
- Firmware pH GPIO 32 is documented as HC-SR04 TRIG.
- Firmware does not use an HC-SR04 TRIG/ECHO pair at all.
- `FEEDER_HOPPER_SENSOR_PIN` is GPIO 36 (`main.cpp:357`), while documentation assigns GPIO 36 to DO.

**Impact:** Sensors may read the wrong physical channels. The water-level implementation cannot work with the documented HC-SR04 wiring.

**Required fix:** Select one authoritative hardware design, then update `main.cpp`, `PINS_CONFIG.txt`, and `SERIAL_COMMANDS.txt` together. Do not flash the current production environment until this is resolved.

### C2. Firestore device authorization is equivalent to “any authenticated user”

`firestore.rules:50` defines:

```text
function isEspSession() { return isSignedIn(); }
```

This predicate grants device privileges at numerous cross-tank paths:

- Write canonical sensor readings for any tank (`94-103`)
- Read thresholds for any tank (`109-110`)
- Read/update actuator state for any tank (`115-121`)
- Create actuator logs for any tank (`123-127`)
- Write feeder status for any tank (`129-132`)
- Read schedules for any tank (`133-135`)
- Read/delete pending commands for any tank (`137-140`)
- Create feeder logs for any tank (`142-145`)
- Write ingestion staging data (`179-186`)

Because regular app users are signed in, they satisfy `isEspSession()`. Anonymous Firebase sessions also satisfy it.

**Impact:** A malicious or compromised user can spoof readings, manipulate another tank's device state, inspect schedules, or delete another tank's pending feed command if the path is known.

**Required fix:** Give the ESP a verifiable device identity, such as a custom claim (`device == true`) issued only by a trusted backend, or replace direct Firestore device writes with an authenticated HTTPS ingestion endpoint. Restrict device operations to the currently assigned tank.

### C3. Historical analytics timestamp field mismatch

The Node router writes canonical history time as `recorded_at` (`functions/notifications/index.js:282-292`, history write at `335-338`). The ML pipeline also queries `recorded_at` (`functions/ml/main.py:107-112`).

However:

- `SensorService.fetchHistoryRange()` sorts using `record['timestamp']` (`lib/services/sensor_service.dart:530-532`).
- `AnalyticsScreen` sorts and parses `record['timestamp']` (`lib/screens/analytics_screen.dart:211-220`).
- `_parseTimestamp()` only accepts numeric values, not Firestore `Timestamp` (`analytics_screen.dart:337-340`).

**Impact:** Canonical historical documents sort as zero and parse as year 2000. The 24-hour labels can be wrong, while 7-day/30-day bucket matching can produce empty/incorrect charts even though Firestore contains valid records.

**Required fix:** Use `recorded_at` as the canonical field and add a shared parser supporting Firestore `Timestamp`, integer epoch seconds, integer epoch milliseconds, and ISO strings. Use it for filtering, sorting, and labels.

### C4. Duplicate scheduled feeding paths can physically feed twice

There are two independent dispatchers:

1. ESP-local scheduler reads `feeder_schedules` and directly calls `startFeed("scheduled")` at the configured minute (`esp/CrayCare/src/main.cpp:1497-1520`).
2. Android WorkManager runs every 15 minutes (`lib/services/background_service.dart:9-20`) and `BackgroundHelper.checkAndDispatchFeeding()` creates a `feed_now` pending command for schedules up to 15 minutes old (`background_helper.dart:77-142`).

The ESP consumes that command and calls `startFeed("manual")` (`main.cpp:1366-1374`). If the background command arrives more than one minute after the local schedule, the ESP's one-minute guard does not prevent another cycle.

Additionally, `BackgroundHelper` writes an “Auto feed dispensed” log immediately after creating the command (`background_helper.dart:154-165`), before the ESP confirms physical completion. The ESP later writes another completion log (`main.cpp:1605-1612`).

**Impact:** Overfeeding, duplicate logs, and false successful-dispense records.

**Required fix:** Choose one source of truth. Recommended: let the ESP execute stored schedules locally for offline resilience, and remove background command dispatch. The app/backend should only send reminders and observe ESP-confirmed logs. Alternatively, use a server dispatcher with an atomic idempotency record and disable ESP-local schedule execution.

---

## High-severity findings

### H1. Documented HC-SR04 water-level behavior is absent from production firmware

`PINS_CONFIG.txt` and `SERIAL_COMMANDS.txt:112-124` describe ultrasonic distance measurement:

```text
waterDepth = sensorHeight - distToSensor
```

Production `main.cpp:1089-1101` instead reads analog voltage on GPIO 33 and linearly maps 0–3.3 V to 0–30 cm. No trigger pulse or echo timing exists.

**Impact:** The documented water-level sensor cannot produce valid readings with production firmware.

### H2. Production calibration/diagnostic commands are mostly documentation-only

`SERIAL_COMMANDS.txt` documents pH calibration, DO calibration, HC-SR04 calibration, threshold setting, sensor enable/disable, raw output, plotter output, and debug commands. The production `main.cpp` command handler (`approximately 1178-1215`) implements only:

- `RESET_WIFI`
- `FEED`
- `n1on/n1off`, `n2on/n2off`, `n3on/n3off`
- `relay status`

The documented pH/DO/water-level calibration commands are found in legacy/standalone firmware variants, not the default `esp32dev_main` build.

**Impact:** Operators following the production documentation cannot calibrate production readings. Default pH/DO coefficients remain hard-coded.

### H3. DO, pH, and water-level “sensor OK” flags do not detect disconnection or invalid signals

`main.cpp:1063-1101` marks each analog sensor OK after every read and constrains the result into a plausible numeric range. There are no electrical validity checks, open-circuit checks, calibration-state checks, or jump filtering for these sensors.

Examples:

- DO is simply `voltage * 4.0 + offset`.
- pH is simply `-5.70 * voltage + 21.34`.
- Water level is linear 0–3.3 V → 0–30 cm.

**Impact:** A disconnected or miswired sensor can still look like a valid measurement and influence alerts, actuators, and ML classification.

### H4. Feed quantity (`grams`) is accepted by the app but ignored by firmware

Flutter writes `grams` into pending commands and schedules (`lib/services/feeder_service.dart:257-278`, `330-350`). Production firmware's pending-command parser only reads action and trigger mode (`main.cpp:1336-1363`); it never reads `grams`. Status always reports 20.0 g after a feed (`main.cpp:1410`). Servo output is controlled by a fixed cycle count.

**Impact:** The UI suggests variable feeding quantity, but physical dispensing remains fixed. Logs/status can claim a quantity that was not actually measured or applied.

### H5. ML runtime path/schema contradicts current documentation

**Actual runtime:**

- Scheduled hourly function: `functions/ml/main.py:188-202`
- Output: `tanks/{tankId}/ml_predictions/current` (`main.py:183-184`)
- Flutter reads that same path (`health_risk_service.dart:158-162`, `ml_service.dart:79-82`)

**Documentation/memory says:**

- Event-driven trigger on latest sensor writes
- Output at `tanks/{tankId}/health_risk/current`
- See `README.md:16-22`, `docs/FIRESTORE_STRUCTURE_ACTUAL.md:122-124`, and `.agents/memory/ml-pipeline.md:6-41`

Firestore rules contain `ml_predictions` but no `health_risk` rule (`firestore.rules:151-156`).

**Impact:** Deployment/debugging instructions are misleading. Anyone implementing from the documentation will target a nonexistent runtime path and trigger model.

### H6. `risk_score` was supposedly removed but is still emitted and consumed

Repository memory explicitly states the score was removed from all runtime layers (`.agents/memory/wqc-rename.md:3-22`). Actual code:

- Emits `risk_score` (`functions/ml/features.py:325-335`)
- Emits zero score for insufficient data (`functions/ml/main.py:160-174`)
- Parses it in Flutter (`lib/services/health_risk_service.dart:55`)

**Impact:** The declared WQC contract and actual API differ. Thesis terminology can regress from classification to a risk-index interpretation.

### H7. ML missing-value fallback can turn an absent sensor into a severe hazard

`functions/ml/main.py:117-140` defaults absent legacy sensor fields to `0.0`. For DO, a missing reading becomes 0 mg/L, which is a critical oxygen hazard. Missing pH/water values also become physically meaningful zeroes rather than missing data.

**Impact:** Partial sensor history or disabled sensors can generate false High/Critical classifications.

**Required fix:** Validate all required fields. Mark assessment `Insufficient` when required sensors are missing/invalid, or use an explicitly trained missing-value strategy with sensor-availability features.

### H8. Node production dependencies contain known vulnerabilities

`npm audit --omit=dev` reported:

- 1 high-severity vulnerability
- 9 moderate-severity vulnerabilities
- 10 total

The high issue is in `fast-xml-parser`; several moderate issues flow through `firebase-admin`, Google Cloud packages, and `uuid`. Installed lock versions include `firebase-admin 12.7.0` and `firebase-functions 5.1.1`.

**Required fix:** Upgrade Firebase Admin/Functions and regenerate/test the lock file. Review breaking changes before deployment.

---

## Medium-severity findings

### M1. New 12:00 AM schedules get the wrong `timeValue`

`FeederService.addSchedule()` calculates `timeValue` without converting 12 AM to 0 (`lib/services/feeder_service.dart:334-348`). `editSchedule()` correctly includes the 12 AM conversion (`396-410`).

**Impact:** A newly created 12:00 AM schedule is stored as minute 720 (12:00 noon) for firmware, while other code parsing `time` + `AM` may treat it as midnight.

### M2. WorkManager claims “dispensed” before physical confirmation

Separate from duplicate dispatch, `background_helper.dart:154-165` records successful dispensing immediately after queueing a command. Network success is not hardware success.

**Impact:** Audit logs are not reliable evidence that food was physically dispensed.

### M3. Actuator UI writes an assumed physical state

`DatabaseService.saveActuatorMode()` writes `current_state = on` for both `on` and `auto` (`lib/services/database_service.dart:284-290`). In auto mode, firmware may correctly decide the relay should be off and overwrite it later.

**Impact:** The UI/database can temporarily report a physical state that never occurred. Only firmware should write `current_state`; the app should write `control_mode` only.

### M4. Latest routing uses merge and can preserve stale fields

`onSensorIngestionWrite` uses `.set(..., { merge: true })` (`functions/notifications/index.js:312-315`). If a future firmware payload omits a disabled sensor, the old canonical value remains.

**Impact:** Disabled/missing sensor fields may look current. Use a full replace for a complete snapshot, or explicitly delete unavailable fields.

### M5. Firestore documentation has additional field-shape mismatches

Examples:

- `feeder_dispatched` docs describe `scheduleIds` array and `dispatched_at` (`FIRESTORE_STRUCTURE_ACTUAL.md:119-120`), while app code writes dynamic schedule-ID boolean fields.
- Batch/production summary sections use camelCase field names (`lines 128-139`), while actual app records use snake_case (`tank_service.dart`). A later appendix partially documents snake_case, leaving contradictory definitions in one file.
- Notification docs mention old aliases in places while runtime uses `notif_type`, `body`, `created_at`, `is_read`.

### M6. Water-level agency reference table contains impossible ordering

`functions/ml/agency_standards.py:151-166` states:

- Optimal: 15–20 cm
- Good: 100–180 cm
- Fair: 10–25 cm
- Poor: 50–220 cm

These ranges overlap and are not ordered from optimal to poor. Runtime feature code uses 15–20 cm, so the reference table does not match actual scoring.

### M7. Saved XGBoost artifact is pickle/joblib-version sensitive

`python functions/ml/predict.py` runs after installing XGBoost 3.x, but XGBoost warns that the serialized model was produced by an older version and recommends exporting via `Booster.save_model()` before loading in a newer version.

**Impact:** A future Cloud Function dependency resolution can break or subtly change model loading. Pin exact tested versions and use XGBoost's stable model format where possible.

### M8. ML `source` field does not match documented enum

Documentation says `source` is `ml`, `rule_based`, or `insufficient_data`. Actual successful predictions use long citation strings from `recommendations.json`; insufficient data uses `System` (`main.py:169`).

**Impact:** Consumers cannot rely on the documented enum to identify inference mode. `analysis_mode` currently carries that information instead.

### M9. ESP firmware performs blocking analog sampling in the main control loop

Each analog read takes roughly 250 ms (50 samples × 5 ms), and DO, pH, turbidity, and water-level reads occur in the same loop, in addition to network calls. The feeder state machine shares this loop.

**Impact:** Relay/servo timing and responsiveness can jitter, especially during slow Firestore operations. Sensor sampling should be non-blocking or separated from time-sensitive actuator control.

---

## Low-severity / maintenance findings

### L1. Production firmware comments contradict its own architecture

At `main.cpp:79-80`, comments say all paths route directly to tanks and that no intermediate `sensorIngestion` exists. The same file actually writes `sensorIngestion/current` and its history subcollection (`883`, `916`). Other top-of-file comments correctly describe staging.

### L2. Firmware comments still call enabled sensors placeholders

`main.cpp:17-24` says only temperature/turbidity are active and calls DO/pH/water level placeholders, while compile-time flags enable all three (`361-363`). Clarify whether they are production-ready or experimental.

### L3. Documentation uses percent for water level in one firmware log

`main.cpp:726` prints water thresholds with `%`, while the app, model, and sensor defaults use centimeters.

### L4. Two Flutter services listen to the same ML document

`MlService` and `HealthRiskService` both resolve the tank and subscribe to `ml_predictions/current`. This is not functionally wrong, but duplicates reads/state and increases maintenance risk.

### L5. No meaningful automated application/firmware test suite

`test/README` and `esp/CrayCare/test/README` are placeholders. `test_tools` contains manual Node scripts rather than deterministic CI tests.

---

## Validation performed

| Check | Result |
|---|---|
| Python source compilation (`compileall`) | PASS |
| Node Cloud Function syntax (`node --check`) | PASS |
| JSON parsing for Firebase/config/recommendations files | PASS |
| Local ML prediction with XGBoost 3.x | PASS, with model-serialization warning |
| `npm audit --omit=dev` | FAIL: 1 high + 9 moderate vulnerabilities |
| Flutter static analysis/build | NOT RUN: Flutter/Dart unavailable |
| ESP32 PlatformIO build | NOT RUN: PlatformIO unavailable |
| Firebase emulator/rules tests | NOT RUN: Firebase CLI unavailable |
| Automated app/firmware unit tests | No substantive tests present |

Example local model output was **Moderate, 100% confidence, pH driver** on the final synthetic dataset row. This confirms artifact execution, not real-world accuracy.

---

## Recommended repair order

1. **Freeze hardware flashing** until pin assignments and the water-level sensor type are made authoritative.
2. **Fix Firestore device authentication/authorization** before exposing the project beyond a controlled demo.
3. **Fix historical timestamp parsing** (`recorded_at`) so analytics and evidence collection are reliable.
4. **Choose exactly one scheduled-feed dispatcher** and make feed execution idempotent and hardware-confirmed.
5. **Implement production calibration and sensor-fault detection** for DO, pH, and water level.
6. **Decide the canonical ML contract:** hourly vs event-driven, `ml_predictions` vs `health_risk`, and whether `risk_score` exists.
7. **Reject incomplete ML samples** instead of filling absent sensors with zero.
8. **Make grams functional or remove the quantity control/claims** from the app.
9. **Upgrade vulnerable Node dependencies** and pin/test Python/XGBoost versions.
10. **Update all documentation from the corrected runtime schema**, then add CI tests for routing, rules, analytics parsing, feeder idempotency, and ML missing data.

## Overall assessment

- **Intended architecture:** Good prototype structure
- **Current cross-layer consistency:** Major identified mismatches repaired; deployment validation remains
- **Safe for controlled development demo:** After hardware pin/wiring verification and sensor calibration
- **Safe for production/unsupervised operation:** No
- **ML claim maturity:** Prototype classifier validated on synthetic, formula-derived labels; not field-validated
idated
