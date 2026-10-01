# CrayCare sensor visualization test

This tool sends synthetic readings to the **assigned live Firestore tank** so
the signed-in CrayCare app can display them. Check that
`hardware_system/currentOwner` points to the test tank before starting. The
tool fails rather than guessing another tank when that assignment is missing.

## Live sensor preview

From this folder, run `npm run demo`. It updates only
`tanks/{tankId}/sensor_readings/latest` every five seconds. Open the app and
view Dashboard or Analytics > Live. Stop the generator with Ctrl+C. To send
just one reading, use `npm run demo:once`.

History writes are off by default. Use `npm run demo:history` only when you
intentionally want each ten-minute synthetic history record saved in the live
tank. This can affect historical Analytics and reports.

## WQAD / ML integration test

For a fast WQAD warm-up, run `npm run ml:seed`. It adds twelve synthetic,
ten-minute history records with varied sensor readings to the assigned tank in
one operation, after checking the hardware assignment and tank ownership. Each
run replaces recent `ml_test_` records and `r_` records explicitly marked with
`hardwareId: MOCK_TEST_TOOL`, then generates fresh small variations; it never
deletes real sensor-history entries.
New seed document IDs use the ESP32-style `r_<captured_at_ms>` format and carry
the same timestamp and assignment metadata fields, while retaining the mock
hardware marker so test data stays identifiable.
The demo data has a gradual turbidity rise near the end and is meant to exercise
the anomaly display, not represent real farm measurements. It writes history
only, not `sensor_readings/latest`, so dashboard live tiles are unchanged. The
deployed WQAD schedule runs every 30 minutes and will process the readings on
its next run. To analyze immediately,
run `npm run ml:run-now`; it calls the same WQAD owner/tank checks and inference
as the scheduled function, then writes the current detection and one detection
history record. Use `npm run ml:check` afterward to read the current result.
These actions write to the assigned live tank and may affect the app's ML card
and anomaly history.

For a continuing sensor visualization, run `npm run ml:demo` instead. It
updates the live reading every five seconds and appends one history row every
ten minutes; allow at least 110 minutes for twelve continuous records, then
wait for the next 30-minute WQAD run. Stop it with Ctrl+C.

This does not retrain or validate the model. For an offline prototype
prediction using the bundled synthetic CSV, use the Python workflow documented
in `functions/ml/README.md` instead.

## Read recent sensor history (read-only)

Run `npm run sensors:recent` to print up to the latest 24 readings from the
assigned tank, including their timestamps, sensor values, and gaps between
records. The final ML window check reports whether the latest readings contain
twelve continuous ten-minute records and whether the newest record is fresh.
This command only reads Firestore; it does not write or delete data.

## Stored sensor shape

- Live readings use one scalar each for `water_level` (cm) and `feed_level` (%).
- History readings also store one scalar each: `water_level` and `feed_level`.
- Neither water-level nor feed-level threshold documents are written by this
  tool. Their configured fields remain `low_value` and `critical_value` only.
- Water-quality sensor history keeps its existing min/max/average fields.
- `--config` is disabled to prevent this tool from changing thresholds.
- The full multi-range backfill is blocked unless explicitly confirmed; it can
  add about 5,475 synthetic history records. To proceed deliberately, run
  `npm run backfill:confirm`.

Synthetic data replaces the current `sensor_readings/latest` values while the
test runs. A connected ESP32 may overwrite them with its next real reading.
