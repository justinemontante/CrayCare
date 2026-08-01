---
name: Multi-device isolation gaps
description: Known Firestore collections that lack per-uid isolation; safe for same-account multi-device but not multi-tenant
---

## Rule
Do not assume ALL collections are uid-isolated — several are intentionally global (single hardware device assumption).

**Why:** CrayCare is designed around one physical ESP32 device assigned to one farmer. Some collections are global by design. Others are global by omission and should be fixed if multi-tenant is needed.

## Collections WITHOUT uid filtering (known gaps)

| Collection | Reason global | Risk |
|---|---|---|
| `healthRisk/latest` | Single device → single result | Different accounts see same ML result |
| `feederSchedules` | No uid field | Any user can overwrite schedules |
| `feederStatus/status` | Singleton doc | Last-write-wins across users |
| `feederCommands` | No uid field | Any user can send feeder commands |
| `feederDispatched/{date}` | No uid field | Shared dispatch log |
| `deviceModes/{deviceId}` | Keyed by deviceId not uid | Shared if device not reassigned |
| `config/default` | Mirrored from user write | Last user to save settings sets ESP32 defaults |

## Collections WITH proper uid isolation

| Collection | Method |
|---|---|
| `users/{uid}` | Path |
| `users/{uid}/batches/...` | Path |
| `notifPrefs/{uid}` | Path |
| `config/{uid}` | Path |
| `sensorReadings` | `ownerUid` field stamped by Cloud Function |
| `notifications`, `notifMarkers` | `uid` field on each doc |
| `batches`, `sampling`, `mortality`, etc. (old flat) | `uid` field on each doc |

## Same-account multi-device behavior
- **Safe:** Firebase Auth gives the same uid on all devices → uid-filtered queries return the same data → real-time Firestore listeners sync automatically across devices
- **Risk:** Concurrent writes to `feederSchedules` or `config/default` from two devices → last write wins

## How to apply
- Do not add new global collections without uid scoping unless it's intentionally shared hardware state
- If multi-tenant support is added later: scope `feederSchedules`, `feederStatus`, `feederCommands` under `users/{uid}/feeder/...`
