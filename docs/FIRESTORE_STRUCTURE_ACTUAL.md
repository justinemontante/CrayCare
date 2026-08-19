# 🔥 CrayCare — Firestore Structure (ACTUAL / Updated)

> Base sa aktwal na code (`lib/services/*.dart`, `functions/*`, `esp/*`, `firestore.rules`).
> ✓ = active · 🗑️ = legacy/leftover (hindi na ginagamit o lumang schema)

---

## 1. USERS
### `users/{uid}` ✓
| Field | Type | Notes |
|---|---|---|
| full_name | string | |
| email | string | |
| role | string | `owner` \| `admin` |
| status | string | `active` \| `disabled` |
| tank_id | string | = uid by default; source of tank ownership |
| photo_url / photoUrl | string | legacy alias |
| created_at | timestamp | |

> **FCM device tokens:** stored in the `users/{uid}.fcmTokens` **array**.

### `users/{uid}/notification_settings/preferences` ✓
`sound`, `vibration`, `critical`, `warning`, `feeding`, `sampling`, `updated_at`

### `users/{uid}/notif_markers/{key}` ✓
Tracks last-seen notification markers.

---

## 2. HARDWARE ASSIGNMENT
### `hardware_system/currentOwner` ✓
`uid`, `tank_id`, `assigned_by`, `assigned_at`

---

## 3. TANKS — ang core ng buong system ✓
### `tanks/{tankId}` ✓
`owner_uid`, `current_batch_id`, `stocking_date`, `last_sample_date`, `sample_count`, `initial_population`, `initial_total_sample_weight`, `initial_total_sample_length`, `is_initialized`, `created_at`

### `tanks/{tankId}/sensor_readings/latest` ✓
`temperature`, `ph_level`, `dissolved_oxygen`, `turbidity`, `water_level`, `recorded_at`

### `tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{docId}` ✓
10-minute MIN/MAX/AVG aggregates plus `recorded_at`.

### `tanks/{tankId}/sensors/{sensorName}` ✓
Sensor names: `temperature` | `ph_level` | `dissolved_oxygen` | `turbidity` | `water_level`
Fields: `min_value`, `max_value`, `updated_at`

### `tanks/{tankId}/actuators/{deviceId}` ✓
Device IDs: `pump`, `aerator1`, `aerator2`
Fields: `control_mode`, `current_state`, `last_changed`

### `tanks/{tankId}/actuator_logs/{logId}` ✓
`actuator_type`, `action`, `type`, `logged_at`

### `tanks/{tankId}/feeder/status` ✓
`status`, `dispenseCount`, `lastSeen`, `last_dispensed_at`, `last_dispensed_grams`

### `tanks/{tankId}/feeder_schedules/{scheduleId}` ✓
`time`, `ampm`, `timeValue`, `grams`, `days`, `enabled`, `isDone`, `created_at`

### `tanks/{tankId}/feeder_logs/{logId}` ✓
`action`, `type`, `trigger_type`, `logged_at`

### `tanks/{tankId}/feeder_commands/{commandId}` ✓
`command_type`, `grams`, `issued_by`, `issued_at`

### `tanks/{tankId}/feeder_dispatched/{YYYY-M-D}` ✓
Legacy/idempotency marker used by manual app dispatch flows.

### `tanks/{tankId}/machine_learning_assessments/current` ✓
**Written hourly by the Python Water Quality Assessment Cloud Function** (Admin SDK). The app reads it with snapshot listeners.
`uid`, `tank_id`, `level` (`Good`|`Moderate`|`Poor`|`Critical`|`Insufficient`), `model_level`, `rule_level`, `safety_override`, `confidence`, `driver`, `driver_label`, `driver_value`, `driver_unit`, `driver_min`, `driver_max`, `problem`, `insight`, `action`, `ts_epoch`, `timestamp` (ISO-8601 string). Legacy `Low` and `High` history values are normalized by the app to `Good` and `Poor`.

There is no public Water Quality Assessment numeric score. At least six complete 10-minute records are required internally before a Water Quality Assessment can be produced.

---

## 4. PRODUCTION / BATCHES ✓
### `tanks/{tankId}/batches/{batchId}` ✓
Canonical stored fields are snake_case.

### `tanks/{tankId}/batches/{batchId}/sampling_records/{recordId}` ✓
`sampling_date`, `avg_body_weight`, `avg_body_length`, `sample_size`, `total_weight`, `total_length`, `biomass`, `live_count`, `is_baseline`, `created_at`

### `tanks/{tankId}/batches/{batchId}/mortality_records/{recordId}` ✓
`mortality_date`, `mortality_count`, `created_at`

### `tanks/{tankId}/batches/{batchId}/harvest_records/{recordId}` ✓
`batch_id`, `harvest_date`, `harvest_count`, `total_weight_kg`, `abw_grams`, `created_at`

---

## 5. NOTIFICATIONS ✓
### `notifications/{notifId}` ✓
`uid`, `notif_type`, `title`, `body`, `is_read`, `created_at`

---

## 6. ESP STAGING ✓
### `sensorIngestion/current` ✓
ESP32 live ingestion path.

### `sensorIngestion/current/history/{docId}` ✓
ESP32 historical ingestion path.

---

## 🗑️ LEGACY / STALE
| Collection | Status |
|---|---|
| `sensorThresholds` | Legacy |
| `sensorReadings/{uid}` | Replaced by nested tank readings |
| `sensorReadingsHistory/{uid}` | Replaced by nested tank history |
| `feederSchedules`, `feederLogs`, `feederCommands`, `feederStatus`, `feederDispatched` | Legacy flat versions |
| `deviceModes`, `deviceLogs` | Replaced by nested actuator data |
| `healthRisk/{tankId}`, `tanks/{id}/health_risk/current`, root `mlPredictions`, `tanks/{id}/ml_predictions` | Replaced by `tanks/{id}/machine_learning_assessments` |
| flat production collections | Replaced by nested batch structure |

---

## 🔐 Security rules summary
- Water Quality Assessments: owner read only; Admin SDK writer only.
- Other operational ownership/security rules remain unchanged.
