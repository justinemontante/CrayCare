import unittest
from unittest.mock import MagicMock, patch
from datetime import datetime, timezone

import pandas as pd

from anomaly_window import anomaly_window


class HistoryWindowTests(unittest.TestCase):
    NOW = 1800000000

    def frame(self, times):
        return pd.DataFrame({'timestamp': times, 'temp_avg': [27.0] * len(times)})

    def test_fresh_regular_history_is_ready(self):
        frame = self.frame([self.NOW - i * 600 for i in range(20)])
        rows, status, source = anomaly_window(frame, self.NOW)
        self.assertEqual(status, 'ready')
        self.assertEqual(len(rows), 12)
        self.assertEqual(source, self.NOW)

    def test_eight_hour_old_readings_are_not_reassessed(self):
        frame = self.frame([self.NOW - 8 * 3600 - i * 600 for i in range(12)])
        rows, status, _ = anomaly_window(frame, self.NOW)
        self.assertEqual(status, 'stale')
        self.assertTrue(rows.empty)

    def test_gap_requires_new_contiguous_history(self):
        frame = self.frame([self.NOW - i * 600 for i in [0, 1, 2, 8, 9, 10]])
        rows, status, _ = anomaly_window(frame, self.NOW)
        self.assertEqual(status, 'insufficient')
        self.assertEqual(len(rows), 3)

    def test_duplicates_do_not_make_six_readings(self):
        _, status, _ = anomaly_window(self.frame([self.NOW] * 12), self.NOW)
        self.assertEqual(status, 'insufficient')

    def test_normal_jitter_across_bucket_boundaries_keeps_all_readings(self):
        times = [self.NOW - 3000 + 1, self.NOW - 2400 - 1,
                 self.NOW - 1800 + 1, self.NOW - 1200 - 1,
                 self.NOW - 600 + 1, self.NOW - 1]
        rows, status, _ = anomaly_window(self.frame(times), self.NOW)
        self.assertEqual(status, 'insufficient')
        self.assertEqual(len(rows), 6)

    def test_future_and_invalid_timestamps_are_excluded(self):
        _, status, source = anomaly_window(self.frame([self.NOW + 600, float('nan')]), self.NOW)
        self.assertEqual(status, 'insufficient')
        self.assertIsNone(source)

    def test_hourly_job_does_not_run_model_on_stale_history(self):
        import main
        now = datetime.now(timezone.utc).timestamp()
        frame = self.frame([now - 8 * 3600 - i * 600 for i in range(12)])
        db = MagicMock()
        tank = db.collection.return_value.document.return_value
        tank.get.return_value.to_dict.return_value = {'owner_uid': 'test-owner'}
        with patch.object(main, '_get_db', return_value=db), \
                patch.object(main, '_fetch_sensor_history', return_value=frame), \
                patch.object(main, '_run_water_quality_anomaly_detection') as run:
            main._analyze_tank('test-only')
        run.assert_not_called()
        result = tank.collection.return_value.document.return_value.set.call_args.args[0]
        self.assertEqual(result['status'], 'Insufficient')
        self.assertEqual(result['data_status'], 'stale')
        self.assertGreater(result['source_age_seconds'], 7 * 3600)
