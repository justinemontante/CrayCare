import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/utils/timestamp_parser.dart';

void main() {
  test('parses every supported Firestore timestamp representation', () {
    final expected = DateTime.utc(2026, 8, 18, 1, 2, 3);

    expect(parseFirestoreDateTime(expected), expected);
    expect(parseFirestoreDateTime(Timestamp.fromDate(expected)), expected);
    expect(parseFirestoreDateTime(expected.toIso8601String()), expected);
    expect(
      parseFirestoreDateTime(expected.millisecondsSinceEpoch),
      expected,
    );
    expect(
      parseFirestoreDateTime(expected.millisecondsSinceEpoch ~/ 1000),
      expected,
    );
  });

  test('returns null for absent or malformed timestamps', () {
    expect(parseFirestoreDateTime(null), isNull);
    expect(parseFirestoreDateTime('not-a-date'), isNull);
    expect(parseFirestoreDateTime(<String, Object?>{}), isNull);
  });
}
