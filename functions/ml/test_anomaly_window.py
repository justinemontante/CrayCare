import unittest
from unittest.mock import MagicMock, patch
from datetime import datetime, timezone

import pandas as pd

from anomaly_window import anomaly_window


class HistoryWindowTests(unittest.TestCase):
    NOW = 1800000000

    def frame(self, times):
        return pd.DataFrame({"timestamp": times, "temp_avg": [27.0] * len(times)})

    def test_fresh_regular_history_is_ready(self):
        frame = self.frame([self.NOW - i * 600 for i in range(20)])
        rows, status, source = anomaly_window(frame, self.NOW)
        self.assertEqual(status, "ready")
        self.assertEqual(len(rows), 13)
        self.assertEqual(source, self.NOW)

    def test_four_sensor_history_does_not_require_water_level(self):
        import main

        row = {
            "temp_avg": 27.0,
            "pH_avg": 7.2,
            "DO_avg": 6.0,
            "turbidity_avg": 15.0,
        }
        self.assertTrue(main._valid_history_row(row))
        self.assertFalse(main._valid_history_row(row, ["temp", "pH", "DO", "turbidity", "waterLevel"]))

    def test_eight_hour_old_readings_are_not_reassessed(self):
        frame = self.frame([self.NOW - 8 * 3600 - i * 600 for i in range(12)])
        rows, status, _ = anomaly_window(frame, self.NOW)
        self.assertEqual(status, "stale")
        self.assertTrue(rows.empty)

    def test_one_missed_ten_minute_reading_is_tolerated(self):
        # Twelve valid readings spanning thirteen expected ten-minute slots.
        slots = [0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12]
        frame = self.frame([self.NOW - i * 600 for i in reversed(slots)])
        rows, status, _ = anomaly_window(frame, self.NOW)
        self.assertEqual(status, "ready")
        self.assertEqual(len(rows), 12)

    def test_two_missed_readings_still_use_elapsed_time(self):
        slots = [0, 1, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13]
        frame = self.frame([self.NOW - i * 600 for i in reversed(slots)])
        _, status, _ = anomaly_window(frame, self.NOW)
        self.assertEqual(status, "ready")

    def test_irregular_thirteen_minute_history_becomes_ready(self):
        times = [self.NOW - i * 780 for i in range(10)]
        rows, status, _ = anomaly_window(self.frame(times), self.NOW)
        self.assertEqual(status, "ready")
        self.assertEqual(len(rows), 10)

    def test_six_readings_without_two_hour_coverage_are_insufficient(self):
        _, status, _ = anomaly_window(
            self.frame([self.NOW - i * 1200 for i in range(6)]), self.NOW
        )
        self.assertEqual(status, "insufficient")

    def test_long_outage_restarts_usable_suffix(self):
        slots = list(range(12)) + list(range(20, 32))
        frame = self.frame([self.NOW - i * 600 for i in reversed(slots)])
        rows, status, _ = anomaly_window(frame, self.NOW)
        self.assertEqual(status, "ready")
        self.assertEqual(len(rows), 12)

    def test_duplicates_do_not_make_six_readings(self):
        _, status, _ = anomaly_window(self.frame([self.NOW] * 12), self.NOW)
        self.assertEqual(status, "insufficient")

    def test_normal_jitter_across_bucket_boundaries_keeps_all_readings(self):
        times = [
            self.NOW - 3000 + 1,
            self.NOW - 2400 - 1,
            self.NOW - 1800 + 1,
            self.NOW - 1200 - 1,
            self.NOW - 600 + 1,
            self.NOW - 1,
        ]
        rows, status, _ = anomaly_window(self.frame(times), self.NOW)
        self.assertEqual(status, "insufficient")
        self.assertEqual(len(rows), 6)

    def test_future_and_invalid_timestamps_are_excluded(self):
        _, status, source = anomaly_window(
            self.frame([self.NOW + 600, float("nan")]), self.NOW
        )
        self.assertEqual(status, "insufficient")
        self.assertIsNone(source)

    def test_scheduled_job_does_not_run_model_on_stale_history_and_writes_one_history_record(self):
        import main

        now = datetime.now(timezone.utc).timestamp()
        frame = self.frame([now - 8 * 3600 - i * 600 for i in range(12)])
        db = MagicMock()
        tank = db.collection.return_value.document.return_value
        tank.get.return_value.to_dict.return_value = {"owner_uid": "test-owner"}
        with (
            patch.object(main, "_get_db", return_value=db),
            patch.object(main, "_fetch_sensor_history", return_value=frame),
            patch.object(main, "_run_water_quality_anomaly_detection") as run,
            patch.object(main, "_prune_history"),
        ):
            main._analyze_tank("test-only")
        run.assert_not_called()
        db.batch.assert_not_called()
        tank_ref = db.collection.return_value.document.return_value
        self.assertEqual(tank_ref.collection.call_count, 1)
        self.assertEqual(
            tank_ref.collection.call_args.args,
            ("water_quality_anomaly_detection_history",),
        )
        history_ref = tank_ref.collection.return_value
        self.assertEqual(history_ref.document.return_value.set.call_count, 1)
        result = history_ref.document.return_value.set.call_args.args[0]
        self.assertEqual(result["status"], "Insufficient")
        self.assertEqual(result["source"], "Stale sensor history")
        self.assertNotIn("data_status", result)
        self.assertIn("source_recorded_at", result)
        self.assertNotIn("source_age_seconds", result)
        self.assertNotIn("analysis_window_minutes", result)

    def test_history_write_uses_timestamp_document_and_only_one_firestore_write(self):
        import main

        db = MagicMock()
        now = datetime(2026, 10, 11, 3, 15, 0, tzinfo=timezone.utc)
        result = {"status": "Normal", "processed_at": now}

        detection_id = main._persist_history_result(db, "tank-123", now, result)

        self.assertEqual(detection_id, "20261011T031500")
        history = (
            db.collection.return_value.document.return_value.collection.return_value
        )
        db.collection.assert_called_once_with("tanks")
        db.collection.return_value.document.assert_called_once_with("tank-123")
        db.collection.return_value.document.return_value.collection.assert_called_once_with(
            "water_quality_anomaly_detection_history"
        )
        history.document.assert_called_once_with(detection_id)
        history.document.return_value.set.assert_called_once_with(result)
        db.batch.assert_not_called()

    def test_fresh_history_create_runs_once_for_active_assignment(self):
        import main

        now = datetime.now(timezone.utc)
        event = MagicMock()
        event.params = {"tank_id": "tank-123", "entry_id": "r_123"}
        event.data.to_dict.return_value = {
            "recorded_at": now,
            "source_tank_id": "tank-123",
            "source_owner_uid": "owner-1",
            "source_assignment_at_ms": 1700000000000,
        }
        assignment = {"tank_id": "tank-123", "assigned_at": datetime.fromtimestamp(1700000000, timezone.utc)}
        with (
            patch.object(main, "_active_assignment", return_value=("owner-1", assignment)),
            patch.object(main, "_analyze_tank") as analyze,
        ):
            main.run_wqad_analysis_on_sensor_record.__wrapped__(event)
        analyze.assert_called_once_with(
            "tank-123", source_id=f"{round(now.timestamp() * 1000):013d}_r_123", source_at=now.timestamp()
        )

    def test_offline_backfill_does_not_start_inference(self):
        import main

        event = MagicMock()
        event.params = {"tank_id": "tank-123", "entry_id": "old"}
        event.data.to_dict.return_value = {
            "recorded_at": datetime.now(timezone.utc).replace(year=2025),
        }
        with patch.object(main, "_active_assignment") as assignment:
            main.run_wqad_analysis_on_sensor_record.__wrapped__(event)
        assignment.assert_not_called()

    def test_staged_history_without_source_fields_uses_assignment_time(self):
        import main

        now = datetime.now(timezone.utc)
        event = MagicMock()
        event.params = {"tank_id": "tank-123", "entry_id": "staged"}
        event.data.to_dict.return_value = {"recorded_at": now}
        assignment = {
            "tank_id": "tank-123",
            "assigned_at": datetime.fromtimestamp(now.timestamp() - 3600, timezone.utc),
        }
        with (
            patch.object(main, "_active_assignment", return_value=("owner-1", assignment)),
            patch.object(main, "_analyze_tank") as analyze,
        ):
            main.run_wqad_analysis_on_sensor_record.__wrapped__(event)
        analyze.assert_called_once()

    def test_older_event_does_not_replace_newer_history(self):
        import main

        now = datetime.now(timezone.utc).timestamp()
        frame = self.frame([now - i * 600 for i in range(13)])
        db = MagicMock()
        with (
            patch.object(main, "_get_db", return_value=db),
            patch.object(main, "_fetch_sensor_history", return_value=frame),
            patch.object(main, "_run_water_quality_anomaly_detection") as run,
        ):
            main._analyze_tank("tank-123", "older-source", now - 600)
        run.assert_not_called()
        db.collection.return_value.document.return_value.collection.assert_not_called()

    def test_source_keyed_history_write_creates_only_one_document(self):
        import main

        db = MagicMock()
        result = {"status": "Normal"}
        source_id = "123_r_abc"
        saved = main._persist_history_result(
            db, "tank-123", datetime.now(timezone.utc), result, source_id
        )
        self.assertEqual(saved, source_id)
        doc = db.collection.return_value.document.return_value.collection.return_value.document.return_value
        doc.create.assert_called_once_with(result)
        doc.set.assert_not_called()
