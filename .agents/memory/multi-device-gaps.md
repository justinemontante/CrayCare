---
name: Multi-device isolation (current schema)
description: The system is designed around ONE physical ESP32 assigned to one farmer via hardware_system/currentOwner
---

## Rule
Do not assume ALL collections are uid-isolated — several are intentionally global
(single hardware device assumption).

**Why:** CrayCare is designed around one physical ESP32 device assigned to one
farmer through `hardware_system/currentOwner`. All real-time data lives under
`tanks/{tankId}/...`, so two users never share a tank.

## Data isolation by design (current schema)
| Path | Who can access |
|---|---|
| `users/{uid}/...` | Self/admin |
| `tanks/{tankId}/...` | Owner (tank_id match) / admin / anonymous ESP32 (limited) |
| `hardware_system/currentOwner` | Read: signed-in; write: admin |
| `notifications/{id}` | Scoped by `uid` field |
| `sensorIngestion/...` | ESP write; admin read/delete |
| `mlPredictions/{id}` | Any signed-in read; admin write |

## Known limitation
- `sensorIngestion/current` is a single fixed doc for the one ESP32. If a second
  hardware unit is ever added, it needs its own ingestion path — do NOT assume
  multi-tenant out of the box.

## How to apply
- Do not add new global collections without scoping under `users/{uid}` or
  `tanks/{tankId}` unless it is intentionally shared hardware state.
- Reference: `docs/FIRESTORE_STRUCTURE_ACTUAL.md` (updated 2026-08-01).
