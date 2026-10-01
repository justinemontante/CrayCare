import unittest
import subprocess
import sys
import tempfile
from pathlib import Path
import joblib
import numpy as np
import pandas as pd
from anomaly_features import build_anomaly_features
from training_data import prepare_history


class TrainingDataTests(unittest.TestCase):
    def sample(self, count=30):
        data = {'timestamp': pd.date_range('2026-08-01', periods=count, freq='10min', tz='UTC')}
        data['temperature'] = np.arange(count) * .01 + 3
        data['ph_level'] = np.arange(count) * .01 + 3
        data['dissolved_oxygen'] = np.arange(count) * .01 + 3
        data['turbidity'] = np.arange(count) * .01 + 3
        data['water_level'] = 18 - np.arange(count) * .001
        return pd.DataFrame(data)

    def test_unlabeled_and_time_units_match_inference(self):
        original = self.sample()
        rows, features = prepare_history(original)
        self.assertEqual(len(rows), 19)
        window = original.tail(12).copy()
        window['timestamp'] = window['timestamp'].map(lambda value: value.timestamp())
        np.testing.assert_allclose(features.iloc[-1], build_anomaly_features(window).iloc[-1], rtol=1e-7, atol=1e-7)
        for unit in ['ms', 'us', 'ns']:
            frame = original.copy()
            frame['timestamp'] = frame['timestamp'].astype(f'datetime64[{unit}, UTC]')
            _, converted = prepare_history(frame)
            np.testing.assert_allclose(features, converted)

    def test_gap_restarts_warmup(self):
        data = self.sample(40).drop(index=20)
        rows, _ = prepare_history(data)
        self.assertEqual(len(rows), 9 + 8)

    def test_future_changes_do_not_change_past_features(self):
        data = self.sample()
        _, before = prepare_history(data)
        data.loc[29, 'temperature'] = 999
        _, after = prepare_history(data)
        np.testing.assert_allclose(before.iloc[:-1], after.iloc[:-1])

    def test_invalid_aggregates_are_not_zero_filled(self):
        data = self.sample(40)
        data.loc[20, 'dissolved_oxygen'] = -1
        rows, _ = prepare_history(data)
        self.assertEqual(len(rows), 17)

    def test_water_level_uses_one_reading_without_min_max(self):
        data = self.sample(30)
        self.assertNotIn('waterLevel_min', data)
        self.assertNotIn('waterLevel_max', data)
        rows, features = prepare_history(data)
        self.assertEqual(len(rows), 19)
        self.assertIn('waterLevel_avg', features)
        self.assertNotIn('waterLevel_spread', features)

    def test_water_level_must_be_finite_and_nonnegative(self):
        data = self.sample(30)
        data.loc[20, 'water_level'] = -1
        rows, _ = prepare_history(data)
        self.assertEqual(len(rows), 9)

    def test_legacy_history_aliases_remain_readable(self):
        data = self.sample(30).rename(columns={
            'temperature': 'temp_avg',
            'ph_level': 'pH_avg',
            'dissolved_oxygen': 'DO_avg',
            'turbidity': 'turbidity_avg',
            'water_level': 'waterLevel',
        })
        rows, _ = prepare_history(data)
        self.assertEqual(len(rows), 19)

    def test_unlabeled_training_cli(self):
        with tempfile.TemporaryDirectory() as directory:
            dataset = Path(directory) / 'history.csv'
            output = Path(directory) / 'candidate.joblib'
            self.sample(300).to_csv(dataset, index=False)
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('train_model.py')),
                '--dataset', str(dataset), '--output', str(output), '--train-days', '1',
                '--origin', 'synthetic_bootstrap_not_field_validated'], capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            bundle = joblib.load(output)
            self.assertFalse(bundle['training_labels_used'])
            self.assertEqual(bundle['evaluation_label_origin'], 'none')
            self.assertIsNone(bundle['prototype_metrics']['precision'])


if __name__ == '__main__':
    unittest.main()
