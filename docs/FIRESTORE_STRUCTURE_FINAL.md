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
tanks/{tank_id}
  owner_uid: string
  current_batch_id: string
  initial_population: number
  stocking_date: epoch milliseconds
  last_sample_date: epoch milliseconds
  sample_count: number
  initial_total_sample_weight: number
  initial_total_sample_length: number
  is_initialized: boolean
  created_at: Timestamp

  sensor_readings/latest
    temperature: number
    ph_level: number
    dissolved_oxygen: number
    turbidity: number
    turbidity_air: boolean
    water_level: number                # centimeters
    feed_level: number                 # hopper percentage; operational only
    estimated_feed_grams: number       # percentage × configured capacity
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
      recorded_at: Timestamp

  sensors/{temperature|ph_level|dissolved_oxygen|turbidity|water_level|feed_level}
    min_value: number
    max_value: number
    critical_value: number | null      # feed_level only
    hopper_capacity_grams: number|null # feed_level only
    updated_at: Timestamp

  actuators/{pump|aerator1|aerator2}
    control_mode: "on" | "off" | "auto"
    current_state: "on" | "off"
    last_changed: epoch milliseconds

  actuator_logs/{log_id}
    actuator_type: string
    action: string
    type: string
    logged_at: epoch milliseconds

  feeder/status
    status: "idle" | "checking_feed_level" | "dispensing" | "completed" | "skipped_insufficient" | "blocked"
    dispenseCount: number
    lastSeen: epoch milliseconds
    last_dispensed_at: epoch milliseconds | null
    last_dispensed_grams: number
    feed_level: number
    estimated_feed_grams: number

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
    last_outcome: "completed" | "skipped_insufficient" | "blocked" | "failed" | null
    last_occurrence_at: epoch milliseconds | null

  feeder_commands/{command_id}
    command_type: "feed_now"
    grams: number | null
    issued_by: string
    issued_at: Timestamp

  feeder_logs/{log_id}
    # Append-only: authorized create + owner read; client update/delete denied
    action: string
    type: "auto" | "manual" | "missed" | "error"
    logged_at: epoch milliseconds
    schedule_key: string | null        # originating schedule, also used by missed audit
    schedule_time: string | null
    occurrence_at: epoch milliseconds | null
    status: "completed" | "skipped_insufficient" | "blocked" | "failed" | null
    requested_grams: number | null
    estimated_dispensed_grams: number | null
    amount_basis: "servo_cycle_estimate" | null
    estimated_available_grams: number | null
    feed_level_before: number | null
    feed_level_after: number | null
    level_change_detected: boolean | null
    verification_note: string | null

  water_quality_anomaly_detections/current
    uid: string
    tank_id: string
    status: "Normal" | "Unusual" | "Insufficient"
    is_anomaly: boolean
    anomaly_score: number # reference-pattern percentile, not a safety score
    source: string
    model_algorithm: "IsolationForest" | "Not applied"
    model_version: string
    training_data_origin: string
    training_label_origin: "none_unsupervised"
    model_feature_count: number
    analysis_window_minutes: number
    data_status: "ready" | "insufficient" | "stale"
    source_recorded_at: ISO-8601 string | null
    source_age_seconds: number | null
    driver, driver_label, driver_value, driver_unit
    contributors: array # ranked sensor contributions and directions
    insight, recommendation
    ts_epoch: epoch seconds
    timestamp: ISO-8601 string

  water_quality_anomaly_detections/{YYYYMMDDTHHMMSS}
    # Same anomaly-detection schema as `current`; retained as hourly history.
```

`effective_at_ms` is reset when a feeding schedule is created, edited, or re-enabled. It prevents an occurrence that happened before that instant from being falsely classified as missed.

The feeder log trigger sets date-scoped schedule outcomes. `isDone` is legacy compatibility only, not proof of success. Feeder history is append-only: authorized clients can create entries, but cannot update or delete an existing log. Offline retries retain the original tank, occurrence timestamp and deterministic log id. Interrupted dispensing is recorded as failed and is not replayed after reboot. Supported doses are 20–200 g, in steps of 20 g; quantities and Consumption Today are servo-cycle estimates, not measured weights. Verify calibration on the actual hardware. App and ESP read all schedule pages.

Machine Learning-Based Water Quality Anomaly Detection (WQAD) uses an unsupervised `IsolationForest` over multivariate readings, spreads, changes, rolling behavior, and trends. It requires twelve contiguous ten-minute readings (±2-minute cadence tolerance), representing a two-hour window. Source data older than 20 minutes is marked stale/Insufficient. Safety thresholds remain separate: they are neither model features nor training labels. Model metadata clearly identifies the current artifact as a synthetic bootstrap until it is retrained and validated using calibrated field data from the actual tank.

New feeder/actuator runtime writes use epoch milliseconds for `logged_at`. Flutter readers retain compatibility with legacy Firestore `Timestamp`, `DateTime`, ISO-string, Unix-second, and Unix-millisecond values where applicable.

## Production hierarchy

```text
tanks/{tank_id}/batches/{batch_id}
  batch_id: string
  batch_status: "active" | "harvested" | "superseded"
  stocking_date: epoch milliseconds
  harvest_date: epoch milliseconds | null
  initial_count: number
  current_count: number
  harvest_count: number
  total_mortality: number
  harvest_weight_grams: number | null
  initial_abw: number
  initial_abl: number
  final_abw: number
  final_abl: number
  days_in_culture: number
  sample_count: number
  initial_total_weight: number
  initial_total_length: number
  created_at: Timestamp

  sampling_records/{sampling_id}
    sampling_date: epoch milliseconds
    avg_body_weight: number
    avg_body_length: number
    sample_size: number
    total_weight: number
    total_length: number
    biomass: number
    live_count: number
    is_baseline: boolean
    created_at: Timestamp

  mortality_records/{mortality_id}
    mortality_date: epoch milliseconds
    mortality_count: number
    created_at: Timestamp

  harvest_records/{harvest_id}
    batch_id: string
    harvest_date: epoch milliseconds
    harvest_count: number
    total_weight_kg: number
    abw_grams: number
    created_at: Timestamp
```

## ESP ingestion flow

```text
ESP32
  -> sensorIngestion/current
       hardwareId
       live sensor values
       turbidity_air
       buffered_entries

  -> sensorIngestion/current/history/{reading_id}
       hardwareId
       per-sensor 10-minute min/max/avg (only sensors with valid samples)
       captured_at_ms

Cloud Functions read hardware_system/currentOwner
  -> tanks/{tank_id}/sensor_readings/latest
  -> tanks/{tank_id}/sensor_readings_history/{date}/entries/{reading_id}
```

`sensorIngestion` is internal system-managed staging data. Invalid 10-minute sensor aggregates are omitted rather than stored as negative sentinels. The routed `recorded_at` preserves the ESP capture time when NTP was valid.

## Security note

### Capture binding and feeder reliability fields

Both sensor staging paths carry `source_tank_id`, `source_owner_uid`, `source_assignment_at_ms`, and `captured_at_ms`. The assignment timestamp is compared at millisecond precision. Functions only route matching capture assignments; old or unbound history stays staged with `routing_status: quarantined` / `routing_reason`. Older live events cannot overwrite newer readings. Coordinate firmware and ingestion-function rollout.

`feeder_commands` adds `expires_at` (Timestamp, app request deadline). Firmware also applies a 60-second limit from the server's `issued_at`; legacy commands without the extra deadline use that server limit. Queued offline app writes cannot restart their deadline on reconnect. Status adds `command_id` / `status_reason`; logs add optional `command_id` for exact request confirmation. Missing confirmation does not create an app-authored failure log.

`tanks/{tank_id}/feeder_notification_receipts/{log_id}` stores `uid` and `push_attempt_claimed_at` (Timestamp). This server-only receipt is created in the same transaction as the deterministic inbox document before attempting FCM. Duplicate deliveries do not resend or reset `is_read`. A crash after claiming can suppress the push; the durable inbox remains. No exactly-once FCM guarantee is claimed.

The current ESP firmware authenticates with the dedicated Firebase Email/Password service account `esp32@craycare.com`. Firestore rules require the password provider and exact authenticated email for ESP-only paths. Its rotated password is stored only in the gitignored device `secrets.h`. A future multi-device production rollout should provision a distinct identity/custom claim for every physical device.
