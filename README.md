# 🦞 CrayCare — Smart Crayfish Aquaculture System

IoT-based smart aquaculture monitoring system for crayfish farming.

## Stack

| Layer | Tech |
|---|---|
| Mobile app | Flutter (Android/iOS/Web) |
| Backend | Firebase (Auth, Firestore, Cloud Functions, FCM, Storage) |
| ML | Python Cloud Function (XGBoost water-quality classifier) |
| Hardware | ESP32 (ESP-IDF/Arduino via PlatformIO) with temp, pH, DO, turbidity, water-level sensors + auto-feeder + pump + 2 aerators |

## Architecture

```
ESP32 (anonymous auth)
  → writes sensorIngestion/current (+ history)
      → Cloud Function routes to tanks/{tankId}/sensor_readings/latest
          → Flutter app reads (real-time) + ML function predicts
              → tanks/{tankId}/health_risk/current → dashboard + alerts
```

Single hardware package assigned to one farmer via `hardware_system/currentOwner`
(admin-managed). Reassignment is instant; previous owner's data is preserved.

## Firestore schema

See [`docs/FIRESTORE_STRUCTURE_ACTUAL.md`](docs/FIRESTORE_STRUCTURE_ACTUAL.md).

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
