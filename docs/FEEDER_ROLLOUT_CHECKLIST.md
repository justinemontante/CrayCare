# Feeder consistency fixes — rollout and hardware checks

These changes are source changes, not evidence of a production deployment or a hardware calibration.

## Rollout order

1. Coordinate flashing `esp32dev_main` with deploying `notifications:onSensorIngestionWrite` and `notifications:onSensorIngestionHistoryCreate`. The updated ingestion functions require capture-bound owner/tank/assignment metadata; old firmware payloads will not route. Preserve and review quarantined legacy staging records instead of guessing ownership. Verify new readings arrive in the correct tank before resuming operation.
2. Deploy `notifications:onFeederLogCreate` and `ml:run_hourly_wqad`, and install the updated Flutter app. The feeder trigger reconciles date-scoped outcomes even when notification preferences are disabled. A Flutter hot reload does not update firmware or cloud functions.
3. Review existing schedules with unsupported amounts (for example 25 g or 35 g). They are not automatically rewritten. The firmware blocks unsupported doses; the app accepts only 20–200 g in steps of 20 g. Confirm the nominal 20 g-per-cycle estimate with the actual feed and feeder before culture operation.

No Firestore rules/index changes are needed for this patch: device logs use the existing assigned-tank create permission; the Admin SDK reconciles schedule outcomes. The DBML and both Firestore schema documents describe the new fields. The `.dbdiagram` file stores only diagram layout and has no field definitions to migrate.

## Required bench tests (not replaced by a successful build)

- Use an empty test vessel, not a stocked pond, to verify 20/40/200 g cycle counts and actual dispensed mass; check motor-open timing during network loss.
- Reboot during a scheduled feed and during the same scheduled minute. Verify the motor does not replay the occurrence and interrupted execution produces `failed` rather than `completed`.
- With a 6:00 PM schedule, verify Feed Now asks for confirmation at 5:50 PM and 6:05 PM, is blocked from 5:59:00 PM through 6:00:59 PM, and never prevents the 6:00 PM automatic occurrence from running. Also queue a command before the hard window and delay its delivery into that window; the ESP32 must block it.
- Reboot after durable intent but before reservation/command deletion. Expect one interrupted outcome and no replay. Simulate an ambiguous command-deletion response; the outbox must retain the intent until acknowledgement succeeds or the command is absent.
- Leave a Feed Now command queued more than 60 seconds, including an app write held offline before server commit. Reconnect and verify no motor movement and a blocked/expired outcome. Check expiry again after a slow status upload.
- Check manual UI results for empty/insufficient/unsafe/expired requests. A prior or scheduled feed's completion must not finish another manual request; a timeout must say unconfirmed and must not create a false failure record.
- Disconnect the internet after a successful initial configuration sync. Run a scheduled feed, reconnect, and confirm exactly one original-timestamp log, the correct outcome, and estimated consumption.
- Unassign hardware while idle. After the next configuration poll, confirm cached schedules are cleared. Life-support relays intentionally hold their current state until replacement settings arrive; unassignment does not blindly turn off aeration.
- Assign another tank. Confirm old schedules and counters are not reused, and feeding stays blocked until all new sensor settings have synced. Queued logs for a previous tank remain on the device until that tank is assigned again or an authorized recovery workflow is provided.
- Buffer history under owner A, then assign owner B before upload. Verify history is quarantined in staging, not added to B's tank. Test same-owner reassignment too. Replay live events out of order and confirm latest never goes backwards.
- Add more than 20 schedules with distinct active times/days and verify every page reaches the ESP. Check repeated days, midnight boundaries, and date labels.
- Test normal, empty, insufficient and critical-but-sufficient hopper readings using a supported dose. A critical percentage alone must not block dispensing.
- Edit initial batch values before any operational records exist; verify batch, tank and Week 0 baseline agree in the growth report.
- Disconnect history long enough to exceed 20 minutes, then run the hourly assessment: expect stale/Insufficient, not a fresh Good/Moderate/Poor/Critical condition.
- Use six history readings spaced alternately 598/602 seconds: all six must remain eligible. Deduplication removes identical timestamps, not neighboring cadence buckets.
- Deliver the same feeder log event concurrently and retry it: one inbox and at most one push attempt; preserve `is_read`. Simulate a crash after claiming: inbox stays available, but push delivery is not guaranteed (FCM and Firestore cannot share one atomic transaction).

## Limits

Offline execution requires a previously confirmed assignment/configuration in the current boot. After reboot, the device waits for an initial full configuration sync instead of trusting another owner's or incomplete settings. A physically offline device cannot observe a remote unassignment until connectivity returns. Interrupted feeds are not automatically retried because the system has no scale that can prove whether part of the dose already dispensed.
