import json
import os
import unittest

import joblib
import pandas as pd

from anomaly_features import SENSORS, build_anomaly_features, detect_water_quality_anomaly

ROOT = os.path.dirname(os.path.abspath(__file__))


class WaterQualityAnomalyDetectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.frame = pd.read_csv(os.path.join(ROOT, "sensor_dataset.csv"), parse_dates=["timestamp"])
        cls.frame["timestamp"] = pd.to_datetime(cls.frame["timestamp"], utc=True).map(lambda value: value.timestamp())
        cls.bundle = joblib.load(os.path.join(ROOT, "wqad_model.joblib"))
        with open(os.path.join(ROOT, "anomaly_recommendations.json"), encoding="utf-8") as handle:
            cls.recommendations = json.load(handle)

    def test_features_do_not_include_threshold_labels(self):
        features = build_anomaly_features(
            self.frame.head(24), sensors=self.bundle.get('sensors', SENSORS),
            version=self.bundle.get('feature_version', 1),
        )
        self.assertFalse(any("class" in name or "threshold" in name or "hazard" in name for name in features.columns))
        self.assertEqual(list(features.columns), self.bundle["features"])

    def test_bundle_is_unsupervised_isolation_forest(self):
        self.assertEqual(self.bundle["algorithm"], "IsolationForest")
        self.assertFalse(self.bundle["training_labels_used"])
        self.assertEqual(self.bundle["sensors"], SENSORS)
        self.assertFalse(any("waterLevel" in name for name in self.bundle["features"]))
        self.assertEqual(self.bundle["training_data_origin"], "external_freshwater_fishpond_proxy_unvalidated")

    def test_normal_reference_window_returns_contract(self):
        result = detect_water_quality_anomaly(self.frame.iloc[500:512], self.bundle, self.recommendations)
        self.assertIn(result["status"], {"Normal", "Unusual"})
        self.assertGreaterEqual(result["anomaly_score"], 0)
        self.assertLessEqual(result["anomaly_score"], 100)
        self.assertTrue(result["insight"])
        self.assertTrue(result["recommendation"])
        self.assertEqual(
            set(result["contributors"][0]),
            {"sensor", "value", "direction", "contribution_score"},
        )
        self.assertNotIn("primary_driver", result)
        self.assertNotIn("driver_label", result)
        self.assertNotIn("analysis_window_minutes", result)
        self.assertFalse(
            {
                "model_algorithm",
                "training_data_origin",
                "training_label_origin",
                "model_feature_count",
            }
            & result.keys()
        )

    def test_inference_uses_four_water_quality_sensors_only(self):
        result = detect_water_quality_anomaly(
            self.frame.iloc[500:512], self.bundle, self.recommendations
        )
        self.assertTrue(result["contributors"])
        self.assertFalse(any(item["sensor"] == "waterLevel" for item in result["contributors"]))


if __name__ == "__main__":
    unittest.main()
