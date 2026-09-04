import json
import os
import unittest

import joblib
import pandas as pd

from anomaly_features import build_anomaly_features, detect_water_quality_anomaly

ROOT = os.path.dirname(os.path.abspath(__file__))


class WaterQualityAnomalyDetectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.frame = pd.read_csv(os.path.join(ROOT, "sensor_dataset.csv"), parse_dates=["timestamp"])
        cls.frame["timestamp"] = cls.frame["timestamp"].astype("int64") / 1e9
        cls.bundle = joblib.load(os.path.join(ROOT, "wqad_model.joblib"))
        with open(os.path.join(ROOT, "anomaly_recommendations.json"), encoding="utf-8") as handle:
            cls.recommendations = json.load(handle)

    def test_features_do_not_include_threshold_labels(self):
        features = build_anomaly_features(self.frame.head(24))
        self.assertFalse(any("class" in name or "threshold" in name or "hazard" in name for name in features.columns))
        self.assertEqual(list(features.columns), self.bundle["features"])

    def test_bundle_is_unsupervised_isolation_forest(self):
        self.assertEqual(self.bundle["algorithm"], "IsolationForest")
        self.assertFalse(self.bundle["training_labels_used"])
        self.assertEqual(self.bundle["training_data_origin"], "synthetic_bootstrap_not_field_validated")

    def test_normal_reference_window_returns_contract(self):
        result = detect_water_quality_anomaly(self.frame.iloc[500:512], self.bundle, self.recommendations)
        self.assertIn(result["status"], {"Normal", "Unusual"})
        self.assertGreaterEqual(result["anomaly_score"], 0)
        self.assertLessEqual(result["anomaly_score"], 100)
        self.assertTrue(result["insight"])
        self.assertTrue(result["recommendation"])

    def test_holdout_event_is_detected_somewhere(self):
        event_rows = self.frame[self.frame["event_type"] == "organic_load_event"]
        detected = False
        for index in event_rows.index[11::6]:
            result = detect_water_quality_anomaly(
                self.frame.loc[index - 11:index], self.bundle, self.recommendations
            )
            detected = detected or result["is_anomaly"]
        self.assertTrue(detected)


if __name__ == "__main__":
    unittest.main()
