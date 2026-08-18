import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:craycare/utils/prediction_timestamp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePredictionTimestamp', () {
    final expected = DateTime.utc(2026, 8, 18, 1, 30, 45);

    test('parses Firestore Timestamp', () {
      final timestamp = Timestamp.fromDate(expected);
      expect(parsePredictionTimestamp(timestamp), expected);
    });

    test('parses DateTime and normalizes to UTC', () {
      final localEquivalent = expected.toLocal();
      expect(parsePredictionTimestamp(localEquivalent), expected);
    });

    test('parses ISO-8601 string', () {
      expect(
        parsePredictionTimestamp('2026-08-18T01:30:45.000Z'),
        expected,
      );
    });

    test('parses epoch seconds', () {
      expect(
        parsePredictionTimestamp(expected.millisecondsSinceEpoch ~/ 1000),
        expected,
      );
    });

    test('parses epoch milliseconds', () {
      expect(
        parsePredictionTimestamp(expected.millisecondsSinceEpoch),
        expected,
      );
    });

    test('returns null for missing or malformed values', () {
      expect(parsePredictionTimestamp(null), isNull);
      expect(parsePredictionTimestamp('not-a-timestamp'), isNull);
      expect(parsePredictionTimestamp(double.nan), isNull);
      expect(parsePredictionTimestamp(Object()), isNull);
    });
  });
}
