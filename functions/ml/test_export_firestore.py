import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock

from export_firestore import export_tank_history


class ExportFirestoreTests(unittest.TestCase):
    def test_exports_entries_under_missing_parent_and_rejects_invalid_readings(self):
        base = datetime(2026, 10, 10, tzinfo=timezone.utc)
        db = MagicMock()
        day_ref = MagicMock()
        db.collection.return_value.document.return_value.collection.return_value.list_documents.return_value = [day_ref]
        readings = [
            {"recorded_at": base, "temperature": 27.0, "ph_level": 7.2,
             "dissolved_oxygen": 6.0, "turbidity": 15.0},
            {"recorded_at": base + timedelta(minutes=10), "temp_avg": 28.0,
             "pH_avg": 7.3, "DO_avg": 5.8, "turbidity_avg": 18.0},
            {"recorded_at": base + timedelta(minutes=20), "temperature": 27.0,
             "ph_level": 15.0, "dissolved_oxygen": 6.0, "turbidity": 15.0},
        ]
        day_ref.collection.return_value.stream.return_value = [
            MagicMock(to_dict=MagicMock(return_value=reading)) for reading in readings
        ]

        frame = export_tank_history(db, "test-tank")

        self.assertEqual(len(frame), 2)
        self.assertEqual(list(frame.temperature), [27.0, 28.0])
        self.assertEqual(list(frame.ph_level), [7.2, 7.3])
        self.assertEqual(frame.timestamp.iloc[0], base)
        db.collection.return_value.document.return_value.collection.return_value.list_documents.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
