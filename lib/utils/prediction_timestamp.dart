import 'package:cloud_firestore/cloud_firestore.dart';

/// Parses prediction timestamps written by different CrayCare components.
///
/// Supported values:
/// - Firestore [Timestamp]
/// - Dart [DateTime]
/// - ISO-8601 strings
/// - epoch seconds
/// - epoch milliseconds
///
/// Returns `null` for missing, malformed, non-finite, or unsupported values.
DateTime? parsePredictionTimestamp(dynamic value) {
  if (value == null) return null;

  if (value is Timestamp) {
    return value.toDate().toUtc();
  }

  if (value is DateTime) {
    return value.toUtc();
  }

  if (value is String) {
    final parsed = DateTime.tryParse(value);
    return parsed?.toUtc();
  }

  if (value is num) {
    final numeric = value.toDouble();
    if (!numeric.isFinite) return null;

    // Current Unix time is ~1.8e9 seconds and ~1.8e12 milliseconds.
    // Values below 1e11 are therefore treated as seconds; larger values as ms.
    final milliseconds = numeric.abs() < 100000000000
        ? (numeric * 1000).round()
        : numeric.round();

    try {
      return DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      );
    } on RangeError {
      return null;
    }
  }

  return null;
}
