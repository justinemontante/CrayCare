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
        for sensor in SENSORS:
            for stat, offset in [('min', 0), ('avg', 1), ('max', 2)]:
                data[f'{sensor}_{stat}'] = np.arange(count) * .01 + offset + 2
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
        data.loc[29, 'temp_max'] = 999
        _, after = prepare_history(data)
        np.testing.assert_allclose(before.iloc[:-1], after.iloc[:-1])

    def test_invalid_aggregates_are_not_zero_filled(self):
        data = self.sample(40)
        data.loc[20, 'DO_min'] = -1
        rows, _ = prepare_history(data)
        self.assertEqual(len(rows), 17)

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
