from __future__ import annotations

import shutil
from pathlib import Path

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path(r"C:\Users\SLUMDUNK\Desktop\Crayfish Flutter UI\craycare")
DOCX = ROOT / "docs" / "Chapters 1–3.docx"
BACKUP = ROOT / ".codex_doc_review" / "Chapters 1–3.before-data-dictionary.docx"


def f(name, dtype, constraints, description):
    return (name, dtype, constraints, description)


COLLECTIONS = [
    {
        "section": "1. Users and Access Management",
        "sub": "1.1 users/{uid}",
        "path": "users/{uid}",
        "description": "Stores the authenticated user's profile, access role, account status, and registered notification tokens. The document ID is the Firebase Authentication UID. Tank ownership is not duplicated here; it lives in tanks/{tankId}.owner_uid (tank ID equals owner UID).",
        "fields": [
            f("full_name", "string", "Required", "User's complete display name."),
            f(
                "email",
                "string",
                "Required; unique",
                "Email address used for authentication and account recovery.",
            ),
            f(
                "role",
                "string",
                "owner | admin",
                "Access role. Only one active administrator account is intended; owners operate assigned tank features.",
            ),
            f(
                "status",
                "string",
                "active | disabled",
                "Controls whether the account may use protected app features.",
            ),
            f(
                "photo_url",
                "string",
                "Optional",
                "Canonical profile-image URL. photoUrl may remain only as a legacy alias.",
            ),
            f(
                "fcmTokens",
                "array<string>",
                "Default: empty",
                "Notification token for each signed-in device.",
            ),
            f(
                "fcmToken",
                "string",
                "Legacy; optional",
                "Single-token compatibility field for older app versions.",
            ),
            f(
                "created_at",
                "timestamp",
                "Server timestamp",
                "Time the profile document was created.",
            ),
        ],
    },
    {
        "sub": "1.2 users/{uid}/notification_settings/preferences",
        "path": "users/{uid}/notification_settings/preferences",
        "description": "Stores the user's notification-channel and notification-category preferences.",
        "fields": [
            f(
                "sound",
                "boolean",
                "Default: true",
                "Enables notification sound where permitted by the device.",
            ),
            f(
                "vibration",
                "boolean",
                "Default: true",
                "Enables vibration where permitted by the device.",
            ),
            f(
                "critical",
                "boolean",
                "Default: true",
                "Enables critical water-quality notifications.",
            ),
            f(
                "warning",
                "boolean",
                "Default: true",
                "Enables warning-level water-quality notifications.",
            ),
            f(
                "feeding",
                "boolean",
                "Default: true",
                "Enables feeding reminders and completed/skipped feeding results.",
            ),
            f(
                "sampling",
                "boolean",
                "Default: true",
                "Enables tank sampling reminders.",
            ),
            f(
                "operational",
                "boolean",
                "Default: true",
                "Enables actuator, device, and sensor-recovery updates.",
            ),
            f(
                "updated_at",
                "timestamp",
                "Server timestamp",
                "Time the preferences were last updated.",
            ),
        ],
    },
    {
        "sub": "1.3 users/{uid}/notif_markers/{key}",
        "path": "users/{uid}/notif_markers/{key}",
        "description": "Stores idempotency markers used by scheduled checks so that the same reminder is not created repeatedly.",
        "fields": [
            f(
                "markerKey",
                "string",
                "Required",
                "Stable identifier for the reminder or scheduled check.",
            ),
            f(
                "value",
                "boolean | string | number",
                "Required",
                "Marker state or last processed value.",
            ),
            f(
                "updated_at",
                "timestamp",
                "Server timestamp",
                "Time the marker was last changed.",
            ),
        ],
    },
    {
        "section": "2. Hardware Assignment",
        "sub": "2.1 hardware_system/currentOwner",
        "path": "hardware_system/currentOwner",
        "description": "Single system document that binds the physical CrayCare hardware to one active owner and that owner's tank.",
        "fields": [
            f(
                "uid",
                "string | null",
                "Active owner UID or null",
                "UID of the currently assigned owner.",
            ),
            f(
                "tank_id",
                "string | null",
                "Must match user's tank_id",
                "Tank receiving data and device operations from the assigned hardware.",
            ),
            f(
                "assigned_by",
                "string",
                "Admin UID",
                "Administrator who made the assignment.",
            ),
            f(
                "assigned_at",
                "timestamp",
                "Server timestamp",
                "Time the assignment became effective.",
            ),
        ],
        "note": "A valid unassigned state uses both uid and tank_id as null. Disabling the assigned owner clears this document atomically.",
    },
    {
        "section": "3. Tanks and Sensor Data",
        "sub": "3.1 tanks/{tankId}",
        "path": "tanks/{tankId}",
        "description": "Core tank document containing ownership and current grow-out-cycle summary information.",
        "fields": [
            f(
                "owner_uid",
                "string",
                "Required",
                "UID of the owner responsible for the tank.",
            ),
            f(
                "current_batch_id",
                "string | null",
                "Optional",
                "Identifier of the active production batch.",
            ),
            f(
                "stocking_date",
                "timestamp",
                "Optional",
                "Date and time the current grow-out cycle was stocked.",
            ),
            f(
                "last_sample_date",
                "timestamp",
                "Optional",
                "Date of the latest recorded sample.",
            ),
            f(
                "sample_count",
                "number",
                "Default: 0",
                "Number of samples recorded for the current cycle.",
            ),
            f(
                "initial_population",
                "number",
                "Non-negative integer",
                "Counted population stocked at the beginning of the cycle.",
            ),
            f(
                "initial_total_sample_weight",
                "number",
                "Optional; grams",
                "Total weight of the baseline sample.",
            ),
            f(
                "initial_total_sample_length",
                "number",
                "Optional; centimeters",
                "Total length of the baseline sample.",
            ),
            f(
                "is_initialized",
                "boolean",
                "Default: false",
                "Whether tank and baseline production data have been initialized.",
            ),
            f(
                "created_at",
                "timestamp",
                "Server timestamp",
                "Time the tank document was created.",
            ),
        ],
    },
    {
        "sub": "3.2 tanks/{tankId}/sensor_readings/latest",
        "path": "tanks/{tankId}/sensor_readings/latest",
        "description": "Latest routed sensor snapshot used by the live dashboard. It is updated from the assigned ESP32's staging document.",
        "fields": [
            f("temperature", "number", "degrees Celsius", "Current water temperature."),
            f("ph_level", "number", "pH", "Current acidity or alkalinity reading."),
            f(
                "dissolved_oxygen",
                "number",
                "mg/L",
                "Current dissolved oxygen concentration.",
            ),
            f("turbidity", "number", "NTU", "Current water turbidity."),
            f(
                "turbidity_air",
                "number",
                "Optional",
                "Air/reference reading used by the turbidity integration.",
            ),
            f("water_level", "number", "centimeters", "Current pond water level."),
            f(
                "feed_level",
                "number",
                "0-100 percent",
                "Estimated percentage of feed remaining in the hopper; operational only and excluded from WQA inputs.",
            ),
            f(
                "estimated_feed_grams",
                "number",
                "Optional; grams",
                "Estimated remaining feed derived from feed level and calibrated hopper capacity.",
            ),
            f(
                "buffered_entries",
                "number",
                "Optional",
                "Number of locally buffered readings reported by the ESP32.",
            ),
            f(
                "recorded_at",
                "timestamp",
                "Required",
                "Original sensor capture time preserved during routing.",
            ),
        ],
    },
    {
        "sub": "3.3 tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}",
        "path": "tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}",
        "description": "Daily summary document used for efficient long-range analytics. Only complete and sanitized summaries are consumed by the optimized reader.",
        "fields": [
            f(
                "date_key",
                "string",
                "YYYY-MM-DD",
                "Calendar key represented by this daily document.",
            ),
            f(
                "summary_version",
                "number",
                "Current: 1",
                "Schema/version number of the summary computation.",
            ),
            f(
                "summary_sanitized",
                "boolean",
                "Required",
                "Confirms invalid sentinel and non-finite values have been removed.",
            ),
            f(
                "summary_complete",
                "boolean",
                "Required",
                "Indicates whether the daily summary is ready for optimized reads.",
            ),
            f(
                "sample_count",
                "number",
                "Default: 0",
                "Number of valid history entries included.",
            ),
            f(
                "processed_entry_ids",
                "array<string>",
                "Default: empty",
                "Entry IDs already included, used for idempotent summary maintenance.",
            ),
            f(
                "temp_min/max/avg/sum/count",
                "number fields",
                "When data exists",
                "Daily temperature statistics.",
            ),
            f(
                "pH_min/max/avg/sum/count",
                "number fields",
                "When data exists",
                "Daily pH statistics.",
            ),
            f(
                "DO_min/max/avg/sum/count",
                "number fields",
                "When data exists",
                "Daily dissolved-oxygen statistics.",
            ),
            f(
                "turbidity_min/max/avg/sum/count",
                "number fields",
                "When data exists",
                "Daily turbidity statistics.",
            ),
            f(
                "waterLevel_min/max/avg/sum/count",
                "number fields",
                "When data exists",
                "Daily water-level statistics.",
            ),
            f(
                "updated_at",
                "timestamp",
                "Server timestamp",
                "Time the daily summary was last maintained.",
            ),
        ],
    },
    {
        "sub": "3.4 tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{docId}",
        "path": "tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{docId}",
        "description": "Ten-minute MIN/MAX/AVG sensor aggregate. Invalid sensors are omitted instead of being stored as negative sentinel values.",
        "fields": [
            f(
                "temp_min, temp_max, temp_avg",
                "number",
                "degrees Celsius",
                "Temperature statistics for the ten-minute window.",
            ),
            f(
                "pH_min, pH_max, pH_avg",
                "number",
                "pH",
                "pH statistics for the ten-minute window.",
            ),
            f(
                "DO_min, DO_max, DO_avg",
                "number",
                "mg/L",
                "Dissolved-oxygen statistics for the window.",
            ),
            f(
                "turbidity_min/max/avg",
                "number",
                "NTU",
                "Turbidity statistics for the window.",
            ),
            f(
                "waterLevel_min/max/avg",
                "number",
                "centimeters",
                "Water-level statistics for the window.",
            ),
            f(
                "feed_level",
                "number",
                "Optional; percent",
                "Operational hopper-level snapshot; excluded from WQA model features.",
            ),
            f(
                "estimated_feed_grams",
                "number",
                "Optional; grams",
                "Estimated feed remaining during the aggregate window.",
            ),
            f(
                "recorded_at",
                "timestamp",
                "Required",
                "Original capture time of the completed ten-minute window.",
            ),
        ],
    },
    {
        "sub": "3.5 tanks/{tankId}/sensors/{sensorName}",
        "path": "tanks/{tankId}/sensors/{sensorName}",
        "description": "Per-tank threshold document for temperature, ph_level, dissolved_oxygen, turbidity, water_level, or feed_level.",
        "fields": [
            f(
                "min_value",
                "number",
                "Required",
                "Lower boundary of the configured normal/ideal range.",
            ),
            f(
                "max_value",
                "number",
                "Required",
                "Upper boundary of the configured normal/ideal range.",
            ),
            f(
                "critical_value",
                "number",
                "feed_level only",
                "Percentage below which the feed level is critical. This alone does not prevent feeding.",
            ),
            f(
                "hopper_capacity_grams",
                "number",
                "feed_level only",
                "Calibrated feed mass when the hopper is full; used to estimate remaining grams.",
            ),
            f(
                "updated_at",
                "timestamp",
                "Server timestamp",
                "Time the threshold configuration was last updated.",
            ),
        ],
        "note": "The feed level statuses are Normal (>20%), Low (11-20%), Critical (1-10%), and Empty (0%). Feeding is skipped only when feed is empty, unavailable, or estimated grams are below the requested amount.",
    },
    {
        "section": "4. Actuators",
        "sub": "4.1 tanks/{tankId}/actuators/{deviceId}",
        "path": "tanks/{tankId}/actuators/{deviceId}",
        "description": "Stores requested mode and reported state for pump, aerator1, or aerator2.",
        "fields": [
            f(
                "control_mode",
                "string",
                "on | off | auto",
                "Operating mode requested by the owner.",
            ),
            f(
                "current_state",
                "string",
                "on | off",
                "Actual relay state reported by the ESP32.",
            ),
            f(
                "last_changed",
                "number",
                "Epoch milliseconds; 0 = never",
                "Time the device state or mode last changed.",
            ),
        ],
    },
    {
        "sub": "4.2 tanks/{tankId}/actuator_logs/{logId}",
        "path": "tanks/{tankId}/actuator_logs/{logId}",
        "description": "Audit record for actuator operations.",
        "fields": [
            f(
                "actuator_type",
                "string",
                "pump | aerator1 | aerator2",
                "Device associated with the event.",
            ),
            f(
                "action",
                "string",
                "Required",
                "Human-readable description of the operation.",
            ),
            f("type", "string", "on | off | auto", "Machine-readable operation type."),
            f(
                "logged_at",
                "number | timestamp",
                "New writes: epoch ms",
                "Time the operation occurred; legacy timestamp forms remain readable.",
            ),
        ],
    },
    {
        "section": "5. Automatic Feeder",
        "sub": "5.1 tanks/{tankId}/feeder/status",
        "path": "tanks/{tankId}/feeder/status",
        "description": "Single live feeder-status document written by the assigned ESP32.",
        "fields": [
            f(
                "status",
                "string",
                "idle | checking_feed_level | dispensing | completed | skipped_insufficient | blocked",
                "Current or most recent feeder state.",
            ),
            f(
                "status_reason",
                "string",
                "Optional",
                "Human-readable explanation when feeding is blocked or skipped.",
            ),
            f(
                "command_id",
                "string",
                "Optional",
                "Manual command correlated with the current outcome.",
            ),
            f(
                "dispenseCount",
                "number",
                "Default: 0",
                "Cumulative completed dispensing cycles.",
            ),
            f(
                "lastSeen",
                "number",
                "Epoch milliseconds",
                "Most recent feeder heartbeat/status time.",
            ),
            f(
                "last_dispensed_at",
                "number | timestamp",
                "Optional",
                "Time of the last completed dispensing cycle.",
            ),
            f(
                "last_dispensed_grams",
                "number",
                "Optional; estimated grams",
                "Estimated amount associated with the last completed cycle.",
            ),
            f(
                "feed_level",
                "number",
                "0-100 percent",
                "Latest hopper level available to the feeder.",
            ),
            f(
                "estimated_feed_grams",
                "number",
                "Optional; grams",
                "Estimated mass remaining in the hopper.",
            ),
        ],
    },
    {
        "sub": "5.2 tanks/{tankId}/feeder_schedules/{scheduleId}",
        "path": "tanks/{tankId}/feeder_schedules/{scheduleId}",
        "description": "Recurring automatic-feeding schedule. The app blocks overlapping schedules that share at least one day and the same time, regardless of feed amount.",
        "fields": [
            f("time", "string", "H:MM", "Human-readable scheduled time."),
            f("ampm", "string", "AM | PM", "Meridiem indicator."),
            f(
                "timeValue",
                "number",
                "0-1439",
                "Minutes since midnight, used for ordering and overlap validation.",
            ),
            f(
                "grams",
                "number | null",
                "20-200; multiples of 20",
                "Estimated feed amount. Null uses the default 20 g.",
            ),
            f(
                "days",
                "array<string> | string mask",
                "At least one active day",
                "Recurring days of the week. Firmware may use a Sunday-first seven-character mask.",
            ),
            f("enabled", "boolean", "Default: true", "Whether the schedule is active."),
            f(
                "isDone",
                "boolean",
                "Legacy compatibility",
                "True only for a completed latest occurrence; not the authoritative outcome.",
            ),
            f(
                "created_at",
                "timestamp",
                "Server timestamp",
                "Time the schedule was created.",
            ),
            f(
                "effective_at_ms",
                "number",
                "UTC epoch milliseconds",
                "Creation/edit/re-enable time; prevents earlier occurrences from being marked missed.",
            ),
            f(
                "last_outcome",
                "string",
                "completed | skipped_insufficient | blocked | failed",
                "Reconciled outcome of the latest applicable occurrence.",
            ),
            f(
                "last_occurrence_at",
                "number",
                "UTC epoch milliseconds",
                "Scheduled minute associated with last_outcome.",
            ),
        ],
    },
    {
        "sub": "5.3 tanks/{tankId}/feeder_logs/{logId}",
        "path": "tanks/{tankId}/feeder_logs/{logId}",
        "description": "Append-only audit log for manual, scheduled, missed, blocked, skipped, failed, and completed feeding events.",
        "fields": [
            f(
                "action",
                "string",
                "Required",
                "Human-readable feeding-event description.",
            ),
            f(
                "type",
                "string",
                "auto | manual | missed | error",
                "Source/category of the feeder event.",
            ),
            f(
                "status",
                "string",
                "completed | skipped_insufficient | blocked | failed",
                "Terminal result reported by the ESP32.",
            ),
            f("command_id", "string", "Optional", "Originating manual command ID."),
            f(
                "schedule_key",
                "string",
                "Scheduled feeds only",
                "Originating schedule document ID.",
            ),
            f(
                "schedule_time",
                "string",
                "Scheduled feeds only",
                "Original schedule time shown in the audit record.",
            ),
            f(
                "occurrence_at",
                "number",
                "UTC epoch milliseconds",
                "Original occurrence time retained through offline retries.",
            ),
            f(
                "requested_grams",
                "number",
                "Required for execution",
                "Feed amount requested by the command or schedule.",
            ),
            f(
                "estimated_dispensed_grams",
                "number",
                "Completed only",
                "Servo-cycle estimate; not scale-measured proof of actual mass.",
            ),
            f(
                "amount_basis",
                "string",
                "servo_cycle_estimate",
                "Explains the basis of the estimated dispensed amount.",
            ),
            f(
                "estimated_available_grams",
                "number",
                "Optional",
                "Estimated hopper mass available before execution.",
            ),
            f(
                "feed_level_before",
                "number",
                "Optional; percent",
                "Hopper percentage before dispensing.",
            ),
            f(
                "feed_level_after",
                "number",
                "Optional; percent",
                "Hopper percentage after dispensing.",
            ),
            f(
                "level_change_detected",
                "boolean",
                "Optional",
                "Supporting indication of feed movement; not proof of exact grams.",
            ),
            f(
                "verification_note",
                "string",
                "Optional",
                "Additional interpretation of the before/after feed-level check.",
            ),
            f(
                "logged_at",
                "number | timestamp",
                "New writes: epoch ms",
                "Original event time. Completed logs alone contribute to Consumption Today.",
            ),
        ],
    },
    {
        "sub": "5.4 tanks/{tankId}/feeder_commands/{commandId}",
        "path": "tanks/{tankId}/feeder_commands/{commandId}",
        "description": "Short-lived one-shot manual feeding request consumed by the assigned ESP32.",
        "fields": [
            f("command_type", "string", "feed_now", "Requested manual action."),
            f(
                "grams",
                "number | null",
                "20-200; multiples of 20",
                "Requested amount; null uses the default 20 g.",
            ),
            f("issued_by", "string", "Owner UID", "User who created the request."),
            f(
                "issued_at",
                "timestamp",
                "Server timestamp",
                "Authoritative request-creation time.",
            ),
            f(
                "expires_at",
                "timestamp",
                "Required for new writes",
                "Application deadline; firmware also rejects requests more than 60 seconds old.",
            ),
        ],
        "note": "Deletion of a command is not proof of completed feeding. The UI confirms outcomes using a matching command_id in feeder status/log records.",
    },
    {
        "sub": "5.5 tanks/{tankId}/feeder_notification_receipts/{logId}",
        "path": "tanks/{tankId}/feeder_notification_receipts/{logId}",
        "description": "Server-only at-most-once claim used to prevent duplicate push attempts for feeder outcome logs.",
        "fields": [
            f("uid", "string", "Required", "Recipient owner UID."),
            f(
                "push_attempt_claimed_at",
                "timestamp",
                "Server timestamp",
                "Time the backend claimed the notification attempt.",
            ),
        ],
        "note": "A receipt proves that the push attempt was claimed, not that the device received the FCM message. The notification inbox record remains available.",
    },
    {
        "section": "6. Machine Learning-Based Water Quality Anomaly Detection (WQAD)",
        "sub": "6.1 tanks/{tankId}/water_quality_anomaly_detections/{detectionId}",
        "path": "tanks/{tankId}/water_quality_anomaly_detections/{detectionId}",
        "description": "Stores the current and hourly Water Quality Anomaly Detection result. The current document ID is current; historical IDs use sortable UTC timestamps (YYYYMMDDTHHMMSS). The unsupervised IsolationForest analyzes water-sensor history and does not directly control actuators.",
        "fields": [
            f("uid", "string", "Required", "Owner UID associated with the detection."),
            f("tank_id", "string", "Required", "Tank evaluated by the detection."),
            f(
                "status",
                "string",
                "Normal | Unusual | Insufficient",
                "Final user-facing result after data-availability handling.",
            ),
            f(
                "is_anomaly",
                "boolean",
                "Default: false",
                "True when the raw score reaches the 98th-percentile reference cutoff.",
            ),
            f(
                "anomaly_score",
                "number",
                "0-100 percentile",
                "Reference-pattern percentile of the current reading versus the trained reference history.",
            ),
            f(
                "source",
                "string",
                "Required",
                "Distinguishes trained model output, insufficient data, or stale data.",
            ),
            f(
                "model_algorithm",
                "string",
                "IsolationForest | Not applied",
                "Algorithm recorded for traceability.",
            ),
            f(
                "model_version",
                "string",
                "Required when model used",
                "Version embedded in the deployed model artifact.",
            ),
            f(
                "training_data_origin",
                "string",
                "Required",
                "Origin of model-training records, such as synthetic bootstrap or actual tank history.",
            ),
            f(
                "training_label_origin",
                "string",
                "none_unsupervised",
                "Unsupervised model; no threshold-derived training labels are used.",
            ),
            f(
                "model_feature_count",
                "number",
                "Required when model used",
                "Number of engineered model inputs.",
            ),
            f(
                "analysis_window_minutes",
                "number",
                "Default: 120",
                "Historical duration analyzed for the detection.",
            ),
            f(
                "data_status",
                "string",
                "ready | insufficient | stale",
                "Availability and freshness classification of the input history.",
            ),
            f(
                "source_recorded_at",
                "string | null",
                "ISO-8601",
                "Timestamp of the newest actual source reading.",
            ),
            f(
                "source_age_seconds",
                "number",
                "Non-negative",
                "Age of the newest source reading at processing time.",
            ),
            f(
                "driver",
                "string",
                "temp | pH | DO | turbidity | waterLevel | overall | N/A",
                "Primary sensor driving the result.",
            ),
            f("driver_label", "string", "Required", "Human-readable driver name."),
            f(
                "driver_value",
                "number | null",
                "Optional",
                "Representative value of the primary driver.",
            ),
            f("driver_unit", "string", "Optional", "Measurement unit of driver_value."),
            f(
                "contributors",
                "array",
                "Top 3 ranked sensors",
                "Ranked sensor contributions with label, value, unit, direction, and contribution score.",
            ),
            f("insight", "string", "Optional", "Trend-aware explanation for the user."),
            f(
                "recommendation",
                "string",
                "Optional",
                "Verification-focused recommended response.",
            ),
            f(
                "ts_epoch",
                "number",
                "UTC epoch seconds",
                "Sortable processing timestamp used by history queries.",
            ),
            f(
                "timestamp",
                "string",
                "ISO-8601",
                "Human-readable detection processing time.",
            ),
        ],
        "note": "Inference requires at least twelve valid contiguous ten-minute records (two-hour pattern). A newest source record older than 20 minutes produces Insufficient/stale instead of inferring a current condition. Feed level is not a WQAD feature. Sensor safety thresholds remain separate and are never used as model inputs or training labels.",
    },
    {
        "section": "7. Grow-Out Production and Sampling",
        "sub": "7.1 tanks/{tankId}/batches/{batchId}",
        "path": "tanks/{tankId}/batches/{batchId}",
        "description": "Stores one crayfish grow-out batch and its current production summary. Population values are counted; biomass is estimated from sampling.",
        "fields": [
            f(
                "batch_status",
                "string",
                "active | harvested | superseded",
                "Current lifecycle state of the batch.",
            ),
            f(
                "stocking_date",
                "timestamp",
                "Required",
                "Stocking date; the setup calendar day is Day 0.",
            ),
            f("harvest_date", "timestamp", "Optional", "Date the batch was harvested."),
            f(
                "initial_count",
                "number",
                "Non-negative integer",
                "Counted population stocked at Day 0.",
            ),
            f(
                "current_count",
                "number",
                "Non-negative integer",
                "Counted population after recorded mortality and harvest events.",
            ),
            f(
                "harvest_count",
                "number",
                "Default: 0",
                "Cumulative crayfish harvested.",
            ),
            f(
                "total_mortality",
                "number",
                "Default: 0",
                "Cumulative recorded mortality.",
            ),
            f(
                "harvest_weight_grams",
                "number",
                "Optional",
                "Cumulative recorded harvest weight in grams.",
            ),
            f(
                "initial_abw",
                "number",
                "Optional; grams",
                "Average body weight from the baseline sample.",
            ),
            f(
                "initial_abl",
                "number",
                "Optional; centimeters",
                "Average body length from the baseline sample.",
            ),
            f(
                "final_abw",
                "number",
                "Optional; grams",
                "Final average body weight at harvest.",
            ),
            f(
                "final_abl",
                "number",
                "Optional; centimeters",
                "Final average body length at harvest.",
            ),
            f(
                "days_in_culture",
                "number",
                "Default: 0",
                "Calendar days since stocking, updated at midnight rather than as rolling 24-hour periods.",
            ),
            f(
                "sample_count",
                "number",
                "Default: 0",
                "Number of non-baseline sampling records.",
            ),
            f(
                "initial_total_weight",
                "number",
                "Optional; grams",
                "Total weight of the baseline sample.",
            ),
            f(
                "initial_total_length",
                "number",
                "Optional; centimeters",
                "Total length of the baseline sample.",
            ),
            f(
                "created_at",
                "timestamp",
                "Server timestamp",
                "Time the batch record was created.",
            ),
        ],
    },
    {
        "sub": "7.2 tanks/{tankId}/batches/{batchId}/sampling_records/{recordId}",
        "path": "tanks/{tankId}/batches/{batchId}/sampling_records/{recordId}",
        "description": "Baseline and weekly sample measurements used to monitor growth and estimate biomass without measuring every crayfish.",
        "fields": [
            f(
                "sampling_date",
                "timestamp",
                "Required",
                "Date the sample was collected.",
            ),
            f(
                "avg_body_weight",
                "number",
                "grams",
                "Average sample weight: total_weight divided by sample_size.",
            ),
            f(
                "avg_body_length",
                "number",
                "centimeters",
                "Average sample length: total_length divided by sample_size.",
            ),
            f(
                "sample_size",
                "number",
                "Positive integer",
                "Number of crayfish physically measured in the sample.",
            ),
            f(
                "total_weight",
                "number",
                "grams",
                "Combined weight of sampled crayfish.",
            ),
            f(
                "total_length",
                "number",
                "centimeters",
                "Combined measured length of sampled crayfish.",
            ),
            f(
                "biomass",
                "number",
                "Estimated grams",
                "Estimated tank biomass calculated from current counted population and average body weight.",
            ),
            f(
                "live_count",
                "number",
                "Counted population",
                "Current counted live population used in the biomass estimate.",
            ),
            f(
                "is_baseline",
                "boolean",
                "Default: false",
                "True for the Day 0 baseline; false for weekly samples.",
            ),
            f(
                "created_at",
                "timestamp",
                "Server timestamp",
                "Time the sampling record was created.",
            ),
        ],
        "note": "Weekly sampling begins seven calendar days after stocking and continues every seven days from the previous weekly sample. The baseline record is excluded from Week N counting.",
    },
    {
        "sub": "7.3 tanks/{tankId}/batches/{batchId}/mortality_records/{recordId}",
        "path": "tanks/{tankId}/batches/{batchId}/mortality_records/{recordId}",
        "description": "Records a discovered mortality event and updates the batch's counted current population.",
        "fields": [
            f(
                "mortality_date",
                "timestamp",
                "Required",
                "Date the dead crayfish were discovered or recorded.",
            ),
            f(
                "mortality_count",
                "number",
                "Positive integer",
                "Number of mortalities in the event.",
            ),
            f(
                "created_at",
                "timestamp",
                "Server timestamp",
                "Time the record was created.",
            ),
        ],
    },
    {
        "sub": "7.4 tanks/{tankId}/batches/{batchId}/harvest_records/{recordId}",
        "path": "tanks/{tankId}/batches/{batchId}/harvest_records/{recordId}",
        "description": "Records a partial or final harvest event.",
        "fields": [
            f(
                "batch_id",
                "string",
                "Required",
                "Parent batch identifier retained in the record.",
            ),
            f(
                "harvest_date",
                "timestamp",
                "Required",
                "Date the harvest was performed.",
            ),
            f(
                "harvest_count",
                "number",
                "Positive integer",
                "Number of crayfish harvested.",
            ),
            f("total_weight_kg", "number", "kilograms", "Combined harvest weight."),
            f("abw_grams", "number", "grams", "Average harvested body weight."),
            f(
                "created_at",
                "timestamp",
                "Server timestamp",
                "Time the record was created.",
            ),
        ],
    },
    {
        "section": "8. Notifications",
        "sub": "8.1 notifications/{notifId}",
        "path": "notifications/{notifId}",
        "description": "User notification inbox record. Deterministic IDs are used where duplicate backend events must collapse into one notification.",
        "fields": [
            f("uid", "string", "Required", "UID of the intended recipient."),
            f(
                "notif_type",
                "string",
                "critical | warning | reminder | device_auto | general",
                "Notification category used for grouping and preference checks.",
            ),
            f("title", "string", "Required", "Short notification heading."),
            f("body", "string", "Required", "Detailed notification message."),
            f(
                "is_read",
                "boolean",
                "Default: false",
                "Whether the user opened or marked the notification as read.",
            ),
            f(
                "created_at",
                "timestamp",
                "Server timestamp",
                "Time the notification record was created.",
            ),
        ],
        "note": "Completed and skipped-insufficient feeder logs create inbox records and immediate FCM pushes when the user's Feeding preference is enabled.",
    },
    {
        "section": "9. ESP32 Sensor-Ingestion Staging",
        "sub": "9.1 sensorIngestion/current",
        "path": "sensorIngestion/current",
        "description": "Five-second ESP32 staging snapshot. Cloud Functions validate its capture-time assignment before routing it to the active tank.",
        "fields": [
            f(
                "hardwareId",
                "string",
                "Required",
                "Stable identifier of the reporting hardware.",
            ),
            f(
                "source_tank_id",
                "string",
                "Required",
                "Tank bound to the hardware when the reading was captured.",
            ),
            f(
                "source_owner_uid",
                "string",
                "Required",
                "Owner bound to the hardware at capture time.",
            ),
            f(
                "source_assignment_at_ms",
                "number",
                "Epoch milliseconds",
                "Assignment identity used to reject stale or cross-owner payloads.",
            ),
            f(
                "captured_at_ms",
                "number",
                "Epoch milliseconds",
                "Original capture time when the device clock is trusted.",
            ),
            f(
                "temperature",
                "number",
                "Optional per validity",
                "Live temperature value.",
            ),
            f("ph_level", "number", "Optional per validity", "Live pH value."),
            f(
                "dissolved_oxygen",
                "number",
                "Optional per validity",
                "Live dissolved oxygen value.",
            ),
            f(
                "turbidity",
                "number",
                "Optional per validity",
                "Live water turbidity value.",
            ),
            f("turbidity_air", "number", "Optional", "Turbidity reference/air value."),
            f(
                "water_level",
                "number",
                "Optional per validity",
                "Live pond water-level value.",
            ),
            f(
                "feed_level",
                "number",
                "Optional per validity",
                "Live hopper percentage.",
            ),
            f("estimated_feed_grams", "number", "Optional", "Estimated hopper mass."),
            f(
                "buffered_entries",
                "number",
                "Default: 0",
                "Count of device readings waiting in the local buffer.",
            ),
        ],
    },
    {
        "sub": "9.2 sensorIngestion/current/history/{docId}",
        "path": "sensorIngestion/current/history/{docId}",
        "description": "Ten-minute ESP32 aggregate staging record. Matching assignments are routed to tank history; mismatched or unbound records remain quarantined.",
        "fields": [
            f(
                "hardwareId",
                "string",
                "Required",
                "Stable identifier of the reporting hardware.",
            ),
            f("source_tank_id", "string", "Required", "Tank bound at capture time."),
            f("source_owner_uid", "string", "Required", "Owner bound at capture time."),
            f(
                "source_assignment_at_ms",
                "number",
                "Epoch milliseconds",
                "Capture-time assignment identity.",
            ),
            f(
                "captured_at_ms",
                "number",
                "Epoch milliseconds",
                "Original aggregate completion time.",
            ),
            f(
                "sensor MIN/MAX/AVG fields",
                "number",
                "Only valid sensors included",
                "Ten-minute aggregates for temperature, pH, dissolved oxygen, turbidity, and water level; optional operational feed values may also be present.",
            ),
            f(
                "routing_status",
                "string",
                "Optional: quarantined",
                "Routing result when the payload cannot be safely assigned.",
            ),
            f(
                "routing_reason",
                "string",
                "Optional",
                "Reason the payload remains in staging.",
            ),
        ],
    },
]


def set_repeat_table_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    tbl_header = OxmlElement("w:tblHeader")
    tbl_header.set(qn("w:val"), "true")
    tr_pr.append(tbl_header)


def prevent_row_split(row):
    tr_pr = row._tr.get_or_add_trPr()
    cant_split = OxmlElement("w:cantSplit")
    cant_split.set(qn("w:val"), "true")
    tr_pr.append(cant_split)


def set_keep_with_next(paragraph, value=True):
    paragraph.paragraph_format.keep_with_next = value


def set_run_font(run, name="Arial", size=11, bold=None, color=None):
    run.font.name = name
    run._element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:ascii"), name)
    run._element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:hAnsi"), name)
    run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if color:
        run.font.color.rgb = RGBColor(*color)


def shade_cell(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_cell_margins(cell, top=75, start=85, bottom=75, end=85):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for margin, value in (
        ("top", top),
        ("start", start),
        ("bottom", bottom),
        ("end", end),
    ):
        node = tc_mar.find(qn(f"w:{margin}"))
        if node is None:
            node = OxmlElement(f"w:{margin}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_table_widths(table, widths_inches):
    table.autofit = False
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    total_twips = int(sum(widths_inches) * 1440)
    tbl_pr = table._tbl.tblPr
    tbl_w = tbl_pr.find(qn("w:tblW"))
    if tbl_w is None:
        tbl_w = OxmlElement("w:tblW")
        tbl_pr.append(tbl_w)
    tbl_w.set(qn("w:w"), str(total_twips))
    tbl_w.set(qn("w:type"), "dxa")
    grid = table._tbl.tblGrid
    for child in list(grid):
        grid.remove(child)
    for width in widths_inches:
        col = OxmlElement("w:gridCol")
        col.set(qn("w:w"), str(int(width * 1440)))
        grid.append(col)
    for row in table.rows:
        for idx, cell in enumerate(row.cells):
            twips = int(widths_inches[idx] * 1440)
            cell.width = Inches(widths_inches[idx])
            tc_pr = cell._tc.get_or_add_tcPr()
            tc_w = tc_pr.find(qn("w:tcW"))
            if tc_w is None:
                tc_w = OxmlElement("w:tcW")
                tc_pr.append(tc_w)
            tc_w.set(qn("w:w"), str(twips))
            tc_w.set(qn("w:type"), "dxa")
            set_cell_margins(cell)


def add_before(doc, anchor, kind="paragraph", **kwargs):
    if kind == "paragraph":
        obj = doc.add_paragraph()
    else:
        obj = doc.add_table(rows=kwargs.get("rows", 1), cols=kwargs.get("cols", 1))
    anchor.addprevious(obj._element)
    return obj


def add_text_paragraph(
    doc,
    anchor,
    text,
    *,
    bold=False,
    size=11,
    align=WD_ALIGN_PARAGRAPH.JUSTIFY,
    before=0,
    after=6,
    left=0,
    first_line=0,
    keep_next=False,
    color=None,
    page_break_before=False,
):
    p = add_before(doc, anchor)
    p.alignment = align
    pf = p.paragraph_format
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    pf.line_spacing = 1.15
    pf.left_indent = Inches(left)
    pf.first_line_indent = Inches(first_line)
    pf.page_break_before = page_break_before
    set_keep_with_next(p, keep_next)
    r = p.add_run(text)
    set_run_font(r, size=size, bold=bold, color=color)
    return p


def add_dictionary_table(doc, anchor, rows):
    table = add_before(doc, anchor, kind="table", rows=1, cols=4)
    table.style = "Table Grid"
    headers = ("Field Name", "Data Type", "Constraints / Default", "Description")
    for i, text in enumerate(headers):
        cell = table.rows[0].cells[i]
        cell.text = text
        shade_cell(cell, "D9EAD3")
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        for p in cell.paragraphs:
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            p.paragraph_format.space_after = Pt(0)
            for run in p.runs:
                set_run_font(run, size=8.5, bold=True)
    prevent_row_split(table.rows[0])
    for values in rows:
        row = table.add_row()
        prevent_row_split(row)
        cells = row.cells
        for i, value in enumerate(values):
            cells[i].text = str(value)
            cells[i].vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            for p in cells[i].paragraphs:
                p.alignment = WD_ALIGN_PARAGRAPH.LEFT
                p.paragraph_format.space_after = Pt(0)
                p.paragraph_format.line_spacing = 1.0
                for run in p.runs:
                    set_run_font(run, size=8.2, bold=(i == 0))
    set_table_widths(table, [1.25, 0.78, 1.45, 2.62])
    spacer = add_before(doc, anchor)
    spacer.paragraph_format.space_after = Pt(2)
    return table


def find_body_paragraph_element(doc, exact):
    for p in doc.paragraphs:
        if p.text.strip() == exact:
            return p._p
    raise RuntimeError(f"Paragraph not found: {exact}")


def main():
    BACKUP.parent.mkdir(parents=True, exist_ok=True)
    if not BACKUP.exists():
        shutil.copy2(DOCX, BACKUP)
    doc = Document(DOCX)
    start = find_body_paragraph_element(doc, "3.2.5\tData Dictionary")
    end = find_body_paragraph_element(doc, "3.3\tDEVELOPMENT METHODOLOGY")

    node = start.getnext()
    removed = 0
    while node is not None and node is not end:
        nxt = node.getnext()
        node.getparent().remove(node)
        node = nxt
        removed += 1

    intro = (
        "This section provides the authoritative field-level reference for the current CrayCare Cloud Firestore database. "
        "Firestore data is organized as collections, documents, and subcollections. Each table identifies the canonical path, "
        "field name, data type, constraints or default behavior, and operational purpose used by the Flutter application, "
        "Cloud Functions, and assigned ESP32 hardware."
    )
    add_text_paragraph(doc, end, intro, first_line=0.5, after=8)
    conventions = (
        "Data types follow Cloud Firestore conventions: string, number, boolean, timestamp, array, map, and null. "
        "Unless a field explicitly uses epoch milliseconds for ESP32 compatibility, date-time values are stored as Firestore "
        "Timestamp values or documented ISO-8601 strings. Canonical application fields use snake_case except where firmware "
        "compatibility requires an established camelCase field."
    )
    add_text_paragraph(doc, end, conventions, first_line=0.5, after=10)

    table_no = 10
    previous_section = None
    for item in COLLECTIONS:
        section = item.get("section")
        if section and section != previous_section:
            add_text_paragraph(
                doc,
                end,
                section,
                bold=True,
                size=11,
                align=WD_ALIGN_PARAGRAPH.LEFT,
                before=10,
                after=5,
                keep_next=True,
                page_break_before=(section == "2. Hardware Assignment"),
            )
            previous_section = section
        add_text_paragraph(
            doc,
            end,
            item["sub"],
            bold=True,
            size=10.5,
            align=WD_ALIGN_PARAGRAPH.LEFT,
            before=6,
            after=3,
            keep_next=True,
        )
        add_text_paragraph(
            doc,
            end,
            item["description"],
            size=10.5,
            first_line=0.35,
            after=5,
            keep_next=True,
        )
        add_text_paragraph(
            doc,
            end,
            f"Table 3.{table_no}",
            size=10.5,
            align=WD_ALIGN_PARAGRAPH.CENTER,
            before=3,
            after=2,
            keep_next=True,
        )
        add_text_paragraph(
            doc,
            end,
            f"Data Dictionary of Collection: {item['path']}",
            bold=True,
            size=10,
            align=WD_ALIGN_PARAGRAPH.CENTER,
            before=0,
            after=4,
            keep_next=True,
        )
        add_dictionary_table(doc, end, item["fields"])
        if item.get("note"):
            p = add_text_paragraph(
                doc,
                end,
                "Note: " + item["note"],
                size=9.5,
                align=WD_ALIGN_PARAGRAPH.JUSTIFY,
                before=2,
                after=7,
            )
            if p.runs:
                p.runs[0].bold = False
        table_no += 1

    doc.save(DOCX)
    print(f"Updated {DOCX}")
    print(f"Backup {BACKUP}")
    print(f"Removed {removed} old body elements")
    print(
        f"Inserted {len(COLLECTIONS)} collection dictionaries (Tables 3.10-3.{table_no - 1})"
    )


if __name__ == "__main__":
    main()
