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
        self.assertIn("learned reference pattern", result["insight"])
        self.assertIn("No unusual multivariate behavior", result["insight"])
        self.assertNotIn("water is safe", result["insight"].lower())
        self.assertIn("routine monitoring", result["recommendation"])

    def test_unusual_insight_does_not_claim_a_cause(self):
        result = interpret_anomaly(True, 99, [{
            "sensor": "DO", "value": 4.8, "direction": "decreasing",
            "contribution_score": 0.7,
        }], self.recommendations)
        self.assertIn("unusual combined water-quality pattern", result["insight"])
        self.assertIn("does not diagnose a definite cause", result["insight"])
        self.assertIn("aerator", result["recommendation"].lower())
        self.assertIn("continue monitoring", result["recommendation"].lower())

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
