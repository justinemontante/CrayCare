# CrayCare Database Integration Audit

**Date:** 2026-08-13

## Verified project configuration

The Android Firebase configuration, generated Dart Firebase options, `.firebaserc`, and Firebase CLI configuration all target:

- Project ID: `craycare-8436c`
- Project number / messaging sender: `937626111574`

The generated options still contain a Realtime Database URL, but active app/firmware data access uses Firestore. No `FirebaseDatabase` API usage exists in the active code.

## Canonical data flow

```text
ESP32 anonymous device session
  -> sensorIngestion/current (5-second best-effort live snapshot)
  -> sensorIngestion/current/history/{id} (10-minute durable aggregate)
      -> Node Cloud Functions resolve hardware_system/currentOwner
      -> tanks/{tankId}/sensor_readings/latest
      -> tanks/{tankId}/sensor_readings_history/{date}/entries/{id}
          -> Flutter live dashboard and historical analytics
          -> hourly Python WQC
          -> tanks/{tankId}/ml_predictions/current
```

Device control paths are scoped to the assigned tank:

- `tanks/{tankId}/sensors/*`
- `tanks/{tankId}/actuators/*`
- `tanks/{tankId}/feeder/status`
- `tanks/{tankId}/feeder_schedules/*`
- `tanks/{tankId}/feeder_commands/*`
- `tanks/{tankId}/feeder_logs/*`
- `tanks/{tankId}/actuator_logs/*`

Production data uses:

- `tanks/{tankId}/batches/{batchId}`
- nested `sampling_records`, `mortality_records`, and `harvest_records`

## Security-rule validation

Firestore rules were loaded successfully by the Firestore Emulator and exercised with authenticated test contexts. Verified behavior:

- Active owner can read/write its own tank data.
- Owner cannot read another owner's tank.
- Disabled owner immediately loses tank access.
- Active Admin can manage accounts/hardware and provision missing tank metadata; Admin is denied owner operational data and controls.
- Owner can change actuator `control_mode` only.
- Assigned anonymous ESP can report actuator physical state for its assigned tank only.
- ESP cannot access another tank's thresholds/actuators.
- App users cannot write canonical sensor readings or ML predictions.
- Anonymous ESP can write the staging ingestion path.
- Legacy owner profile can safely backfill missing `role/status` without self-promoting.
- Owner cannot promote itself to admin.
- Notification owner can change `is_read`, but cannot rewrite title/body or transfer notification UID.

## Integration corrections made

1. Disabled owners/admins are now enforced by Firestore rules, not only the login UI.
2. Legacy profile role/status backfill is permitted only as `owner` + `active`; self-promotion/reactivation is blocked.
3. Feeder status is device-owned. Flutter only reads status/feedCount/lastSeen/last_dispensed_*; the ESP32 writes them on its heartbeat.
4. Sensor alerts, feeding reminders, and sampling reminders have one canonical server-side writer. Retired client/background reminder paths were removed to prevent duplicate Firestore notifications and duplicate OS banners.
5. Old Android WorkManager feeding/reminder work is cancelled on app upgrade.
6. User/tank/sensor/actuator/feeder provisioning is atomic, and TankService repairs missing seed subdocuments without overwriting existing configuration.
7. FeederService uses the same safe legacy tank claim as other services.
8. Profile images now use one canonical `photo_url` field. Legacy `photoUrl` remains read-compatible, but duplicate base64 storage is removed to avoid Firestore's 1 MiB document limit.
9. Profile images are resized/compressed and rejected if the encoded payload remains too large.
10. Required composite indexes are present for notifications and actuator logs; all other active ordered queries use automatic single-field indexes.

## Validation results

- Firestore rules syntax: **PASS**
- Firestore emulator authorization tests: **PASS**
- Node Cloud Function syntax: **PASS**
- Python ML source compilation: **PASS**
- Dart source parsing for changed integration files: **PASS**
- ESP32 production firmware build: **PASS**
  - RAM: 15.2%
  - Flash: 35.7%

## Remaining production caveat

The ESP currently uses Firebase anonymous authentication. Rules restrict direct tank-device access to the tank in `hardware_system/currentOwner`, but any party able to create an anonymous Firebase session could still attempt to spoof the fixed `sensorIngestion` staging path. Before public production deployment, replace anonymous device identity with one of:

- a custom-auth device token / custom claim issued only to provisioned hardware; or
- a secured HTTPS ingestion endpoint that validates a per-device credential.

The emulator validates rules and integration contracts; final deployment should still include a smoke test against the actual Firebase project after rules/functions/indexes are deployed.
