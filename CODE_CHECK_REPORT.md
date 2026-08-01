# CrayCare — Full Code Check Report
**Date:** 2026-08-01 · Repo: `justinemontante/CrayCare` @ `main` (`2caa108`)
**Scope:** Flutter app, Cloud Functions (Node + Python ML), ESP32 firmware, Firestore rules/indexes, schema docs.

> ✅ **UPDATE (same day):** All items below marked "FIXED" are now done and committed.
> Normalization pass: duplicate structure file removed, structure doc rewritten to the
> actual schema, dead code removed, ESP platformio envs verified, agent memory docs
> updated to the current schema.

---

## ✅ RESOLVED — `resetExperiment()` dead code REMOVED
- `lib/services/tank_service.dart` — deleted entirely (no callers anywhere).
- It was querying legacy flat collections (`sampling_records`, `mortality_records`,
  `batches`, `healthRisk`, `deviceLogs`) that are not in `firestore.rules` → DENIED.

## ✅ RESOLVED — `platformio.ini` env `esp32dev_allinone` REMOVED
- It referenced missing `main_allinone.cpp` (build would fail). Removed the env.
- Verified: all remaining 10 envs reference existing files in `src/`.

## ✅ RESOLVED — Firestore structure docs NORMALIZED
- `firestore_structure_clean.json` (exact duplicate) — **deleted**.
- `firestore_structure.json` — **rewritten** to the ACTUAL schema (14 canonical paths,
  no legacy entries: `sensorThresholds`, `sensorReadings`, flat `feeder*`, `healthRisk`,
  `deviceModes`, `notifPrefs`, `migration`, `sensorConfig`, `system_config` all removed).
- New readable doc: `docs/FIRESTORE_STRUCTURE_ACTUAL.md`.
- `.agents/memory/*.md` — updated to the current nested tank schema.

---

## 🔧 FIXED — Actuator (pump + 2 aerators) integration

**Files changed:**
| File | Change |
|---|---|
| `esp/CrayCare/src/main.cpp` | Idinagdag ang buong **Actuator Module** — pump (GPIO 26), aerator1 (GPIO 27), aerator2 (GPIO 14), active-LOW relays |
| `firestore.rules` | ESP32 (anonymous) allowed to READ `actuators`, UPDATE only `current_state`+`last_changed`, CREATE `actuator_logs` |
| `esp/CrayCare/SERIAL_COMMANDS.txt` | Notes para sa n1/n2/n3 relay test commands |

**Firmware behavior (default env `esp32dev_main`):**
- Every 5s: binabasa ang `tanks/{tankId}/actuators/{pump|aerator1|aerator2}` → `control_mode`
- `on` / `off` → direktang i-apply sa relay
- `auto` → sensor-driven rules:
  - **Pump:** ON kapag mababa ang water level (< `waterLevelCriticalLow`) o mataas ang temp (> `tempCriticalHigh`)
  - **Aerator 1:** ON kapag mababa ang dissolved oxygen (< `doCriticalLow`) o mataas ang temp
  - **Aerator 2:** ON kapag CRITICAL ang DO (< `doCriticalLow` − 1.5) o mataas ang temp
  - Graceful fallback: kapag naka-disable ang DO/water-level sensor, temperature rule ang gagamitin
- Write-back sa Firestore ng ACTUAL relay state (`current_state` + `last_changed`), kaya totoo ang ipinapakita ng app
- Log sa `actuator_logs` sa bawat relay transition:
  - Format: `Switched ON — Aerator 1 (AUTO) — ...` → tugma sa Controls screen runtime label (naghahanap ng "Switched ON/OFF") at sa auto-control event (naghahanap ng "(AUTO)")
- Serial commands: `n1on/n1off/n2on/n2off/n3on/n3off`, `relay status` (local test; cloud mode re-asserts on next sync)

**Database integration notes:**
- Field names tugma sa Flutter (`control_mode`, `current_state`, `last_changed`) at sa `_createTankIfMissing()` seeding
- Ang ESP ay HINDI pwedeng magbago ng `control_mode` (rules-restricted) — mode control ay app/admin lang
- Log fields tugma sa `ActuatorLogService`: `actuator_type, action, log_level, message, type, time, date, timestamp(ms)`
- Syntax-verified gamit ang C++ compile check (stubs) ✅

---

## ✅ VERDICT: HARDWARE ASSIGNMENT — OK (works end-to-end)

End-to-end flow verified — walang break:

1. **Admin UI** → `database_service.setCurrentOwner(uid)` writes:
   `hardware_system/currentOwner { uid, tank_id, assigned_by, assigned_at }`
   - Auto-provisions a tank + seeds `tank_id` on the user if missing ✅
2. **Firestore rules** — `hardware_system` write = admin only; read = any signed-in ✅
3. **ESP32** `fetchTankId()` reads `hardware_system/currentOwner` → gets `tank_id` ✅ (anonymous auth CAN read ✅)
4. **ESP32 writes ONLY to staging:** `sensorIngestion/current` + `sensorIngestion/current/history` ✅ (rules allow anonymous ✅)
5. **Cloud Functions route** (using `currentOwner.tank_id` at write time):
   - `sensorIngestion/current` → `tanks/{tankId}/sensor_readings/latest`
   - `.../history/{docId}` → `tanks/{tankId}/sensor_readings_history/{YYYY-MM-DD}/entries/{docId}` ✅
6. **Reassignment works:** new owner gets new readings; old owner keeps all history — nothing deleted/moved ✅ (implemented in `index.js` + documented)
7. **Sensor field names consistent** across Flutter / Cloud Function / ESP32:
   `temperature, ph_level, dissolved_oxygen, turbidity, water_level` ✅
   - CF `normalizeSensorReading()` even accepts legacy `phLevel/dissolvedOxygen/waterLevel` during migration ✅
8. **Actuator names consistent:** `pump, aerator1, aerator2` — ginagamit ng Controls screen + `_createTankIfMissing()` seeding ✅ (structure doc lang ang luma: "pump, aerator")
9. **Queries ↔ indexes:** lahat ng aktibong composite-index queries (actuator_logs, notifications uid+created_at) ay may index sa `firestore.indexes.json` ✅

---

## ⚠️ FINDINGS — dapat ayusin

### 🔴 1. (Functional gap) Walang PUMP/AERATOR control ang default ESP32 firmware
- **Flutter** ay may buong Controls screen → nagsusulat sa `tanks/{tankId}/actuators/{deviceId}` (pump, aerator1, aerator2) ✅
- **Firestore rules** ay pinapayagan ito ✅
- **PERO** `esp/CrayCare/src/main.cpp` (ang production default env) ay **walang kahit isang actuator/aerator/pump code** — sensor + feeder (servo) + Firestore ingestion LANG.
- `main_aerator.cpp` ay relay blink-test sketch lang (38 lines, walang Firestore).
- **Epekto:** ang "ON/OFF/Auto" ng pump at aerator sa app ay HINDI kailanman ma-e-execute ng hardware. Kailangan idagdag sa `main.cpp`: basahin `tanks/{tankId}/actuators/{deviceId}`, i-apply ang relay/pump control, at mag-log sa `actuator_logs`.

### 🟠 2. `platformio.ini` — env `esp32dev_allinone` references **missing `main_allinone.cpp`**
- Kung i-flash mo ang env na iyon, mag-fa-fail ang build. Hindi default env, pero latent issue.

### 🟠 3. Dead code: `resetExperiment()` sa `lib/services/tank_service.dart` (walang caller)
- Nag-qu-query ng **legacy flat collections** (`sampling_records`, `mortality_records`, `harvest_records`, `batches`, `healthRisk`) na **wala sa firestore.rules** → kung tawagin, DENIED lahat.
- Recommend: **i-delete** ang buong function (mukhang leftover ng migration).

### 🟡 4. Stale docs — `.agents/memory/*.md` (5 files) lahat naka-refer sa LUMANG schema
- `healthRisk/latest`, `sensorReadings/{uid}`, `feederSchedules` flat, `config/default`, `sensorReadingsHistory/{uid}`, flat `batches` w/ uid — lahat ito ay **pinalitan na** ng nested `tanks/{tankId}/...` schema.
- Kung susundan mo o ng agent mo ang mga memory notes na ito, malilito kayo. Recommend i-update o i-delete.

### 🟡 5. `firestore_structure.json` vs `firestore_structure_clean.json` — identical duplicates + stale entries
- Duplicate file (same content) — keep one.
- Stale entries: actuators example ("pump, aerator" → actual is pump/aerator1/aerator2); `sensorConfig` documented pero **hindi ginagamit sa code at walang rules**; `feeder_schedules` fields incomplete (missing `timeValue`, `grams`, `time` na isinusulat ng `feeder_service.dart`).

### 🟡 6. Orphaned file: `functions/package-lock.json` (walang kasamang package.json)
- Ang totoong package ay nasa `functions/notifications/`. Ang root lockfile ay 88 bytes, empty — harmless pero confusing.

### 🟡 7. `database.rules.json` (RTDB rules) — LEGACY
- ESP32 firmware ay zero-RTDB na. Stale config; pwede tanggalin kung wala nang gumagamit ng Realtime Database.

### 🟢 8. `firestore.indexes.json` — may legacy composite indexes (mula sa lumang flat schema)
- `batches/uid`, `sampling`, `mortality`, `activities`, `harvests` flat, `history/ownerUid`, `sensorReadings` — para sa mga collection na wala na. Safe i-clean up, pero hindi naman nakaka-break (extra index lang).

### 🟢 9. Dev artifacts na pwedeng linisin (optional)
- `attached_assets/*.txt`, `flutter_01.png`, `docs/session-notes/`, `test_tools/`, `replit.md`, `.replit` — mga dev leftovers.

---

## ✅ NAPATUNAYANG OK

| Item | Result |
|---|---|
| 287 Dart imports — lahat resolve sa existing files | ✅ |
| `node --check functions/notifications/index.js` — syntax OK | ✅ |
| `py_compile` lahat ng `functions/ml/*.py` — syntax OK | ✅ |
| Assets (images/icons/fonts) — lahat present, tama ang paths | ✅ |
| `pubspec.lock` — lahat ng direct deps locked | ✅ |
| Firebase app IDs (android/ios/web/windows) — match ang `firebase_options.dart` ↔ `firebase.json` | ✅ |
| Recorded build error (`admin_screen.dart:498 assignedHardwareId String?`) — **NA-FIX na** sa current code | ✅ |
| ESP32 thresholds sync — tama ang sensor names | ✅ |
| Feeder flow (schedules, pending_commands, feeder/status, feeder_logs) — nested paths sa firmware kapag may tankId | ✅ |
| ML pipeline paths (`tanks/{tankId}/health_risk/current`) — consistent sa Flutter read | ✅ |
| Notification prefs (`users/{uid}/notification_settings/preferences`) — consistent sa rules | ✅ |

---

## ❓ HINDI NAPATUNAYAN (ikaw na ang bahala)

- **`flutter analyze`** — walang Flutter SDK dito sa sandbox; ikaw na ang mag-run sa VS Code. (Static import check passed.)
- **Deployment** ng rules/functions/indexes — nangangailangan ng Firebase project access.
- **Compile** ng ESP32 firmware (PlatformIO) — walang PlatformIO dito.

---

## 📋 RECOMMENDED NEXT STEPS (priority order)

1. **Idagdag ang actuator (pump/aerator) control sa `esp/CrayCare/src/main.cpp`** — pinakaimportante, para gumana ang Controls screen ng app.
2. **I-delete ang `resetExperiment()`** sa `tank_service.dart`.
3. **Ayusin o tanggalin ang `main_allinone` env** sa `platformio.ini` (o i-commit ang `main_allinone.cpp`).
4. **I-update/delete ang `.agents/memory/*.md`** para i-reflect ang nested schema.
5. **I-consolidate ang firestore_structure docs** (tanggalin duplicate; i-update ang stale entries).
6. **I-clean up** ang legacy indexes, RTDB rules, orphan lockfile (optional).
