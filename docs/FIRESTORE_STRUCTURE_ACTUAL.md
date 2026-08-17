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

> **FCM device tokens:** stored in the `users/{uid}.fcmTokens` **array** (each device adds its own via `arrayUnion`; removed per-device via `arrayRemove` on sign-out). No subcollection is used.

### `users/{uid}/notification_settings/preferences` ✓
`sound`, `vibration`, `critical` (sensor alerts), `warning` (approaching threshold), `feeding` (feeding reminders), `sampling` (weekly sampling), `updated_at`
> Per-user ✓ — naka-scope sa `users/{uid}`. Sine-save ng app, chine-check ng Cloud Function para i-gate ang pushes.

### `users/{uid}/notif_markers/{key}` ✓
Tracks last-seen notification markers (reminders/confirmations) — `last_read_at`-style flags

---

## 2. HARDWARE ASSIGNMENT
### `hardware_system/currentOwner` ✓ *(source of truth — ESP32 + CF + admin)*
| Field | Type |
|---|---|
| uid | string |
| tank_id | string |
| assigned_by | string (admin uid) |
| assigned_at | timestamp |

> **Flow:** ESP32 reads this → Cloud Function routes readings to `tanks/{tank_id}/...`

---

## 3. TANKS — ang core ng buong system ✓
### `tanks/{tankId}` ✓
| Field | Type |
|---|---|
| owner_uid | string |
| current_batch_id | string |
| stocking_date | int (epoch ms) |
| last_sample_date | int (epoch ms) |
| sample_count | int |
| initial_population | int |
| initial_total_sample_weight | double |
| initial_total_sample_length | double |
| is_initialized | bool |
| created_at | timestamp |

> Canonical field names = **snake_case** (consistent sa Cloud Function at ESP32).

### `tanks/{tankId}/sensor_readings/latest` ✓
**Written by Cloud Function** (mula `sensorIngestion/current`); app reads.
`temperature`, `ph_level`, `dissolved_oxygen`, `turbidity`, `water_level`, `recorded_at` (server timestamp)

### `tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{docId}` ✓
Historical readings, partitioned by date. Written by CF. Each entry is a **10-min window** with per-sensor **MIN/MAX/AVG** aggregates (structure order: min, max, avg):
- `temp_min`, `temp_max`, `temp_avg`
- `turbidity_min`, `turbidity_max`, `turbidity_avg`
- `pH_min`, `pH_max`, `pH_avg` (kapag naka-enable)
- `DO_min`, `DO_max`, `DO_avg` (kapag naka-enable)
- `waterLevel_min`, `waterLevel_max`, `waterLevel_avg` (kapag naka-enable)
- `recorded_at` (timestamp) — orihinal na capture time (may fallback sa server time)

### `tanks/{tankId}/sensors/{sensorName}` ✓ *(thresholds)*
Sensor names: `temperature` | `ph_level` | `dissolved_oxygen` | `turbidity` | `water_level`
Fields: `min_value`, `max_value`, `updated_at`
> Seeded by `_createTankIfMissing()`; app (owner) writes; **ESP32 reads**; CF reads for alerts.

### `tanks/{tankId}/actuators/{deviceId}` ✓ ✅ **(na-update kasama ang integration)**
Device IDs: **`pump`** · **`aerator1`** · **`aerator2`**
| Field | Type | Sino sumusulat |
|---|---|---|
| control_mode | string `on`\|`off`\|`auto` | App lang (owner/admin) |
| current_state | string `on`\|`off` (ACTUAL relay state) | **ESP32** (anonymous) |
| last_changed | timestamp (app) / int epoch-ms (ESP) | pareho |

> **Rules:** ESP32 pwede mag-read ng lahat, pero mag-update LANG ng `current_state` + `last_changed`. Hindi pwede baguhin ng ESP ang `control_mode`.

### `tanks/{tankId}/actuator_logs/{logId}` ✓ ✅ **(bago — nilikha ng ESP)**
| Field | Type |
|---|---|
| actuator_type | string (`pump`\|`aerator1`\|`aerator2`) |
| action | string — e.g. `Switched ON — Aerator 1 (AUTO) — ...` |
| log_level | string (`info`) |
| message | string |
| type | string (`on`\|`off`\|`auto`) |
| time | string (`6:30 PM`) |
| date | string (`Aug 1, 2026`) |
| timestamp | int epoch-ms |
| logged_at | int epoch-ms |

> **ESP32 lumilikha** kapag may relay transition. App nagbabasa. May composite index na (by `timestamp` at `logged_at`).

### `tanks/{tankId}/feeder/status` ✓
ESP32 writes: `status` (`idle`|`dispensing`), `isRunning`, `feedSource`, `feedCount`, `hopperLevel`, `lastSeen`, `last_dispensed_at`, `last_dispensed_grams`

### `tanks/{tankId}/feeder_schedules/{scheduleId}` ✓
Flutter writes; ESP32 reads. `time` (`6:00`), `ampm` (`AM`/`PM`), `timeValue` (minutes since midnight — ginagamit sa sorting), `grams`, `portion_grams`, `feed_time`, `is_active`, `isDone`, `created_at`

### `tanks/{tankId}/feeder_logs/{logId}` ✓
ESP32 + app lumilikha. `action`, `type`, `time`, `date`, `timestamp`

### `tanks/{tankId}/feeder_commands/{commandId}` ✓
Flutter creates; ESP32 reads + deletes after processing.
`command_type` (`feed_now`), `trigger_type` (`manual`|`auto`), `grams`, `issued_by`, `status` (`pending`|`done`), `issued_at`

### `tanks/{tankId}/feeder_dispatched/{YYYY-M-D}` ✓
Legacy/idempotency marker used by manual app dispatch flows. Each schedule document ID is stored as a dynamic boolean field (`{scheduleId}: true`). Stored schedules themselves are executed by the ESP32; Android background work is reminders-only.

### `tanks/{tankId}/ml_predictions/current` ✓
**Written hourly by the Python WQC Cloud Function** (Admin SDK). The app reads it with snapshot listeners.
`uid`, `tank_id`, `level` (`Low`|`Moderate`|`High`|`Critical`|`Insufficient`), `confidence`, `driver`, `driver_label`, `driver_value`, `driver_unit`, `driver_min`, `driver_max`, `problem`, `insight`, `action`, `source` (standards/citation text), `analysis_mode`, `samples_analyzed`, `required_samples`, `timestamp` (ISO-8601 string).

There is no public WQC numeric score. At least six complete 10-minute records are required; incomplete sensor records are skipped rather than converted to zero.

---

## 4. PRODUCTION / BATCHES ✓
### `tanks/{tankId}/batches/{batchId}` ✓
Canonical stored fields are snake_case (see the exact list in the appendix below). Derived calculations used consistently by TankService and the dashboard:
- `ABW (g) = total sample weight (g) / sample size`
- `ABL (cm) = total sample length (cm) / sample size`
- `biological survivors = initial_count - total_mortality`
- `in-tank count = initial_count - total_mortality - harvest_count`
- `survival rate (%) = biological survivors / initial_count × 100` (harvested animals are survivors, not deaths)
- `estimated biomass (kg) = in-tank count × latest ABW (g) / 1000`
- `harvest ABW (g) = total_weight_kg × 1000 / harvest_count`

Mortality and harvest record creation plus aggregate updates use atomic Firestore batches/transactions. Values are clamped/validated so mortality + harvest cannot exceed the initial population.

### `tanks/{tankId}/batches/{batchId}/sampling_records/{recordId}` ✓
`sampling_date`, `avg_body_weight`, `avg_body_length`, `sample_size`, `total_weight`, `total_length`, `biomass`, `live_count`, `is_baseline`, `created_at`

### `tanks/{tankId}/batches/{batchId}/mortality_records/{recordId}` ✓
`mortality_date`, `mortality_count`, `created_at`

### `tanks/{tankId}/batches/{batchId}/harvest_records/{recordId}` ✓
`batch_id`, `harvest_date`, `harvest_count`, `total_weight_kg`, `abw_grams`, `survival_rate`, `created_at`

---

## 5. NOTIFICATIONS ✓
### `notifications/{notifId}` ✓
Root collection scoped by the `uid` field.
`uid`, `notif_type`, `title`, `body`, `is_read`, `created_at`
> Cloud Functions are the canonical sensor/feeding/sampling notification writers. The owner may update `is_read` only. Composite index: `uid + created_at DESC`.

---

## 6. ESP STAGING (ESP32 lang sumusulat) ✓
### `sensorIngestion/current` ✓
ESP32 writes every ~5s. CF `onSensorIngestionWrite` → routes to `tanks/{tankId}/sensor_readings/latest`.
Fields: `hardwareId`, `temperature`, `turbidity`, `turbidity_air`, `dissolved_oxygen`, `ph_level`, `water_level`

### `sensorIngestion/current/history/{docId}` ✓
ESP32 creates every 10min. CF → `tanks/{tankId}/sensor_readings_history/{date}/entries/{docId}`

---

## 7. MISC ✓
### `system/authorizedOperators` *(optional server-side allowlist)*
Read by the Admin SDK notification function. Supported shapes are `{ UID: "uid1,uid2" }` or `{ uid: true }`. When absent, the function falls back to all non-admin users. It is not client-readable.

---

## 🗑️ LEGACY / STALE — hindi na ginagamit (safe i-ignore, nasa `firestore_structure.json` pa)
| Collection | Status |
|---|---|
| `sensorThresholds` | Lumang mirror ng thresholds (nasa `tanks/{id}/sensors` na) |
| `sensorReadings/{uid}` | Pinalitan ng `tanks/{id}/sensor_readings/latest` |
| `sensorReadingsHistory/{uid}` | Pinalitan ng nested history |
| `feederSchedules`, `feederLogs`, `feederCommands`, `feederStatus`, `feederDispatched` | Flat versions — nasa `tanks/{id}/...` na |
| `deviceModes`, `deviceLogs` | Pinalitan ng `actuators/` + `actuator_logs/` |
| `healthRisk/{tankId}`, `tanks/{id}/health_risk/current`, root `mlPredictions` | Pinalitan ng `tanks/{id}/ml_predictions/current` |
| `batches`, `sampling_records`, `mortality_records`, `harvest_records` (flat) | Pinalitan ng nested batch structure |
| `notifPrefs`, `notifMarkers`, `migration`, `sensorConfig`, `system_config` | Legacy / unused |
| `deviceLogs` | Flat logs — pinalitan ng `actuator_logs` |

---

## 🔐 Security rules summary (updated)
- **users** — self; active Admin manages account status and hardware assignment
- **hardware_system** — read: active Admin or ESP; write: active Admin
- **tank operational data** — active Owner only
- **ESP32** — assigned-tank reads for thresholds/schedules/modes; writes physical status/logs; staging writes through `sensorIngestion`
- **Admin** — may read/create tank root metadata and create missing seed docs for assignment, but cannot read owner sensor history, ML results, controls, logs, or production records
- **canonical sensor readings + ML output** — Admin SDK writes only
- **notifications** — matching owner reads/deletes; owner may update `is_read` only

## 📋 Indexes (`firestore.indexes.json`)
- `actuator_logs`: `actuator_type + timestamp DESC`, `actuator_type + logged_at DESC` ✅
- `notifications`: `uid + created_at DESC` ✅
- Other active ordered queries use Firestore automatic single-field indexes.


## Canonical production hierarchy

```text
tanks/{tank_id}/batches/{batch_id}
  batch_status, stocking_date, harvest_date, initial_count, current_count,
  harvest_count, total_mortality, harvest_weight_grams, initial_abw, initial_abl,
  final_abw, final_abl, days_in_culture, sample_count, created_at

  sampling_records/{record_id}
    sampling_date, avg_body_weight, avg_body_length, sample_size, total_weight,
    total_length, biomass, live_count, is_baseline, created_at

  mortality_records/{record_id}
    mortality_date, mortality_count, created_at

  harvest_records/{record_id}
    batch_id, harvest_date, harvest_count, total_weight_kg, abw_grams,
    survival_rate, created_at
```
