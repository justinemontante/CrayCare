# 🦞 CrayCare — Smart Crayfish Aquaculture System

IoT-based smart aquaculture monitoring system for crayfish farming.

## Stack

| Layer | Tech |
|---|---|
| Mobile app | Flutter (Android/iOS/Web) |
| Backend | Firebase (Auth, Firestore, Cloud Functions, FCM, Storage) |
| ML | Python Cloud Function (Machine Learning-Based Water Quality Assessment using XGBoost) |
| Hardware | ESP32 (ESP-IDF/Arduino via PlatformIO) with temp, pH, DO, turbidity, water-level sensors + auto-feeder + pump + 2 aerators |

## Architecture

```
ESP32 (anonymous device session)
  → writes sensorIngestion/current (+ 10-minute history)
      → Cloud Function routes to tanks/{tankId}/sensor_readings/latest + history
          → Flutter app reads live/analytics data
          → hourly Python Water Quality Assessment analyzes ≥6 complete history windows
              → tanks/{tankId}/machine_learning_assessments/current → dashboard + AI insights
```

### Machine Learning-Based Water Quality Assessment

The Water Quality Assessment combines pH, temperature, dissolved oxygen,
turbidity, water level, and their recent trends to determine the overall water
condition, identify emerging risks, and generate insights and recommendations.
A machine-learning model is used as part of the Water Quality Assessment to
determine the overall water condition. Immediate actuator
control remains threshold-based; the ML feature provides the broader trend-aware
assessment and early warning.

### Android Live Tank Status Widget

The resizable Android home-screen widget shows the ESP32 online state, latest
Water Quality Assessment and primary concern, all five live sensor values with
their individual threshold status, the next enabled feeding time, and the last
refresh time. The Flutter app pushes a cached snapshot to the native widget
whenever sensor, assessment, feeder, connectivity, or threshold data changes.
Tapping the widget opens CrayCare. After installing a build containing the
feature, add it from the Android launcher widget picker as **CrayCare**.

Single hardware package assigned to one farmer via `hardware_system/currentOwner`
(admin-managed). Reassignment is instant; previous owner's data is preserved.

Offline behavior: after at least one successful online synchronization, the ESP32
continues sensing, runs cached feeding schedules locally, and stores 10-minute
history windows in LittleFS. On reconnect it uploads the backlog oldest-first with
deterministic IDs to avoid duplicates. Live 5-second snapshots are best-effort and
are not buffered. A cold power-up with no network cannot know correct wall-clock
time without an external RTC, so time-based schedules require a previously synced
clock and uninterrupted power during the outage.

## Firestore schema and audits

- [`docs/FIRESTORE_STRUCTURE_ACTUAL.md`](docs/FIRESTORE_STRUCTURE_ACTUAL.md)
- [`docs/DATABASE_INTEGRATION_AUDIT.md`](docs/DATABASE_INTEGRATION_AUDIT.md)
- [`docs/CODEBASE_REGRESSION_AUDIT.md`](docs/CODEBASE_REGRESSION_AUDIT.md)

## ESP32 Firmware

PlatformIO project in [`esp/CrayCare/`](esp/CrayCare/) — default env `esp32dev_main`
(sensor ingestion + feeder + pump/aerator control, Firestore-only, zero RTDB).

- Pinout: [`esp/CrayCare/PINS_CONFIG.txt`](esp/CrayCare/PINS_CONFIG.txt)
- Serial commands: [`esp/CrayCare/SERIAL_COMMANDS.txt`](esp/CrayCare/SERIAL_COMMANDS.txt)

## Deploy

```bash
# Firestore rules + indexes
firebase deploy --only firestore:rules,firestore:indexes

# Cloud Functions (Node notifications + Python ML)
firebase deploy --only functions

# Flash ESP32 (PlatformIO)
cd esp/CrayCare && pio run -e esp32dev_main -t upload
```

## Notes

- ESP32 authenticates with Firebase anonymous sign-in (thesis/demo guard).
- Per-user notification preferences live at `users/{uid}/notification_settings/preferences`.
- Multiple devices per account: all receive push (FCM tokens stored via arrayUnion).
