import tempfile
import unittest
from pathlib import Path

import pandas as pd

from prepare_fishpond_candidate import prepare_dataset


class FishpondCandidatePreparationTests(unittest.TestCase):
    def test_keeps_four_sensors_and_averages_complete_pairs(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.csv"
            timestamps = pd.date_range("2026-01-01", periods=6, freq="5min")
            pd.DataFrame({
                "timestamp": timestamps,
                "temp_C": [20, 22, 24, 26, 28, 30],
                "pH": [6, 8, 6, 8, 6, 8],
                "do_mgL": [4, 6, 4, 6, 4, 6],
                "turbidity_NTU": [10, 20, 30, 40, 50, 60],
                "ec_uScm": [1] * 6,
                "tds_mgL": [2] * 6,
                "orp_mV": [3] * 6,
                "class": ["Normal", "Severe"] * 3,
            }).to_csv(source, index=False)

            prepared = prepare_dataset(source)

        self.assertEqual(list(prepared.columns), [
            "timestamp", "temperature", "ph_level", "dissolved_oxygen", "turbidity"
        ])
        self.assertEqual(len(prepared), 3)
        self.assertEqual(prepared.loc[0, "temperature"], 21)
        self.assertEqual(prepared.loc[0, "ph_level"], 7)
        self.assertEqual(prepared.loc[0, "dissolved_oxygen"], 5)
        self.assertEqual(prepared.loc[0, "turbidity"], 15)
        self.assertTrue(prepared["timestamp"].diff().dropna().eq(pd.Timedelta(minutes=10)).all())

    def test_discards_incomplete_ten_minute_bucket(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.csv"
            pd.DataFrame({
                "timestamp": ["2026-01-01 00:00:00", "2026-01-01 00:05:00", "2026-01-01 00:10:00"],
                "temp_C": [20, 22, 24], "pH": [7, 7, 7], "do_mgL": [5, 5, 5],
                "turbidity_NTU": [10, 10, 10],
            }).to_csv(source, index=False)

            prepared = prepare_dataset(source)

        self.assertEqual(len(prepared), 1)
        self.assertEqual(prepared.iloc[0]["temperature"], 21)


if __name__ == "__main__":
    unittest.main()
