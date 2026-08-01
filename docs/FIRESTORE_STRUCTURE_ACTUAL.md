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
| lifetime_mortality | int |
| lifetime_harvested | int |
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
Historical readings (same fields), partitioned by date. Written by CF.

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

### `tanks/{tankId}/pending_commands/{commandId}` ✓
Flutter creates; ESP32 reads + deletes after processing.
`command_type` (`feed_now`), `trigger_type` (`manual`|`auto`), `grams`, `issued_by`, `status` (`pending`|`done`), `issued_at`

### `tanks/{tankId}/feeder_dispatched/{YYYY-MM-DD}` ✓
Flutter-only. Tracks kung anong schedules ang na-fire na ngayong araw. `scheduleIds` (array), `dispatched_at`

### `tanks/{tankId}/health_risk/current` ✓
**Written by ML Cloud Function** (Admin SDK). App reads (snapshot listener).
`uid`, `tank_id`, `level` (`Low`|`Moderate`|`High`|`Critical`|`Insufficient`), `confidence`, `driver`, `problem`, `insight`, `action`, `source` (`ml`|`insufficient_data`|`rule_based`), `timestamp`

---

## 4. PRODUCTION / BATCHES ✓
### `tanks/{tankId}/batches/{batchId}` ✓
`batchId`, `tankId`, `status` (`active`|`harvested`|`superseded`), `stockingDate` (ms), `harvestDate` (ms|null), `initialCount`, `currentCount`, `harvestCount`, `totalMortality`, `harvestWeightGrams`, `initialAbw`, `initialAbl`, `finalAbw`, `finalAbl`, `daysInCulture`, `sampleCount`, `initialTotalWeight`, `initialTotalLength`, `created_at`

### `tanks/{tankId}/batches/{batchId}/sampling_records/{recordId}` ✓
`tankId`, `batchId`, `date` (ms), `abw`, `avgLength`, `sampleSize`, `totalWeight`, `totalLength`, `biomass`, `liveCount`, `isBaseline`, `timestamp`

### `tanks/{tankId}/batches/{batchId}/mortality_records/{recordId}` ✓
`tankId`, `batchId`, `date` (ms), `count`, `timestamp`

### `tanks/{tankId}/batches/{batchId}/harvest_records/{recordId}` ✓
`tankId`, `batchId`, `date` (ms), `harvestedCount`, `totalWeightKg`, `abwGrams`, `survivalRate`, `timestamp`

---

## 5. NOTIFICATIONS ✓
### `notifications/{notifId}` ✓
Root collection, scoped by `uid` field (hindi path).
`uid`, `title`, `message` (code uses `message`, hindi `body`), `type` (`sensor`|`alert`|`feeder`|`system`), `is_read`, `readBy` (map uid→bool), `timestamp` / `created_at`
> Composite index: `uid` + `created_at DESC` ✓ (nasa indexes)

---

## 6. ESP STAGING (ESP32 lang sumusulat) ✓
### `sensorIngestion/current` ✓
ESP32 writes every ~5s. CF `onSensorIngestionWrite` → routes to `tanks/{tankId}/sensor_readings/latest`.
Fields: `hardwareId`, `temperature`, `turbidity`, `turbidity_air`, `dissolved_oxygen`, `ph_level`, `water_level`

### `sensorIngestion/current/history/{docId}` ✓
ESP32 creates every 10min. CF → `tanks/{tankId}/sensor_readings_history/{date}/entries/{docId}`

---

## 7. MISC ✓
### `mlPredictions/{docId}` ✓
`tankId`, `batchId`, `prediction`, `confidence`, `model_version`, `created_at`

### `system/authorizedOperators` ⚠️ *(ginagamit ng functions/notifications/index.js)*
`system/doc/authorizedOperators` — lumalabas sa Cloud Function (auth check), pero **wala sa rules o structure doc** — para sa isang function feature.

---

## 🗑️ LEGACY / STALE — hindi na ginagamit (safe i-ignore, nasa `firestore_structure.json` pa)
| Collection | Status |
|---|---|
| `sensorThresholds` | Lumang mirror ng thresholds (nasa `tanks/{id}/sensors` na) |
| `sensorReadings/{uid}` | Pinalitan ng `tanks/{id}/sensor_readings/latest` |
| `sensorReadingsHistory/{uid}` | Pinalitan ng nested history |
| `feederSchedules`, `feederLogs`, `feederCommands`, `feederStatus`, `feederDispatched` | Flat versions — nasa `tanks/{id}/...` na |
| `deviceModes`, `deviceLogs` | Pinalitan ng `actuators/` + `actuator_logs/` |
| `healthRisk/{tankId}` | Pinalitan ng `tanks/{id}/health_risk/current` |
| `batches`, `sampling_records`, `mortality_records`, `harvest_records` (flat) | Pinalitan ng nested batch structure |
| `notifPrefs`, `notifMarkers`, `migration`, `sensorConfig`, `system_config` | Legacy / unused |
| `deviceLogs` | Flat logs — pinalitan ng `actuator_logs` |

---

## 🔐 Security rules summary (updated)
- **users** — self/admin lang
- **hardware_system** — read: any signed-in; write: admin
- **tanks/{tankId}** — owner/admin read/write; **ESP32 (anonymous)** pinapayagan:
  - READ: `sensors`, `feeder_schedules`, `actuators`
  - WRITE: `sensor_readings`, `sensor_readings_history`, `feeder/*`, `pending_commands` (read/delete), **`actuator_logs` (create)**, **`actuators` (update: `current_state`+`last_changed` only)**
- **notifications** — owner lang (uid match)
- **sensorIngestion** — ESP write, admin read/delete
- **health_risk, mlPredictions** — Admin SDK lang sumusulat

## 📋 Indexes (nasa `firestore.indexes.json` na)
- `actuator_logs`: `actuator_type + timestamp DESC`, `actuator_type + logged_at DESC` ✅
- `notifications`: `uid + created_at DESC` ✅
- `sampling_records` / `mortality_records`: `tankId + batchId`, `tankId + date`, etc. ✅
- Legacy flat indexes (batches/uid, sampling/uid, etc.) — para sa lumang schema, safe i-clean
