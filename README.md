# CrayCare — Smart Crayfish Aquaculture System

CrayCare is a Flutter and Firebase application for monitoring crayfish pond conditions, managing feeding and tank controls, and recording growth and production data.

## Technology stack

| Layer | Technology |
|---|---|
| Mobile application | Dart and Flutter |
| Backend | Firebase Authentication, Cloud Firestore, Cloud Functions, FCM, and Storage |
| Hardware | ESP32 firmware using C++ and the Arduino framework, built with PlatformIO |
| ML development | Python and scikit-learn training scaffold for Random Forest water-quality classification |

## Current water-quality ML status

The dashboard contains a **Water Quality Classification** card. The Random Forest training materials and dataset are in [`ML_WQC/`](ML_WQC/). Its Firebase runtime classifier is grouped under `functions/backend/water_quality_classification/`; other backend functions remain in the same deployable package.

The previous unsupervised Water Quality Anomaly Detection implementation and its reports are preserved under [`archive/water_quality_anomaly_detection_2026-11-10/`](archive/water_quality_anomaly_detection_2026-11-10/). Those files are not part of the active Flutter or Firebase Functions source configuration.

## Sensor and application flow

The ESP32 sends sensor readings to Firebase. Cloud Functions route device data to the assigned tank, and the Flutter app presents live readings, history, charts, controls, feeding schedules, and production records. Sensor-threshold alerts and actuator safety checks remain separate from the pending ML classifier.

## Firestore documentation

- [`docs/FIRESTORE_STRUCTURE_ACTUAL.md`](docs/FIRESTORE_STRUCTURE_ACTUAL.md)
- [`docs/craycare_erd.dbml`](docs/craycare_erd.dbml) — logical data model

## ESP32 firmware

The PlatformIO project is in [`esp/CrayCare/`](esp/CrayCare/). Its default environment is `esp32dev_main`.

- Pinout: [`esp/CrayCare/PINS_CONFIG.txt`](esp/CrayCare/PINS_CONFIG.txt)
- Serial commands: [`esp/CrayCare/SERIAL_COMMANDS.txt`](esp/CrayCare/SERIAL_COMMANDS.txt)

## Deployment commands

```bash
# Firestore rules and indexes
firebase deploy --only firestore:rules,firestore:indexes

# Configured backend Cloud Functions
firebase deploy --only functions

# Flash ESP32
cd esp/CrayCare && pio run -e esp32dev_main -t upload
```

Removing the old ML codebase from local deployment configuration does not remove an already deployed Cloud Function. Check and retire any existing WQAD Cloud Function separately before treating the cloud deployment as disabled.
