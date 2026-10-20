import json
import unittest
from pathlib import Path

from anomaly_interpreter import interpret_anomaly


ROOT = Path(__file__).parent


class AnomalyInterpreterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.recommendations = json.loads(
            (ROOT / "anomaly_recommendations.json").read_text(encoding="utf-8")
        )

    def test_normal_means_pattern_match_not_safe_water_claim(self):
        result = interpret_anomaly(False, 20, [], self.recommendations)
        self.assertIn("No unusual change was found", result["insight"])
        self.assertNotIn("water is safe", result["insight"].lower())
        self.assertIn("Keep checking the tank", result["recommendation"])

    def test_unusual_insight_does_not_claim_a_cause(self):
        result = interpret_anomaly(True, 99, [{
            "sensor": "DO", "value": 4.8, "direction": "decreasing",
            "contribution_score": 0.7,
        }], self.recommendations)
        self.assertIn("Recent readings show an unusual change", result["insight"])
        self.assertIn("Dissolved oxygen (4.8 mg/L) is falling", result["insight"])
        self.assertNotIn("confirmed causes", result["insight"])
        self.assertNotIn("safety-limit checks", result["insight"])
        self.assertIn("aerator", result["recommendation"].lower())
        self.assertIn("check the dissolved oxygen", result["recommendation"].lower())

    def test_no_contributors_uses_general_verification_advice(self):
        result = interpret_anomaly(True, 99, [], self.recommendations)
        self.assertIn("could not tell which reading stands out", result["insight"])
        self.assertIn("check the readings", result["recommendation"].lower())
        self.assertIn("sensor warning", result["recommendation"].lower())

    def test_temperature_and_falling_do_select_combined_guidance(self):
        result = interpret_anomaly(True, 99, [
            {"sensor": "DO", "value": 4.8, "direction": "decreasing", "contribution_score": 0.7},
            {"sensor": "temp", "value": 29.2, "direction": "increasing", "contribution_score": 0.6},
        ], self.recommendations)
        self.assertIn("make sure the aerator is running", result["recommendation"])
        self.assertIn("temperature or oxygen warning", result["recommendation"])

    def test_matching_ph_and_do_trends_select_daily_cycle_guidance(self):
        result = interpret_anomaly(True, 99, [
            {"sensor": "pH", "value": 7.9, "direction": "increasing", "contribution_score": 0.7},
            {"sensor": "DO", "value": 7.1, "direction": "increasing", "contribution_score": 0.6},
        ], self.recommendations)
        self.assertIn("check the pH and dissolved oxygen readings", result["recommendation"])
        self.assertIn("pH or oxygen warning", result["recommendation"])

    def test_weak_secondary_sensor_does_not_trigger_combined_advice(self):
        result = interpret_anomaly(True, 99, [
            {"sensor": "pH", "value": 7.9, "direction": "increasing", "contribution_score": 0.7},
            {"sensor": "DO", "value": 7.1, "direction": "increasing", "contribution_score": 0.2},
        ], self.recommendations)
        self.assertIn("Check the pH", result["recommendation"])
        self.assertNotIn("pH or oxygen warning", result["recommendation"])

    def test_decreasing_do_and_increasing_turbidity_select_combined_guidance(self):
        result = interpret_anomaly(True, 99, [
            {"sensor": "DO", "value": 4.8, "direction": "decreasing", "contribution_score": 0.7},
            {"sensor": "turbidity", "value": 28.0, "direction": "increasing", "contribution_score": 0.6},
        ], self.recommendations)
        self.assertIn("Check the dissolved oxygen and water-clarity readings", result["recommendation"])
        self.assertIn("oxygen or water-clarity warning", result["recommendation"])

    def test_sensor_directions_have_cautious_recommendations(self):
        for sensor in ("temp", "pH", "DO", "turbidity"):
            for direction in ("increasing", "decreasing", "stable"):
                with self.subTest(sensor=sensor, direction=direction):
                    result = interpret_anomaly(True, 99, [{
                        "sensor": sensor, "value": 1.0, "direction": direction,
                        "contribution_score": 1.0,
                    }], self.recommendations)
                    self.assertTrue(result["recommendation"].strip())
                    self.assertRegex(result["recommendation"], r"^(Verify|Check|Confirm)")
                    self.assertNotIn("confirmed causes", result["insight"])

    def test_every_recommendation_has_evidence_mapping(self):
        evidence = self.recommendations["_evidence"]
        expected = {"overall.normal", "overall.verify", "combined_do_turbidity.action",
                    "combined_temp_do.action", "combined_ph_do.action"}
        for sensor in ("temp", "pH", "DO", "turbidity"):
            expected.update(f"{sensor}.{direction}" for direction in
                            ("increasing", "decreasing", "stable", "verify"))
        self.assertEqual(set(evidence), expected)

    def test_recommendation_evidence_references_resolve(self):
        references = self.recommendations["_references"]
        evidence = self.recommendations["_evidence"]
        self.assertTrue(references)
        for keys in evidence.values():
            self.assertTrue(keys)
            for key in keys:
                self.assertIn(key, references)
                self.assertTrue(references[key]["url"].startswith("https://"))
        self.assertIn("usgs.gov", references["usgs_do"]["url"])
        self.assertIn("business.qld.gov.au", references["redclaw_qld"]["url"])


if __name__ == "__main__":
    unittest.main()
