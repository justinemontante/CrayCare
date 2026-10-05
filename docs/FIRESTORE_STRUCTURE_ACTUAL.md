# 🔥 CrayCare — Firestore Structure (ACTUAL / Updated)

> Base sa aktwal na code (`lib/services/*.dart`, `functions/*`, `esp/*`, `firestore.rules`).
> ✓ = active · 🗑️ = legacy/leftover (hindi na ginagamit o lumang schema)

> **Important:** Ito ang aktwal na NoSQL/Firestore structure. May ilang cached at
> duplicated fields para sa mabilis na real-time reads, offline support, at security
> checks. Ang hiwalay na `craycare_erd.dbml` ang normalized 3NF SQL ERD;
> hindi kailangang magkapareho ang physical NoSQL documents at SQL tables.

> **Timestamp convention:** Event/record date-times use Firestore `Timestamp`.
> `created_at` means when a record was written; fields such as `sampling_date`
> mean when the sampling event happened. Explicit `*_at_ms` fields remain
> integer milliseconds only where the firmware or routing contract requires it.

---

## 1. USERS
### `users/{uid}` ✓
| Field | Type | Notes |
|---|---|---|
| full_name | string | |
| email | string | |
| role | string | `owner` \| `admin` |
| status | string | `active` \| `disabled` |
| photo_url / photoUrl | string | `photo_url` canonical; `photoUrl` legacy alias |
| fcmTokens | array<string> | One token per logged-in device |
| fcmToken | string | Legacy single-token compatibility only |
| created_at | timestamp | |

### `users/{uid}/notification_settings/preferences` ✓
`sound`, `vibration`, `critical`, `warning`, `feeding`, `sampling`, `operational`, `updated_at`

### `users/{uid}/notif_markers/{key}` ✓
`markerKey`, `value`, `updated_at` — server-side idempotency markers for scheduled reminders/checks.

---

## 2. HARDWARE ASSIGNMENT
### `hardware_system/currentOwner` ✓
`uid`, `tank_id`, `assigned_by`, `assigned_at`

A valid assignment is either `uid == null && tank_id == null`, or an **active owner** whose canonical `tanks/{tankId}.owner_uid` matches `uid`. Admin user-management clears the assignment atomically when the assigned owner is disabled. Firestore rules reject invalid client assignments, and Cloud Functions also clear invalid Console/Admin-SDK assignments.

---

## 3. TANKS — ang core ng buong system ✓
### `tanks/{tankId}` ✓
`owner_uid`, `current_batch_id`, `is_initialized`, `created_at`

`owner_uid` is the only ownership source of truth. The user profile does not duplicate a `tank_id`. Culture and sampling facts are stored under the selected batch rather than duplicated on the tank document. Registration creates only the owner profile and notification preferences; the first submitted Tank Setup creates `tanks/{uid}` and its sensor, actuator, feeder, and initial batch records. Under the one-owner/one-tank design, the tank document ID is the owner's Firebase UID.

### Firestore document ID conventions
Document IDs are path identifiers, not normal fields stored inside each document. `users/{uid}` and `tanks/{tankId}` use the owner's Firebase Authentication UID. Batch IDs use `CR-YYYYMMDD-###`; that value is also intentionally stored as `batch_id`. The baseline sampling record is `baseline`, later sampling records use Firestore Auto-IDs, and mortality, harvest, schedule, and command records use Firestore Auto-IDs. Actuator logs use Auto-IDs; feeder logs use an Auto-ID for app audit entries or a durable firmware event ID for ESP32 outcomes. Fixed IDs are `currentOwner`, `latest`, `status`, and anomaly detection `current`; anomaly history uses `YYYYMMDDTHHMMSS`.

### `tanks/{tankId}/sensor_readings/latest` ✓
Direct 5-second ESP32 snapshot: `temperature`, `ph_level`, `dissolved_oxygen`, `turbidity`, `turbidity_air`, `water_level`, `feed_level` (percent), optional `buffered_entries`, `recorded_at`, `captured_at_ms`, `hardwareId`, `source_tank_id`, `source_owner_uid`, and `source_assignment_at_ms`. Rules allow writes only from the ESP32 service account when the current hardware assignment and tank owner match, and reject out-of-order readings.

### `tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}` ✓
Daily summary parent used for long-range Analytics. Canonical maintenance fields: `summary_version` (currently `4`), `summary_sanitized`, `summary_complete`, `date_key`, `sample_count`, `processed_entry_ids`, and `updated_at`. Temperature, pH, dissolved oxygen, and turbidity have per-sensor `*_min`, `*_max`, `*_avg`, `*_sum`, and `*_count` fields when data exists; daily min/max are calculated across the 10-minute history means, not across the readings inside each window. Water and feed levels have daily means plus sums/counts, with no daily min/max fields.

Only completed summaries with `summary_sanitized == true` are used by the optimized Flutter long-range reader. Older summaries are rebuilt from their raw entries by the hourly backfill before being used.

### `tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{docId}` ✓
Each 10-minute history record stores one mean of valid readings for each available sensor: `temperature`, `ph_level`, `dissolved_oxygen`, `turbidity`, `water_level` (cm), and `feed_level` (percent). It does not store per-window min/max or legacy `*_avg` names. Records also include `recorded_at`, `captured_at_ms`, `hardwareId`, `source_tank_id`, `source_owner_uid`, and `source_assignment_at_ms` for timestamping and assignment validation. Rules verify the active assignment. A sensor with no valid reading is omitted rather than stored as a negative sentinel. Buffered history continues through the Cloud Function staging route, where old-assignment entries are quarantined. Existing older records remain supported by app and ML readers.

### `tanks/{tankId}/sensors/{sensorName}` ✓
Sensor names: `temperature` | `ph_level` | `dissolved_oxygen` | `turbidity` | `water_level` | `feed_level`
Water-quality documents use `min_value` and `max_value`. Both water-level and feed-level documents use only `low_value` and `critical_value` (water level in cm; feed level in percent). All threshold documents store `updated_at`.

### `tanks/{tankId}/actuators/{deviceId}` ✓
Device IDs: `pump`, `aerator1`, `aerator2`
Fields: `control_mode`, `current_state`, `last_changed` (Firestore Timestamp; `null` until the first device-reported state change). The app accepts older integer epoch-millisecond values during rollout.

### `tanks/{tankId}/actuator_logs/{logId}` ✓
`actuator_type`, `action`, `type`, `logged_at` (Firestore Timestamp on new writes; readers remain compatible with legacy timestamp/epoch representations).

### `tanks/{tankId}/feeder/status` ✓
`status`, `command_id`, `status_reason`, `dispenseCount`, `lastSeen` (Firestore Timestamp), `last_dispensed_at` (Firestore Timestamp or null), and `feed_level` (percent). Older integer `lastSeen` values remain readable.

Feeder status flow: `idle` → `checking_feed_level` → `dispensing` → `completed`, with `blocked`, `skipped_insufficient`, or `failed` terminal outcomes. `command_id` ties a manual outcome to the originating Feed Now request, while `status_reason` explains blocked or failed requests.

### `tanks/{tankId}/feeder_schedules/{scheduleId}` ✓
Existing production documents may still contain legacy `time`, `ampm`, and `timeValue`, alongside `grams`, `days`, `enabled`, `isDone`, `created_at`, `effective_at_ms`, `last_outcome`, and `last_occurrence_at`. New writes use `scheduled_time` (zero-padded 24-hour `HH:mm` string); legacy aliases are removed when a schedule is edited or toggled.

The app may display AM/PM, but converts the selected time to `scheduled_time` before saving. The deployed `processFeeding` and `onFeederLogCreate` functions read both canonical and legacy schedule fields, and the deployed schedule-writing callable writes the canonical field. Flash the matching ESP32 firmware before using the updated app to create or edit schedules; existing legacy documents remain readable during this transition. `feeder_schedule_days` is the normalized SQL representation, not a separate Firestore collection.

`effective_at_ms` records when a schedule becomes effective after creation, edit, or re-enable, preventing an occurrence earlier than that instant from being incorrectly marked as missed.

Manual Feed Now collision protection uses these enabled schedules. The app asks
for confirmation within 15 minutes before or after an occurrence. Feed Now is
strictly blocked during the final 60 seconds before the schedule and throughout
the scheduled minute. The ESP32 repeats the strict check before operating the
servo, so a stale client or delayed command cannot race an automatic feeding.
Confirmed warning-window commands store `near_schedule_confirmed: true`; this
records the owner's decision but never bypasses the strict device-side block.

`last_outcome` (`completed`, `blocked`, `skipped_insufficient`, `failed`) and `last_occurrence_at` (Firestore Timestamp; legacy integer epoch ms is read during rollout) are reconciled by `onFeederLogCreate`. `isDone` remains a legacy compatibility field, true only for a completed outcome; the app does not infer completion from this flag alone or reset it at startup. Late backfills cannot overwrite newer occurrences or edited configurations. App reads all schedules; ESP fetches every 20-document page before replacing its cache. `effective_at_ms` remains an integer because it is an explicit millisecond scheduling boundary.

Firmware accepts whole-gram schedule and Feed Now amounts from 1–200 g; missing legacy amounts default to 20 g. Fractions and out-of-range amounts are rejected, not silently rounded or clamped. Actual output requires hardware calibration.

### `tanks/{tankId}/feeder_logs/{logId}` ✓
Canonical fields: `action`, `type`, `logged_at`. ESP outcome logs additionally store `status`, `command_id`, `requested_grams`, `feed_level_before`, `feed_level_after`, and `level_change_detected`. Completed cycles (including confirmed overrides) also store `estimated_dispensed_grams` with `amount_basis: servo_cycle_estimate`; this is a servo-cycle estimate, not a directly weighed amount. Hopper inventory remains percentage-only.

New device outcome logs include `occurrence_at`. Scheduled outcomes also include `schedule_key` and `schedule_time`. Status is `completed`, `blocked`, `skipped_insufficient`, or `failed`; a critical feed-level reading is logged as a skipped outcome. `requested_grams` preserves the dose entered by the user, `estimated_dispensed_grams` reports the servo-cycle estimate after completion, and `feed_level_before` / `feed_level_after` store percentage readings.

Feeder logs are append-only under Firestore security rules: the assigned ESP or tank owner may create an authorized log, but client updates and deletes are denied after creation.

ESP persists an execution reservation before dispensing and writes logs to a LittleFS outbox. Document ids combine hardware id and a persisted event sequence; retries do not create duplicate records. Interrupted execution is reported as `failed`, never automatically replayed. Queued logs retain their original tank and timestamps. Logs belonging to a previous tank remain on-device rather than being misattributed to a newly assigned owner; uploading them requires that tank to be assigned again (or an authorized recovery workflow).

Missed-schedule logs may additionally contain `schedule_key` and `schedule_time`. `trigger_type` is no longer written by the active runtime. New `logged_at` and `occurrence_at` values are Firestore Timestamps; the app accepts legacy `DateTime`, ISO-string, Unix-second, and Unix-millisecond values during rollout.

### `tanks/{tankId}/feeder_commands/{commandId}` ✓
`command_type`, `grams`, `issued_by`, `issued_at`, `expires_at`, and `near_schedule_confirmed`. Older command documents may still contain the deprecated `allow_water_quality_override` field, but the current app does not write it and firmware ignores it.

Manual Feed Now and scheduled feeding both use the shared owner-level setting at `tanks/{tankId}/feeder/schedule_policy.allow_water_quality_override`. When enabled, it permits feeding despite configured temperature, pH, dissolved oxygen, or turbidity range violations only. Missing/stale or unavailable sensors, turbidity sensor-in-air detection, critical feed level, schedule guards, and command validity checks still block feeding.

`expires_at` prevents a queued/offline Feed Now write from becoming a fresh physical command after reconnect. `near_schedule_confirmed` records that the owner accepted the warning-window confirmation; it never overrides the ESP's strict collision block around a scheduled feeding occurrence.

### `tanks/{tankId}/water_quality_anomaly_detections/current` ✓
**Written hourly by the Python Water Quality Anomaly Detection Cloud Function** (Admin SDK). The app reads it with snapshot listeners.
`uid`, `tank_id`, `status` (`Normal`|`Unusual`|`Insufficient`), `is_anomaly`, `anomaly_score`, `source`, `data_status`, `source_recorded_at`, `contributors` (ranked array of `{sensor, value, direction, contribution_score}`), `insight`, `recommendation`, and `processed_at` (Timestamp). The app maps each sensor code to its display label and unit. The deployed detector uses an unsupervised Isolation Forest; model and training metadata are not copied into each detection document.

Hourly history uses the valid sibling collection `tanks/{tankId}/water_quality_anomaly_detection_history/{YYYYMMDDTHHMMSS}` with the same detection fields. Existing timestamp-named documents in `water_quality_anomaly_detections` remain readable during transition. ML rejects incomplete, negative-sentinel, non-finite, or internally inconsistent min/avg/max history rows before inference. Firestore cannot have `current` as a document and `history/{detectionId}` as a subcollection path at the same collection level; the sibling collection provides the intended organization with valid collection/document path parity.

The anomaly score is a 0–100 percentile showing how unusual the latest pattern is relative to reference behavior; it is not a water-safety score. Twelve complete 10-minute records are required before a detection can be produced.

`data_status` (`ready`, `insufficient`, `stale`) and `source_recorded_at` (nullable Firestore Timestamp) describe source freshness. Inference requires twelve contiguous readings at ten-minute cadence (±2 minutes). A newest source reading older than 20 minutes yields `status: Insufficient`, `data_status: stale`; no current pattern is inferred from old readings.

---

## 4. PRODUCTION / BATCHES ✓
### `tanks/{tankId}/batches/{batchId}` ✓
Canonical stored fields are snake_case: `batch_id`, `batch_status`, `stocking_date`, `harvest_date`, `ended_at`, `initial_count`, `current_count`, `harvest_count`, `total_mortality`, `harvest_weight_grams`, `sample_count`, and `created_at`. `sample_count` is the number of individual crayfish in the initial baseline sample. The app derives `days_in_culture` from `stocking_date` to today for active batches, or to `harvest_date` / `ended_at` for completed or superseded batches; this value is not stored. Older batch documents may contain `initial_total_weight` or `initial_total_length`; these are legacy read-compatibility fields, not canonical fields for new writes.
Initial ABW and ABL are derived from the individual measurements in the batch's `sampling_records/baseline` document. Initial totals and ABW/ABL are not written to new batch documents. Final ABW/ABL are derived from the latest sampling record. Legacy batch documents may still contain `initial_total_weight`, `initial_total_length`, or average fields; the reader retains compatibility with them.

### `tanks/{tankId}/batches/{batchId}/sampling_records/{recordId}` ✓
`sampling_date`, `measurements` (array of objects: `sample_number`, `label`, `weight_g`, `length_cm`), `live_count`, `is_baseline`, `created_at`
`sampling_date` is stored as a Firestore Timestamp. Readers remain compatible with legacy epoch-millisecond records.
For new records, sample size is `measurements.length`, total weight and length are sums of `weight_g` and `length_cm`, ABW and ABL are the respective averages, and biomass is `live_count × ABW`. These values are computed by the app and are not written to new sampling records. Legacy records may still contain `sample_size`, `total_weight`, `total_length`, or cached average/biomass fields; they remain readable, and stale aggregate fields are deleted when a record is edited.
Sa normalized relational ERD at Data Dictionary, bawat object sa `measurements` ay ipinapakita bilang isang `sampling_measurements` row. Sa aktuwal na Firestore, naka-embed pa rin ang mga object sa sampling record at walang hiwalay na collection para rito.

### `tanks/{tankId}/batches/{batchId}/mortality_records/{recordId}` ✓
`mortality_date`, `mortality_count`, `created_at`
`mortality_date` is stored as a Firestore Timestamp. Readers remain compatible with legacy epoch-millisecond records.

### `tanks/{tankId}/batches/{batchId}/harvest_records/{recordId}` ✓
`batch_id`, `harvest_date`, `harvest_count`, `total_weight_kg`, `created_at`
`harvest_date` is stored as a Firestore Timestamp. Readers remain compatible with legacy epoch-millisecond records.
Harvest ABW is computed by the app as `total_weight_kg * 1000 / harvest_count`; it is not stored. Editing an older harvest record deletes its legacy `abw_grams` field.

---

## 5. NOTIFICATIONS ✓
### `notifications/{notifId}` ✓
`uid`, `notif_type`, `title`, `body`, `is_read`, `created_at`

For operational actuator events, deterministic notification IDs ensure one Firestore notification/log record while FCM fans the same notification out to all registered devices of the account.

Completed feeder outcome logs create deterministic notification records and immediate FCM pushes when the user's Feeding preference is enabled.

---

## 6. ESP SENSOR WRITES ✓
The current firmware writes live readings and normal 10-minute mean records directly to each tank's canonical sensor documents. Both carry `source_tank_id`, `source_owner_uid`, `source_assignment_at_ms`, and `captured_at_ms`. Rules compare the captured assignment with `hardware_system/currentOwner` and the tank's `owner_uid`; the ESP refreshes its assignment once per minute. Reassignment resets the averaging window. Buffered entries still use the staging route so historical data from the prior assignment is quarantined rather than added to the new owner's tank. Out-of-order live events cannot replace a newer reading.

### `sensorIngestion/current` ✓
Legacy 5-second live staging snapshot for older firmware during rollout. Current firmware writes the live snapshot directly to `tanks/{tankId}/sensor_readings/latest`.

### `sensorIngestion/current/history/{docId}` ✓
Fallback staging for offline-buffered, unassigned, or older-firmware history. Cloud Functions preserve the original capture instant as canonical `recorded_at` and quarantine mismatched assignments instead of routing them to a new owner.

---

## 🗑️ LEGACY / STALE
| Collection | Status |
|---|---|
| `sensorThresholds` | Legacy |
| `sensorReadings/{uid}` | Replaced by nested tank readings |
| `sensorReadingsHistory/{uid}` | Replaced by nested tank history |
| `feederSchedules`, `feederLogs`, `feederCommands`, `feederStatus`, `feederDispatched` | Legacy flat versions |
| `deviceModes`, `deviceLogs` | Replaced by nested actuator data |
| `healthRisk/{tankId}`, `tanks/{id}/health_risk/current`, root `mlPredictions`, `tanks/{id}/ml_predictions` | Replaced by `tanks/{id}/water_quality_anomaly_detections` |
| flat production collections | Replaced by nested batch structure |

---

## 🔐 Security rules summary
- Water Quality Anomaly Detections: owner read only; Admin SDK writer only.
- Active owner/admin access checks require `status == active`.
- `hardware_system/currentOwner` client writes are valid only for an active owner whose tank document has a matching `owner_uid`, or a fully unassigned null/null state.
- ESP staging/assigned-device access uses the dedicated Firebase Email/Password service account `esp32@craycare.com`. Firestore rules verify both the password provider and exact authenticated email. Keep its rotated password only in the gitignored device `secrets.h`; a future multi-device production rollout should provision a distinct identity/custom claim per physical device.

## Feeder request confirmation and push receipts

- `tanks/{tankId}/feeder_commands/{commandId}` adds `expires_at` (Timestamp). ESP rejects commands older than 60 seconds by `issued_at`, or past the app's `expires_at`, including offline writes committed late. Legacy commands without `expires_at` still use the server-issued 60-second limit.
- `tanks/{tankId}/feeder/status` adds `command_id` and `status_reason`. `feeder_logs` adds optional `command_id`. Manual UI outcomes must match that request, not a different feed's count increment. An app timeout is unconfirmed, not an authoritative failure log.
- ESP writes a durable interrupted intent before command acknowledgement or schedule reservation. Reboot recovery reserves the intent's minute and never retries the physical dose. Terminal logs are persisted before cloud status updates.
- `tanks/{tankId}/feeder_notification_receipts/{logId}` contains `uid`, `push_attempt_claimed_at`. Admin SDK creates it atomically with the deterministic inbox entry before the FCM attempt. Duplicate events do not resend or reset read state. A crash after the claim can lose the push attempt; the inbox remains. This is at-most-once, not guaranteed delivery. Receipts are server-only under existing default-deny rules.
