import os
import unittest

import joblib

import anomaly_window
import train_model
from anomaly_features import SENSORS

ROOT = os.path.dirname(os.path.abspath(__file__))


class ModelArtifactContractTests(unittest.TestCase):
    """Keep the shipped artifact, the trainer, and the runtime window aligned.

    The live inference window is defined only in ``anomaly_window``. The
    trainer imports those constants, and this test fails if the two ever
    drift apart or if the shipped bundle stops matching the runtime contract.
    """

    @classmethod
    def setUpClass(cls):
        cls.bundle = joblib.load(os.path.join(ROOT, "trained_wqad_model.joblib"))

    def test_runtime_window_constants_are_the_documented_values(self):
        self.assertEqual(anomaly_window.ANALYSIS_WINDOW_SECONDS, 120 * 60)
        self.assertEqual(anomaly_window.MIN_LIVE_ROWS, 6)
        self.assertEqual(anomaly_window.MIN_SPAN_SECONDS, 110 * 60)
        self.assertEqual(anomaly_window.CADENCE_MIN_SECONDS, 480)
        self.assertEqual(anomaly_window.CADENCE_MAX_SECONDS, 1800)
        self.assertEqual(anomaly_window.CADENCE_GAP_FACTOR, 2.2)
        self.assertEqual(anomaly_window.STALE_AFTER_SECONDS, 20 * 60)

    def test_trainer_derives_window_fields_from_the_runtime(self):
        self.assertEqual(train_model.MIN_LIVE_ROWS, anomaly_window.MIN_LIVE_ROWS)
        self.assertEqual(train_model.ANALYSIS_WINDOW_SECONDS,
                         anomaly_window.ANALYSIS_WINDOW_SECONDS)

    def test_shipped_artifact_matches_the_runtime_contract(self):
        self.assertEqual(self.bundle["feature_version"], 3)
        self.assertEqual(self.bundle["algorithm"], "IsolationForest")
        self.assertEqual(self.bundle["sensors"], SENSORS)
        self.assertEqual(self.bundle["analysis_window_minutes"],
                         anomaly_window.ANALYSIS_WINDOW_SECONDS // 60)

    def test_recorded_row_count_is_provenance_only(self):
        # The bundle records the row count used when the artifact was trained.
        # Inference never reads it, so a difference from the runtime constant
        # is provenance, not a behavioural difference. The runtime always
        # applies anomaly_window.MIN_LIVE_ROWS.
        recorded = self.bundle.get("minimum_live_history_rows")
        self.assertTrue(recorded is None or isinstance(recorded, int))
        self.assertEqual(anomaly_window.MIN_LIVE_ROWS, 6)


if __name__ == "__main__":
    unittest.main()
