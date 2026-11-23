import '../models/control_types.dart';

enum FeedingSlot { morning, evening }

/// Feeder logs carry UTC instants while batches and schedules use Asia/Manila
/// wall-clock dates. Keep the conversion in one place so the recommendation
/// progress and the feed chart count the same day.
DateTime feedingManilaDate(DateTime instant) {
  final manila = instant.toUtc().add(manilaUtcOffset);
  return DateTime(manila.year, manila.month, manila.day);
}

class FeedingProgress {
  final FeedingSlot slot;
  final double recommendedGrams;
  final double morningDispensedGrams;
  final double eveningDispensedGrams;

  const FeedingProgress({
    required this.slot,
    required this.recommendedGrams,
    required this.morningDispensedGrams,
    required this.eveningDispensedGrams,
  });

  double get dispensedGrams => slot == FeedingSlot.morning
      ? morningDispensedGrams
      : eveningDispensedGrams;

  double get otherSlotDispensedGrams => slot == FeedingSlot.morning
      ? eveningDispensedGrams
      : morningDispensedGrams;

  double get remainingGrams => (recommendedGrams - dispensedGrams)
      .clamp(0.0, double.infinity)
      .toDouble();

  /// The firmware dispenses whole grams only. Never round a remainder up into
  /// an amount that would exceed the recommended dose.
  double get dispensableGrams =>
      remainingGrams >= 1 ? remainingGrams.floorToDouble() : 0.0;

  bool get canApply => dispensableGrams >= 1;

  /// Servo estimates are noisy by <1 g. Treat that as complete so a farmer is
  /// not trapped by a 0.3 g remainder that cannot be dispensed as a whole gram.
  bool get isDone => remainingGrams < 1;

  String get slotLabel => slot == FeedingSlot.morning ? 'AM' : 'PM';

  String get slotName => slot == FeedingSlot.morning ? 'morning' : 'afternoon';

  String get progressNote {
    if (recommendedGrams <= 0) return 'No recommendation available.';
    if (isDone) {
      final next = slot == FeedingSlot.morning ? 'PM' : 'AM';
      return 'Already fed $slotName: ${dispensedGrams.round()}/'
          '${recommendedGrams.round()} g. Next feeding is $next.';
    }
    if (dispensedGrams > 0) {
      return 'Already fed $slotName: ${dispensedGrams.round()}/'
          '${recommendedGrams.round()} g. Only ${dispensableGrams.round()} g '
          'remains — do not use the full dose.';
    }
    return 'No feed recorded yet this $slotName. '
        '${dispensableGrams.round()} g is available.';
  }
}

/// Sums actual feed dispensed for today's morning/evening halves and reports
/// how much of the current half is still available.
///
/// [now] must already be an Asia/Manila wall-clock value. [batchStart] and
/// [batchEndExclusive] are Manila dates, matching the feed-intake chart.
FeedingProgress computeFeedingProgress({
  required double recommendedGrams,
  required List<LogEntry> logs,
  required DateTime now,
  DateTime? batchStart,
  DateTime? batchEndExclusive,
}) {
  final slot = now.hour < 12 ? FeedingSlot.morning : FeedingSlot.evening;
  final today = DateTime(now.year, now.month, now.day);
  var morning = 0.0;
  var evening = 0.0;

  for (final log in logs) {
    final ms = log.timestamp;
    if (ms <= 0) continue;

    final instant = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    final day = feedingManilaDate(instant);
    if (day != today) continue;
    if (batchStart != null && day.isBefore(batchStart)) continue;
    if (batchEndExclusive != null && !day.isBefore(batchEndExclusive)) continue;

    final local = instant.add(manilaUtcOffset);
    final logSlot = local.hour < 12 ? FeedingSlot.morning : FeedingSlot.evening;

    final status = (log.status ?? '').toLowerCase();
    if (status != 'completed' && status != 'forced') continue;

    final grams = log.estimatedDispensedGrams ?? log.requestedGrams ?? 0.0;
    if (!grams.isFinite || grams <= 0) continue;

    if (logSlot == FeedingSlot.morning) {
      morning += grams;
    } else {
      evening += grams;
    }
  }

  return FeedingProgress(
    slot: slot,
    recommendedGrams: recommendedGrams,
    morningDispensedGrams: morning,
    eveningDispensedGrams: evening,
  );
}
