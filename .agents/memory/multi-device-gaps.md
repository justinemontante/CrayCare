---
name: Single-device isolation (current schema)
description: The system is designed around one physical ESP32 assigned to one owner through hardware_system/currentOwner
---

## Rule

CrayCare currently assumes one production ESP32 installation. Operational data
is scoped under `tanks/{tankId}/...`, while the active hardware assignment is
stored in `hardware_system/currentOwner`.

## Current access model

| Path | Access |
|---|---|
| `users/{uid}/...` | Self; admin for account management |
| `tanks/{tankId}` | Owner of that tank; admin for provisioning metadata |
| `tanks/{tankId}/sensor_readings/...` | Tank owner only; server writes canonical readings |
| `tanks/{tankId}/sensors/...` | Tank owner; assigned ESP read; admin may seed/create |
| `tanks/{tankId}/actuators/...` | Tank owner control-mode request; assigned ESP physical-state update |
| `tanks/{tankId}/water_quality_anomaly_detections/...` | Tank owner read; backend writes |
| `hardware_system/currentOwner` | Admin write; admin/ESP read |
| `sensorIngestion/...` | Authenticated ESP write; admin read/delete |
| `notifications/{id}` | Scoped by the document `uid` field |

The ESP session is currently recognized by Firebase password authentication for
`esp32@craycare.com`, and assigned-tank device operations additionally check
`hardware_system/currentOwner.tank_id`.

## Known limitation

`sensorIngestion/current` is a single fixed staging document and the current ESP
identity is a shared single-device credential. Adding multiple independent
hardware units requires per-device identities plus per-device ingestion/assignment
scoping; do not treat the current design as multi-device production architecture.
