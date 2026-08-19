"""Regression tests for Water Quality Assessment class semantics and safety."""

import json
import os
import unittest

import numpy as np
import pandas as pd

from assessment_interpreter import enrich_assessment
from features import (
    CLASS_NAMES,
    assess_water_quality,
    build_features,
    classify,
)


_DIR = os.path.dirname(os.path.abspath(__file__))


class _FixedClassifier:
    def __init__(self, predicted_class):
        self.predicted_class = predicted_class

    def predict(self, frame):
        return np.array([self.predicted_class])

    def predict_proba(self, frame):
        probabilities = np.full(4, 0.02)
        probabilities[self.predicted_class] = 0.94
        return np.array([probabilities])


def _sensor_frame(
    *,
    temp=26.0,
    ph=7.5,
    dissolved_oxygen=6.5,
    turbidity=8.0,
    water_level=17.5,
    rows=12,
):
    values = {
        "temp": temp,
        "pH": ph,
        "DO": dissolved_oxygen,
        "turbidity": turbidity,
        "waterLevel": water_level,
    }
    records = []
    for index in range(rows):
        record = {"timestamp": index}
        for sensor, value in values.items():
            record[f"{sensor}_avg"] = value
            record[f"{sensor}_min"] = value
            record[f"{sensor}_max"] = value
        records.append(record)
    return pd.DataFrame(records)


class WaterQualityAssessmentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(
            os.path.join(_DIR, "recommendations.json"),
            encoding="utf-8",
        ) as handle:
            cls.recommendations = json.load(handle)

    def _bundle(self, frame, predicted_class):
        features, _ = build_features(frame)
        return {
            "model": _FixedClassifier(predicted_class),
            "features": list(features.columns),
            "type": "assessment",
            "model_version": "test-assessment-model",
        }

    def test_public_class_names_are_condition_labels(self):
        self.assertEqual(
            CLASS_NAMES,
            ["Good", "Moderate", "Poor", "Critical"],
        )
        self.assertEqual(classify(0), (0, "Good"))
        self.assertEqual(classify(25), (1, "Moderate"))
        self.assertEqual(classify(50), (2, "Poor"))
        self.assertEqual(classify(75), (3, "Critical"))

    def test_rolling_rule_floor_cannot_be_downgraded_by_model(self):
        frame = _sensor_frame(dissolved_oxygen=0.5)
        result = assess_water_quality(
            frame,
            self._bundle(frame, predicted_class=2),
            self.recommendations,
        )
        self.assertEqual(result["model_level"], "Poor")
        self.assertEqual(result["rule_level"], "Critical")
        self.assertEqual(result["level"], "Critical")
        self.assertTrue(result["safety_override"])

    def test_mild_active_condition_can_remain_good(self):
        frame = _sensor_frame(dissolved_oxygen=4.9)
        result = assess_water_quality(
            frame,
            self._bundle(frame, predicted_class=0),
            self.recommendations,
        )
        result = enrich_assessment(result, frame, self.recommendations)
        self.assertEqual(result["level"], "Good")

    def test_immediate_critical_reading_overrides_poor(self):
        frame = _sensor_frame(dissolved_oxygen=1.9, rows=1)
        result = assess_water_quality(
            frame,
            self._bundle(frame, predicted_class=2),
            self.recommendations,
        )
        self.assertEqual(result["level"], "Poor")
        result = enrich_assessment(result, frame, self.recommendations)
        self.assertEqual(result["level"], "Critical")
        self.assertTrue(result["safety_override"])


if __name__ == "__main__":
    unittest.main()
