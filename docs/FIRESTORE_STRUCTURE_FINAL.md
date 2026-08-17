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

The admin changes only this document to assign/reassign the one ESP32 system. New readings are routed to `tanks/{tank_id}`. Existing readings remain in the previous tank.

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
    water_level: number  # centimetres
    turbidity_air: boolean
    recorded_at: Timestamp

  sensor_readings_history/{YYYY-MM-DD}/entries/{reading_id}
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
    isRunning: boolean
    feedSource: string
    feedCount: number
    hopperLevel: number
    lastSeen: epoch milliseconds
    last_dispensed_at: epoch milliseconds | null
    last_dispensed_grams: number

  feeder_schedules/{schedule_id}
    feed_time: string
    time: string
    ampm: string
    timeValue: number
    grams: number | null
    portion_grams: number | null
    enabled: boolean
    is_active: boolean
    isDone: boolean
    created_at: Timestamp

  feeder_commands/{command_id}
    command_type: "feed_now"
    grams: number | null
    issued_by: string
    issued_at: Timestamp

  feeder_logs/{log_id}
    action: string
    type: string
    time: string
    date: string
    logged_at: epoch milliseconds
```

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
    survival_rate: number
    created_at: Timestamp

  ml_predictions/current
    level: "Low" | "Moderate" | "High" | "Critical" | "Insufficient"
    confidence: number
    driver, driver_label, driver_value, driver_unit
    driver_min, driver_max
    problem, insight, action, source, analysis_mode
    samples_analyzed, required_samples
    timestamp: ISO-8601 string
```

## ESP ingestion flow

```text
ESP32
  -> sensorIngestion/current
  -> sensorIngestion/current/history/{reading_id}

Cloud Function reads hardware_system/currentOwner.tank_id
  -> tanks/{tank_id}/sensor_readings/latest
  -> tanks/{tank_id}/sensor_readings_history/{date}/entries/{reading_id}
```

`sensorIngestion` is internal system-managed data. Do not create it manually.
