import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/services/water_quality_assessment_service.dart';

void main() {
  group('Water Quality Assessment labels', () {
    test('keeps the four current condition labels', () {
      expect(normalizeWaterQualityAssessmentLevel('Good'), 'Good');
      expect(normalizeWaterQualityAssessmentLevel('Moderate'), 'Moderate');
      expect(normalizeWaterQualityAssessmentLevel('Poor'), 'Poor');
      expect(normalizeWaterQualityAssessmentLevel('Critical'), 'Critical');
    });

    test('normalizes legacy risk labels in stored history', () {
      expect(normalizeWaterQualityAssessmentLevel('Low'), 'Good');
      expect(normalizeWaterQualityAssessmentLevel('High'), 'Poor');
    });

    test('uses Insufficient for unknown or missing values', () {
      expect(normalizeWaterQualityAssessmentLevel(null), 'Insufficient');
      expect(normalizeWaterQualityAssessmentLevel('unknown'), 'Insufficient');
    });

    test('preserves safety-floor metadata from new assessments', () {
      final result = WaterQualityAssessmentResult.fromMap({
        'level': 'Critical',
        'model_level': 'Poor',
        'rule_level': 'Critical',
        'safety_override': true,
        'timestamp': DateTime.utc(2026, 8, 19).toIso8601String(),
      });

      expect(result.level, 'Critical');
      expect(result.modelLevel, 'Poor');
      expect(result.ruleLevel, 'Critical');
      expect(result.safetyOverride, isTrue);
      expect(result.assessmentBasis, 'Safety Rule');
    });

    test('does not present deterministic fallback as ML confidence', () {
      final result = WaterQualityAssessmentResult.fromMap({
        'level': 'Moderate',
        'model_level': 'Moderate',
        'rule_level': 'Moderate',
        'safety_override': false,
        'source': 'Rule-based fallback',
        'confidence': 0,
        'timestamp': DateTime.utc(2026, 8, 25).toIso8601String(),
      });

      expect(result.assessmentBasis, 'Rule-Based Fallback');
      expect(result.hasModelConfidence, isFalse);
    });
  });
}
