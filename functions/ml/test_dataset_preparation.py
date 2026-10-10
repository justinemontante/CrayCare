import unittest

import pandas as pd

from dataset_preparation import prepare_dataset


class DatasetPreparationTests(unittest.TestCase):
    def test_stations_are_preserved_and_invalid_rows_are_removed(self):
        source = pd.DataFrame({
            'station': ['Station1', 'Station1', 'Station2'],
            'Date': ['01-02-2022'] * 3,
            'Time': ['08:00:00', '08:20:00', '08:00:00'],
            'TEMP': [25, 26, 27], 'PH': [7, '#VALUE!', 8],
            'DO': [6, 7, 8], 'TURBIDITY': [20, 21, 22],
        })
        prepared = prepare_dataset(source)
        self.assertEqual(len(prepared), 2)
        self.assertEqual(set(prepared.series_id), {'station1', 'station2'})
        self.assertEqual(list(prepared.columns), [
            'series_id', 'timestamp', 'temperature', 'ph_level',
            'dissolved_oxygen', 'turbidity',
        ])


if __name__ == '__main__':
    unittest.main()
