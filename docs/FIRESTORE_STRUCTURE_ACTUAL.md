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
| photo_url / photoUrl | string | `photo_url` canonical; `photoUrl` legacy alias |
| fcmTokens | array<string> | One token per logged-in device |
| fcmToken | string | Legacy single-token compatibility only |
| created_at | timestamp | |

### `users/{uid}/notification_settings/preferences` ✓
`sound`, `vibration`, `critical`, `warning`, `feeding`, `sampling`, `updated_at`

### `users/{uid}/notif_markers/{key}` ✓
`markerKey`, `value`, `updated_at` — server-side idempotency markers for scheduled reminders/checks.

---

## 2. HARDWARE ASSIGNMENT
### `hardware_system/currentOwner` ✓
`uid`, `tank_id`, `assigned_by`, `assigned_at`

A valid assignment is either `uid == null && tank_id == null`, or an **active owner** whose profile `tank_id` exactly matches the assignment. Admin user-management clears the assignment atomically when the assigned owner is disabled. Firestore rules reject invalid client assignments, and Cloud Functions also clear invalid Console/Admin-SDK assignments.

---

## 3. TANKS — ang core ng buong system ✓
### `tanks/{tankId}` ✓
`owner_uid`, `current_batch_id`, `stocking_date`, `last_sample_date`, `sample_count`, `initial_population`, `initial_total_sample_weight`, `initial_total_sample_length`, `is_initialized`, `created_at`

### `tanks/{tankId}/sensor_readings/latest` ✓
`temperature`, `ph_level`, `dissolved_oxygen`, `turbidity`, `turbidity_air`, `water_level`, optional `buffered_entries`, `recorded_at`.

### `tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}` ✓
Daily summary parent used for long-range Analytics. Canonical maintenance fields: `summary_version` (currently `1`), `summary_sanitized`, `summary_complete`, `date_key`, `sample_count`, `processed_entry_ids`, `updated_at`, plus per-sensor `*_min`, `*_max`, `*_avg`, `*_sum`, and `*_count` fields when data exists.

Only completed summaries with `summary_sanitized == true` are used by the optimized Flutter long-range reader. Older summaries are rebuilt from their raw entries by the hourly backfill before being used.

### `tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{docId}` ✓
10-minute MIN/MAX/AVG aggregates plus `recorded_at`. A sensor with zero valid samples is omitted rather than stored as a negative sentinel.

### `tanks/{tankId}/sensors/{sensorName}` ✓
Sensor names: `temperature` | `ph_level` | `dissolved_oxygen` | `turbidity` | `water_level`
Fields: `min_value`, `max_value`, `updated_at`

### `tanks/{tankId}/actuators/{deviceId}` ✓
Device IDs: `pump`, `aerator1`, `aerator2`
Fields: `control_mode`, `current_state`, `last_changed` (epoch milliseconds; `0` = never changed)

### `tanks/{tankId}/actuator_logs/{logId}` ✓
`actuator_type`, `action`, `type`, `logged_at`. New writes use epoch milliseconds; the app remains tolerant of legacy timestamp representations.

### `tanks/{tankId}/feeder/status` ✓
`status`, `dispenseCount`, `lastSeen`, `last_dispensed_at`, `last_dispensed_grams`

### `tanks/{tankId}/feeder_schedules/{scheduleId}` ✓
`time`, `ampm`, `timeValue`, `grams`, `days`, `enabled`, `isDone`, `created_at`, `effective_at_ms`

`effective_at_ms` records when a schedule becomes effective after creation, edit, or re-enable, preventing an occurrence earlier than that instant from being incorrectly marked as missed.

### `tanks/{tankId}/feeder_logs/{logId}` ✓
Canonical fields: `action`, `type`, `logged_at`.

Missed-schedule logs may additionally contain `schedule_key` and `schedule_time`. `trigger_type` is no longer written by the active runtime. The app accepts legacy Firestore `Timestamp`, `DateTime`, ISO-string, Unix-seconds, and Unix-milliseconds forms of `logged_at`, while new writes use Unix epoch milliseconds.

### `tanks/{tankId}/feeder_commands/{commandId}` ✓
`command_type`, `grams`, `issued_by`, `issued_at`

### `tanks/{tankId}/machine_learning_assessments/current` ✓
**Written hourly by the Python Water Quality Assessment Cloud Function** (Admin SDK). The app reads it with snapshot listeners.
`uid`, `tank_id`, `level` (`Good`|`Moderate`|`Poor`|`Critical`|`Insufficient`), `model_level`, `rule_level`, `safety_override`, `confidence`, `driver`, `driver_label`, `driver_value`, `driver_unit`, `driver_min`, `driver_max`, `problem`, `insight`, `action`, `concerns`, `secondary_concerns`, `ts_epoch`, `timestamp` (ISO-8601 string). Legacy `Low` and `High` history values are normalized by the app to `Good` and `Poor`.

Hourly history uses `tanks/{tankId}/machine_learning_assessments/{YYYYMMDDTHHMMSS}` with the same assessment schema. ML rejects incomplete, negative-sentinel, non-finite, or internally inconsistent min/avg/max history rows before inference.

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

For operational actuator events, deterministic notification IDs ensure one Firestore notification/log record while FCM fans the same notification out to all registered devices of the account.

---

## 6. ESP STAGING ✓
### `sensorIngestion/current` ✓
5-second live ESP staging snapshot: `hardwareId`, live sensor values, `turbidity_air`, and `buffered_entries`. Cloud Functions route the latest snapshot to the active tank.

### `sensorIngestion/current/history/{docId}` ✓
10-minute ESP staging aggregate: `hardwareId`, per-sensor MIN/MAX/AVG only when valid samples exist, plus `captured_at_ms` when the NTP clock is trusted. Cloud Functions preserve the original capture instant as canonical `recorded_at`.

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
- Active owner/admin access checks require `status == active`.
- `hardware_system/currentOwner` client writes are valid only for an active owner whose profile `tank_id` matches, or a fully unassigned null/null state.
- ESP staging/assigned-device access currently identifies ESP sessions through Firebase Anonymous Auth. Before production deployment, bind ESP authorization to a provisioned device identity/custom claim instead of treating every anonymous session as trusted hardware.
