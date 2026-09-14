# CrayCare Firestore Structure — Final Normalized Schema

> This file describes the deployed document-oriented Firestore schema. “Normalized”
> here means consistent canonical paths and field names, not SQL Third Normal Form.
> The thesis 3NF relational model is maintained separately in `craycare_erd.dbml`.

## Relationship

```text
1 User = 1 Tank
1 Tank = many Batches
1 Batch = many Sampling Records, Mortality Records, and Harvest Records
1 ESP32 hardware system = 1 currently assigned owner/tank at a time
```

## Root collections

```text
users
hardware_system
notifications
sensorIngestion       # internal ESP-to-Cloud-Function staging path
```

## Firestore document ID conventions

Document IDs identify a Firestore document in its path; they are not normally
duplicated as fields inside that document. The only intentional duplicate is
`batch_id`, which is stored on a batch document and matches its document ID.

- `users/{uid}` and `tanks/{tankId}` use the owner's Firebase Authentication UID.
- `batches/{batchId}` uses `CR-YYYYMMDD-###` (for example, `CR-20260912-001`).
- `sampling_records/{recordId}` uses `baseline` for the initial record and a Firestore Auto-ID for later samples.
- `mortality_records`, `harvest_records`, `feeder_schedules`, and `feeder_commands` use Firestore Auto-IDs.
- `actuator_logs` use Firestore Auto-IDs. `feeder_logs` use a Firestore Auto-ID for app audit entries or a durable firmware event ID for ESP32 outcome entries.
- Fixed document IDs include `sensor_readings/latest`, `feeder/status`, `hardware_system/currentOwner`, and anomaly detection `current`. Historical anomaly detection records use `YYYYMMDDTHHMMSS`.

## Users

```text
users/{uid}
  full_name: string
  email: string
  role: "owner" | "admin"
  status: "active" | "disabled"
  photo_url: string | null
  fcmTokens: string[]
  created_at: Timestamp

  notification_settings/preferences
    sound: boolean
    vibration: boolean
    critical: boolean
    warning: boolean
    feeding: boolean
    sampling: boolean
    operational: boolean
    updated_at: Timestamp

  notif_markers/{marker_key}
    markerKey: string
    value: number | string
    updated_at: Timestamp
```

## Single hardware assignment

```text
hardware_system/currentOwner
  uid: string | null
  tank_id: string | null
  assigned_by: string | null
  assigned_at: Timestamp | null
```

A valid assignment is either fully unassigned (`uid == null` and `tank_id == null`) or points to an **active owner** whose `tanks/{tank_id}.owner_uid` value matches `uid`. Flutter clears the assignment atomically when the assigned owner is disabled, Firestore rules reject invalid client assignments, and Cloud Functions clear invalid Console/Admin-SDK assignments as defense in depth.

## Tank and hardware data

Owner registration does not create a tank. The first submitted Tank Setup
provisions `tanks/{uid}` together with its default sensor, actuator, and feeder
documents. Before setup, the owner account remains valid but cannot be assigned
hardware or write tank operations.

```text
tanks/{tank_id}       # tank_id is the owner's Firebase Authentication UID
  owner_uid: string
  current_batch_id: string
  is_initialized: boolean
  created_at: Timestamp

  sensor_readings/latest
    temperature: number
    ph_level: number
    dissolved_oxygen: number
    turbidity: number
    turbidity_air: boolean
    water_level: number                # centimeters
    feed_level: number                 # hopper percentage
    estimated_feed_grams: number       # estimated remaining feed
    buffered_entries: number           # optional offline-backlog count
    recorded_at: Timestamp

  sensor_readings_history/{YYYY-MM-DD}
    summary_version: 1
    summary_sanitized: boolean
    summary_complete: boolean
    date_key: string
    sample_count: number
    processed_entry_ids: string[]
    *_min, *_max, *_avg, *_sum, *_count  # only where sensor data exists
    updated_at: Timestamp

    entries/{reading_id}
      temp_min, temp_max, temp_avg
      pH_min, pH_max, pH_avg
      DO_min, DO_max, DO_avg
      turbidity_min, turbidity_max, turbidity_avg
      waterLevel_min, waterLevel_max, waterLevel_avg
      feed_level: number | null
      estimated_feed_grams: number | null
      recorded_at: Timestamp

  sensors/{temperature|ph_level|dissolved_oxygen|turbidity|water_level|feed_level}
    min_value: number
    max_value: number
    critical_value: number             # feed-level threshold only
    hopper_capacity_grams: number      # feed-level configuration only
    updated_at: Timestamp

  actuators/{pump|aerator1|aerator2}
    control_mode: "on" | "off" | "auto"
    current_state: "on" | "off"
    last_changed: Timestamp | null

  actuator_logs/{log_id}
    actuator_type: string
    action: string
    type: string
    logged_at: Timestamp

  feeder/status
    command_id: string | null
    status: "idle" | "checking_feed_level" | "dispensing" | "completed" | "blocked" | "skipped_insufficient" | "failed"
    status_reason: string | null
    dispenseCount: number
    lastSeen: Timestamp
    last_dispensed_at: Timestamp | null
    last_dispensed_grams: number
    feed_level: number | null
    estimated_feed_grams: number | null

  feeder_schedules/{schedule_id}
    time: string
    ampm: string
    timeValue: number
    grams: number | null
    days: string                       # 7-char Sunday-first mask
    enabled: boolean
    isDone: boolean
    created_at: Timestamp
    effective_at_ms: epoch milliseconds
    last_outcome: "completed" | "blocked" | "skipped_insufficient" | "failed" | null
    last_occurrence_at: Timestamp | null

  feeder_commands/{command_id}
    command_type: "feed_now"
    grams: number | null
    issued_by: string
    issued_at: Timestamp
    expires_at: Timestamp
    near_schedule_confirmed: boolean

  feeder_logs/{log_id}
    # Append-only: authorized create + owner read; client update/delete denied
    action: string
    type: "auto" | "manual" | "missed" | "error" | "pending_confirmation"
    logged_at: Timestamp
    command_id: string | null
    schedule_key: string | null        # originating schedule, also used by missed audit
    schedule_time: string | null
    occurrence_at: Timestamp | null
    status: "completed" | "blocked" | "skipped_insufficient" | "failed" | null
    requested_grams: number | null
    estimated_dispensed_grams: number | null
    estimated_available_grams: number | null
    feed_level_before: number | null
    feed_level_after: number | null
    level_change_detected: boolean | null
    amount_basis: "servo_cycle_estimate" | null

  water_quality_anomaly_detections/current
    uid: string
    tank_id: string
    status: "Normal" | "Unusual" | "Insufficient"
    is_anomaly: boolean
    anomaly_score: number # reference-pattern percentile, not a safety score
    source: string
    analysis_window_minutes: number
    data_status: "ready" | "insufficient" | "stale"
    source_recorded_at: Timestamp | null
    source_age_seconds: number | null
    primary_driver: object | null # sensor, label, value, unit, direction, contribution_score
    driver, driver_label, driver_value, driver_unit
    contributors: array # ranked sensor contributions and directions
    insight, recommendation
    processed_at: Timestamp

  water_quality_anomaly_detection_history/{YYYYMMDDTHHMMSS}
    # Same anomaly-detection schema as `current`; retained as hourly history.
```

`effective_at_ms` is reset when a feeding schedule is created, edited, or re-enabled. It prevents an occurrence that happened before that instant from being falsely classified as missed.

The feeder log trigger sets date-scoped schedule outcomes. `isDone` is legacy compatibility only, not proof of success. Feeder history is append-only: authorized clients can create entries, but cannot update or delete an existing log. `pending_confirmation` is a non-terminal audit entry and therefore has no required `status`. Offline retries retain the original tank, occurrence timestamp and deterministic log id. Interrupted dispensing is recorded as failed and is not replayed after reboot. Supported doses are 20–200 g, in steps of 20 g; quantities and Consumption Today are servo-cycle estimates, not measured weights. Verify calibration on the actual hardware. App and ESP read all schedule pages.

Machine Learning-Based Water Quality Anomaly Detection (WQAD) uses an unsupervised `IsolationForest` over multivariate readings, spreads, changes, rolling behavior, and trends. It requires twelve contiguous ten-minute readings (±2-minute cadence tolerance), representing a two-hour window. Source data older than 20 minutes is marked stale/Insufficient. Safety thresholds remain separate: they are neither model features nor training labels. Model metadata clearly identifies the current artifact as a synthetic bootstrap until it is retrained and validated using calibrated field data from the actual tank.

Runtime event times (`logged_at`, `occurrence_at`, `last_changed`, `lastSeen`, `last_dispensed_at`, and `source_recorded_at`) are stored as Firestore Timestamps. `created_at` is the record creation time; fields such as `sampling_date` represent when the sampling event occurred. Readers remain compatible with legacy epoch-millisecond, Unix-second, ISO-string, and `DateTime` values during rollout. Explicit millisecond protocol fields (`effective_at_ms`, `source_assignment_at_ms`, `captured_at_ms`) remain integers because scheduling and sensor-routing logic compare them at millisecond precision.

## Production hierarchy

```text
tanks/{tank_id}/batches/{batch_id}
  batch_id: string
  batch_status: "active" | "harvested" | "superseded"
  stocking_date: Timestamp
  harvest_date: Timestamp | null
  ended_at: Timestamp | null # Set when superseded without harvest
  initial_count: number
  current_count: number
  harvest_count: number
  total_mortality: number
  harvest_weight_grams: number | null
  sample_count: number
  initial_total_weight: number
  initial_total_length: number
  created_at: Timestamp
  # App derives initial_abw = initial_total_weight / sample_count
  # and initial_abl = initial_total_length / sample_count.
  # Final ABW/ABL come from the latest sampling record; none are stored here.
  # The app derives days_in_culture from stocking_date to today, or harvest_date/ended_at when complete.

  sampling_records/{sampling_id}
    sampling_date: Timestamp
    sample_size: number
    total_weight: number
    total_length: number
    live_count: number
    is_baseline: boolean
    created_at: Timestamp
    # App derives avg_body_weight = total_weight / sample_size
    # avg_body_length = total_length / sample_size, and
    # biomass = live_count * (total_weight / sample_size); none are stored.

  mortality_records/{mortality_id}
    mortality_date: Timestamp
    mortality_count: number
    created_at: Timestamp

  harvest_records/{harvest_id}
    batch_id: string
    harvest_date: Timestamp
    harvest_count: number
    total_weight_kg: number
    created_at: Timestamp
    # App derives ABW as total_weight_kg * 1000 / harvest_count; not stored.
```

## ESP ingestion flow

```text
ESP32
  -> sensorIngestion/current
       hardwareId
       source_tank_id
       source_owner_uid
       source_assignment_at_ms
       captured_at_ms
       live sensor values
       turbidity_air
       buffered_entries

  -> sensorIngestion/current/history/{reading_id}
       hardwareId
       source_tank_id
       source_owner_uid
       source_assignment_at_ms
       captured_at_ms
       per-sensor 10-minute min/max/avg (only sensors with valid samples)

Cloud Functions read hardware_system/currentOwner
  -> tanks/{tank_id}/sensor_readings/latest
  -> tanks/{tank_id}/sensor_readings_history/{date}/entries/{reading_id}
```

`sensorIngestion` is internal system-managed staging data written by the dedicated ESP Email/Password service account. Invalid 10-minute sensor aggregates are omitted rather than stored as negative sentinels. The routed `recorded_at` preserves the ESP capture time when NTP was valid.

## Security note

### Capture binding and feeder reliability fields

Both sensor staging paths carry `source_tank_id`, `source_owner_uid`, `source_assignment_at_ms`, and `captured_at_ms`. The assignment timestamp is compared at millisecond precision. Functions only route matching capture assignments; old or unbound history stays staged with `routing_status: quarantined` / `routing_reason`. Older live events cannot overwrite newer readings. Coordinate firmware and ingestion-function rollout.

`feeder_commands` includes `expires_at` (Timestamp, app request deadline) and `near_schedule_confirmed` (owner warning-window acknowledgement). Firmware also applies a 60-second limit from the server's `issued_at`; legacy commands without the extra deadline use that server limit. Queued offline app writes cannot restart their deadline on reconnect. `near_schedule_confirmed` never bypasses the strict device-side collision block around a scheduled feeding. Status includes `command_id` / `status_reason`; logs add optional `command_id` for exact request confirmation. Missing confirmation does not create an app-authored failure log.

`tanks/{tank_id}/feeder_notification_receipts/{log_id}` stores `uid` and `push_attempt_claimed_at` (Timestamp). This server-only receipt is created in the same transaction as the deterministic inbox document before attempting FCM. Duplicate deliveries do not resend or reset `is_read`. A crash after claiming can suppress the push; the durable inbox remains. No exactly-once FCM guarantee is claimed.

The current ESP firmware authenticates with the dedicated Firebase Email/Password service account `esp32@craycare.com`. Firestore rules require the password provider and exact authenticated email for ESP-only paths. Its rotated password is stored only in the gitignored device `secrets.h`. A future multi-device production rollout should provision a distinct identity/custom claim for every physical device.
