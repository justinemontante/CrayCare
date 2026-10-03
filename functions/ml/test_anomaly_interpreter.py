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
        self.assertIn("usual pattern", result["insight"])
        self.assertIn("separate sensor safety alerts", result["insight"])
        self.assertNotIn("water is safe", result["insight"].lower())

    def test_unusual_insight_does_not_claim_a_cause(self):
        result = interpret_anomaly(True, 99, [{
            "sensor": "DO", "value": 4.8, "direction": "decreasing",
            "contribution_score": 0.7,
        }], self.recommendations)
        self.assertIn("unusual combined pattern", result["insight"])
        self.assertIn("establish the cause", result["insight"])
        self.assertIn("possible explanation", result["recommendation"])

    def test_recommendation_evidence_references_resolve(self):
        references = self.recommendations["_references"]
        evidence = self.recommendations["_evidence"]
        self.assertTrue(references)
        for keys in evidence.values():
            self.assertTrue(keys)
            for key in keys:
                self.assertIn(key, references)
                self.assertTrue(references[key]["url"].startswith("https://"))


if __name__ == "__main__":
    unittest.main()
