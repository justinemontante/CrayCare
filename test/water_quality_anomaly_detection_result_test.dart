import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:craycare/services/water_quality_anomaly_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Water Quality Anomaly Detection result', () {
    test('normalizes only the WQAD contract statuses', () {
      expect(normalizeWaterQualityAnomalyStatus('normal'), 'Normal');
      expect(normalizeWaterQualityAnomalyStatus('ANOMALY'), 'Unusual');
      expect(normalizeWaterQualityAnomalyStatus('unusual'), 'Unusual');
      expect(normalizeWaterQualityAnomalyStatus('Critical'), 'Insufficient');
    });

    test('parses an unsupervised anomaly result', () {
      final result = WaterQualityAnomalyDetectionResult.fromMap({
        'status': 'Unusual',
        'is_anomaly': true,
        'anomaly_score': 99.2,
        'source': 'wqad-isolation-forest-test',
        'model_algorithm': 'IsolationForest',
        'training_data_origin': 'synthetic_bootstrap_not_field_validated',
        'training_label_origin': 'none_unsupervised',
        'driver': 'DO',
        'driver_label': 'Dissolved Oxygen',
        'insight': 'Unusual combined pattern detected.',
        'recommendation': 'Verify the reading and inspect aeration.',
        'timestamp': '2026-09-03T00:00:00Z',
      });
      expect(result.status, 'Unusual');
      expect(result.isAnomaly, isTrue);
      expect(result.anomalyScore, 99.2);
      expect(result.modelBasis, 'Isolation Forest ML');
      expect(result.usesPrototypeData, isTrue);
      expect(result.recommendation, isNotEmpty);
    });
    test('does not expose former threshold assessment labels', () {
      final result = WaterQualityAnomalyDetectionResult.fromMap({
        'status': 'Good',
        'is_anomaly': false,
      });
      expect(result.status, 'Insufficient');
      expect(result.hasData, isFalse);
    });

    test('prefers processed_at Timestamp with legacy fallbacks', () {
      final stamped = WaterQualityAnomalyDetectionResult.fromMap({
        'status': 'Normal',
        'is_anomaly': false,
        'processed_at': Timestamp.fromDate(DateTime.utc(2026, 9, 6, 8)),
        'timestamp': '2026-09-03T00:00:00Z',
        'ts_epoch': 1725619200,
      });
      expect(stamped.timestamp, DateTime.utc(2026, 9, 6, 8));

      final legacy = WaterQualityAnomalyDetectionResult.fromMap({
        'status': 'Normal',
        'is_anomaly': false,
        'ts_epoch': 1725619200,
      });
      expect(legacy.timestamp.year, 2024);
    });
  });
}
