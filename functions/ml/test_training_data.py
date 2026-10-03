import unittest
import subprocess
import sys
import tempfile
from pathlib import Path
import joblib
import numpy as np
import pandas as pd
from anomaly_features import SENSORS, build_anomaly_features
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
        np.testing.assert_allclose(features.iloc[-1], build_anomaly_features(window, sensors=SENSORS).iloc[-1], rtol=1e-7, atol=1e-7)
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

    def test_water_level_is_ignored_by_wqad(self):
        data = self.sample(30)
        rows, features = prepare_history(data)
        self.assertEqual(len(rows), 19)
        self.assertFalse(any('waterLevel' in name for name in features.columns))

    def test_water_level_does_not_affect_sensor_validity(self):
        data = self.sample(30)
        data.loc[20, 'water_level'] = -1
        rows, _ = prepare_history(data)
        self.assertEqual(len(rows), 19)

    def test_canonical_four_sensor_aliases_remain_readable(self):
        data = self.sample(30).rename(columns={
            'temperature': 'temp_avg',
            'ph_level': 'pH_avg',
            'dissolved_oxygen': 'DO_avg',
            'turbidity': 'turbidity_avg',
        })
        rows, _ = prepare_history(data)
        self.assertEqual(len(rows), 19)

    def test_v2_gap_tolerance_matches_live_window_rules(self):
        data = self.sample(40).drop(index=20)
        rows, features = prepare_history(data, version=2)
        self.assertEqual(len(rows), 28)
        window = data.tail(12).copy()
        window['timestamp'] = window['timestamp'].map(lambda value: value.timestamp())
        expected = build_anomaly_features(window, sensors=SENSORS, version=2).iloc[-1]
        np.testing.assert_allclose(features.iloc[-1], expected, rtol=1e-7, atol=1e-7)

    def test_four_sensor_history_does_not_require_water_level(self):
        data = self.sample(30).drop(columns=['water_level'])
        rows, features = prepare_history(data, sensors=['temp', 'pH', 'DO', 'turbidity'])
        self.assertEqual(len(rows), 19)
        self.assertIn('turbidity_avg', features)
        self.assertFalse(any('waterLevel' in name for name in features.columns))

    def test_fishpond_proxy_origin_and_four_sensor_candidate_train_without_labels(self):
        with tempfile.TemporaryDirectory() as directory:
            dataset = Path(directory) / 'history.csv'
            output = Path(directory) / 'candidate.joblib'
            self.sample(900).drop(columns=['water_level']).assign(**{'class': ['Normal'] * 900}).to_csv(dataset, index=False)
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('train_model.py')),
                '--dataset', str(dataset), '--output', str(output), '--train-days', '3',
                '--sensors', 'temp,pH,DO,turbidity',
                '--origin', 'external_freshwater_fishpond_proxy_unvalidated'],
                capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            bundle = joblib.load(output)
            self.assertEqual(bundle['sensors'], SENSORS)
            self.assertEqual(bundle['sensors'], ['temp', 'pH', 'DO', 'turbidity'])
            self.assertFalse(bundle['training_labels_used'])
            self.assertEqual(bundle['evaluation_label_origin'], 'none')
            self.assertIsNone(bundle['prototype_metrics']['precision'])

    def test_unlabeled_training_cli(self):
        with tempfile.TemporaryDirectory() as directory:
            dataset = Path(directory) / 'history.csv'
            output = Path(directory) / 'candidate.joblib'
            self.sample(900).to_csv(dataset, index=False)
            result = subprocess.run([sys.executable, str(Path(__file__).with_name('train_model.py')),
                '--dataset', str(dataset), '--output', str(output), '--train-days', '3',
                '--origin', 'synthetic_bootstrap_not_field_validated'], capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            bundle = joblib.load(output)
            self.assertFalse(bundle['training_labels_used'])
            self.assertEqual(bundle['evaluation_label_origin'], 'none')
            self.assertIsNone(bundle['prototype_metrics']['precision'])


if __name__ == '__main__':
    unittest.main()
