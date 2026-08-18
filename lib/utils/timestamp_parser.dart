import 'package:cloud_firestore/cloud_firestore.dart';

/// Parses the timestamp representations used by current and legacy Firestore
/// documents. Numeric values accept both epoch seconds (used by `ts_epoch`)
/// and epoch milliseconds (used by legacy mobile records).
DateTime? parseFirestoreDateTime(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) {
    final epoch = value.toInt();
    // Millisecond epochs are currently 13 digits, while second epochs are 10.
    // The threshold also keeps historical dates unambiguous for this app.
    final milliseconds = epoch.abs() < 100000000000 ? epoch * 1000 : epoch;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }
  return null;
}
