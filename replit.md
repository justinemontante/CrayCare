# CrayCare — Project Overview

CrayCare is a Flutter and Firebase smart-aquaculture application for crayfish farming. It monitors ESP32 sensor data, manages tank controls and feeding, and stores growth and production records.

## Stack

| Layer | Technology |
|---|---|
| Mobile | Dart and Flutter |
| Backend | Firebase Authentication, Cloud Firestore, Cloud Functions, FCM, and Storage |
| Hardware | ESP32 C++ firmware with the Arduino framework and PlatformIO |
| ML development | Python, scikit-learn, and a Random Forest classification scaffold |

## Current data flow

```text
ESP32 → Firebase sensor history and live readings
      → notification Cloud Functions route readings to the assigned tank
      → Flutter app shows live readings, analytics, controls, and records
      → dashboard shows Water Quality Classification as MODEL PENDING
```

The classification training materials and dataset are in `ML_WQC/`.

## Archived anomaly-detection implementation

The prior Water Quality Anomaly Detection / Isolation Forest source, artifacts, reports, and Flutter UI have been moved to `archive/water_quality_anomaly_detection_2026-11-10/`. They are not active application code. Existing Firestore anomaly-history documents are retained; this local archive does not delete cloud data or remove an already deployed Cloud Function.

## Safety and deployment notes

- Sensor-threshold alerts and actuator safeguards remain separate from ML classification.
- ESP credentials stay in the ignored device secrets file.
- Firebase Functions currently configured in `firebase.json` use `functions/backend` as the source folder. The Firebase codebase ID remains `notifications` to preserve its existing deployment identity.
- Removing a codebase from local configuration does not remove an already deployed Firebase Function; confirm and retire any old WQAD deployment separately.
- Node.js notification functions must be migrated before their runtime is decommissioned.
