# CrayCare Full Codebase Regression Audit

**Date:** 2026-08-14

## Scope

Reviewed the current Flutter/Dart application, Firestore integration and rules, Node notification/routing functions, Python Water Quality Anomaly Detection pipeline, ESP32 production firmware, test tools, schemas, indexes, and deployment configuration.

## Validation results

- All 57 Dart source files parse successfully with Dart 3.13.
- Node Cloud Function syntax passes.
- Python ML modules compile.
- The pinned Isolation Forest model loads and produces an anomaly-detection result.
- Firestore rules load in the emulator.
- Strict role/device authorization emulator tests pass.
- ESP32 `esp32dev_main` production build previously passed after the integration changes (RAM 15.2%, flash 35.7%).
- JSON schema/index/config files parse successfully.
- Updated Node test tools pass syntax checks.

## Mismatches corrected in this regression

1. **Admin access did not match the documented role.** Admin UI was account/hardware-only, but rules allowed broad owner operational access. Admin is now denied owner sensor readings/history, thresholds, controls, logs, ML results, and production records. Admin retains account/hardware management and limited tank-root/seed provisioning required for assignment.
2. **Sensor threshold save used short document IDs.** `temp/ph/do/turb/waterlevel` did not match the canonical/rule IDs. Writes now use `temperature/ph_level/dissolved_oxygen/turbidity/water_level` and occur once through the canonical batch writer.
3. **Scheduled feed confirmation used the wrong log phrase.** Flutter expected `Auto feed dispensed`, while firmware writes `Dispensed feed (Scheduled)`. Both canonical and legacy phrases are now recognized, preventing false skipped-feed status/logs.
4. **Batch initialization could overwrite an existing document or corrupt an active batch during edit.** Batch names are validated, duplicates are rejected, existing names cannot be silently changed, editing is blocked after operational records exist, and new-batch creation/superseding/tank-pointer updates are atomic.
5. **ML Firestore export did not match the training CSV.** Export now maps `recorded_at` to `timestamp`, emits the exact 16-column feature source schema, drops incomplete records, and uses ADC/service-account credentials through standard Firebase Admin initialization.
6. **Test tools targeted removed collections.** Mock ingestion, Water Quality Anomaly Detection seeding/checking, and threshold configuration now use current staging/tank paths and current snake_case fields.
7. **Schema documents contradicted runtime fields and permissions.** Production, notification, ML, history aggregate, feeder, actuator, and security sections were aligned.
8. **Duplicate generated project scaffolding existed.** Stale root PlatformIO and root Functions lock scaffolding were removed; the canonical firmware project remains `esp/CrayCare/`.
9. **Generated artifacts had been tracked despite ignore rules.** Tracked Node dependency and Android build outputs are removed from source control; ignore coverage was corrected.
10. **Minor hardware documentation typo and obsolete reminder wording were corrected.**

## Canonical role contract

- **Admin:** manages accounts/status and assigns/reassigns/unassigns hardware. Admin may provision missing tank metadata/seed docs but cannot access owner operational data or controls.
- **Owner:** exclusively reads and manages the assigned tank's operational data, thresholds, controls, feeding, ML result, and production/growth records.
- **ESP device:** reads only assigned-tank device configuration, reports physical state/logs, consumes pending commands, and writes fixed staging ingestion documents.
- **Admin SDK Cloud Functions:** route canonical readings, create server notifications, and write ML output.

## Remaining intentional limitations / deployment work

1. **Anonymous ESP identity:** suitable for a controlled thesis/demo, but staging can be attempted by another anonymous client. Public production should use provisioned custom device credentials or a protected HTTPS ingestion API.
2. **Synthetic ML training:** the Water Quality Anomaly Detection model is bootstrap-tested with synthetic operating patterns and holdout anomaly events, not yet field-validated using actual Cherax RAS history. Synthetic event labels are used only for offline evaluation and are never supplied to model fitting.
3. **Estimated feeder grams:** 20 g per servo cycle is an estimate until physically calibrated or measured with a load cell.
4. **Cold-boot offline time:** cached schedules work during an outage after time synchronization; reliable scheduling after a powered-off cold boot without internet requires an RTC such as DS3231.
5. **Android distribution:** package ID remains `com.example.craycare` because it matches the registered Firebase Android app, and release builds currently use debug signing. A unique Firebase-registered package and release keystore are required for formal store distribution.
6. **Test coverage:** authorization integration tests were executed, but the repository still lacks a complete committed Flutter widget/unit suite and physical hardware-in-the-loop tests.
7. **Legacy firmware variants:** only `esp32dev_main` is the production target; backup RTDB/local variants are retained as references and are not guaranteed to match production behavior.

## Overall result

No unresolved critical cross-layer schema/path mismatch was found after correction. The current code is consistent for controlled development and thesis demonstration, subject to real Firebase deployment smoke tests, physical sensor calibration, and the intentional limitations above.
