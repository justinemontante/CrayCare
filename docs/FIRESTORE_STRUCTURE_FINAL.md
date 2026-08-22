# CrayCare Firestore Structure — Final Normalized Schema

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
  tank_id: string | null
  fcmTokens: string[]
  created_at: Timestamp

  notification_settings/preferences
    sound: boolean
    vibration: boolean
    critical: boolean
    warning: boolean
    feeding: boolean
    sampling: boolean
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

A valid assignment is either fully unassigned (`uid == null` and `tank_id == null`) or points to an **active owner** whose profile `tank_id` exactly matches. Flutter clears the assignment atomically when the assigned owner is disabled, Firestore rules reject invalid client assignments, and Cloud Functions clear invalid Console/Admin-SDK assignments as defense in depth.

## Tank and hardware data

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

  sensors/{temperature|ph_level|dissolved_oxygen|turbidity|water_level}
    min_value: number
    max_value: number
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
    status: "idle" | "dispensing"
    dispenseCount: number
    lastSeen: epoch milliseconds
    last_dispensed_at: epoch milliseconds | null
    last_dispensed_grams: number

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

  feeder_commands/{command_id}
    command_type: "feed_now"
    grams: number | null
    issued_by: string
    issued_at: Timestamp

  feeder_logs/{log_id}
    action: string
    type: "auto" | "manual" | "missed" | "error"
    logged_at: epoch milliseconds
    schedule_key: string | null        # missed-schedule audit only
    schedule_time: string | null       # missed-schedule audit only

  machine_learning_assessments/current
    uid: string
    tank_id: string
    level: "Good" | "Moderate" | "Poor" | "Critical" | "Insufficient"
    model_level: "Good" | "Moderate" | "Poor" | "Critical" | "Insufficient"
    rule_level: "Good" | "Moderate" | "Poor" | "Critical" | "Insufficient"
    safety_override: boolean
    confidence: number
    driver, driver_label, driver_value, driver_unit
    driver_min, driver_max
    problem, insight, action
    concerns: array
    secondary_concerns: array
    ts_epoch: epoch seconds
    timestamp: ISO-8601 string

  machine_learning_assessments/{YYYYMMDDTHHMMSS}
    # Same assessment schema as `current`; retained as hourly history.
```

`effective_at_ms` is reset when a feeding schedule is created, edited, or re-enabled. It prevents an occurrence that happened before that instant from being falsely classified as missed.

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

The current ESP firmware authenticates with Firebase Anonymous Auth. Firestore rules therefore still treat an anonymous Firebase session as an ESP session. This is an acknowledged pre-production limitation: production deployment should provision a persistent device identity/custom claim rather than trusting every anonymous session.
