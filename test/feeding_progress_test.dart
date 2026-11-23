import 'package:flutter_test/flutter_test.dart';

import 'package:craycare/models/control_types.dart';
import 'package:craycare/utils/feeding_progress.dart';

LogEntry _feed({
  required DateTime at,
  required String status,
  String type = 'auto',
  String? scheduleTime,
  double? estimated,
  double? requested,
}) {
  return LogEntry(
    'Dispensed feed (Scheduled)',
    type,
    '',
    '',
    timestamp: at.millisecondsSinceEpoch,
    scheduleTime: scheduleTime,
    status: status,
    estimatedDispensedGrams: estimated,
    requestedGrams: requested,
  );
}

void main() {
  final now = DateTime(2026, 11, 23, 8, 27);

  group('computeFeedingProgress', () {
    test('pending confirmation: no grams counted', () {
      final progress = computeFeedingProgress(
        recommendedGrams: 28,
        logs: [
          _feed(
            at: DateTime.utc(2026, 11, 22, 23, 17),
            status: 'pending_confirmation',
            type: 'pending_confirmation',
            scheduleTime: '6:00 AM',
          ),
        ],
        now: now,
      );

      expect(progress.slot, FeedingSlot.morning);
      expect(progress.slotLabel, 'AM');
      expect(progress.morningDispensedGrams, 0);
      expect(progress.remainingGrams, 28);
      expect(progress.dispensableGrams, 28);
      expect(progress.canApply, isTrue);
      expect(progress.isDone, isFalse);
    });

    test('partial morning: only the whole-gram remainder is dispensable', () {
      final progress = computeFeedingProgress(
        recommendedGrams: 28,
        logs: [
          _feed(
            at: DateTime.utc(2026, 11, 22, 22, 0),
            status: 'completed',
            estimated: 9.7,
            requested: 10,
          ),
        ],
        now: now,
      );

      expect(progress.morningDispensedGrams, 9.7);
      expect(progress.remainingGrams, closeTo(18.3, 0.0001));
      expect(progress.dispensableGrams, 18);
      expect(progress.canApply, isTrue);
    });

    test('fully fed morning disables apply and keeps afternoon separate', () {
      final progress = computeFeedingProgress(
        recommendedGrams: 28,
        logs: [
          _feed(
            at: DateTime.utc(2026, 11, 22, 22, 0),
            status: 'completed',
            estimated: 28,
          ),
          _feed(
            at: DateTime.utc(2026, 11, 23, 10, 0),
            status: 'forced',
            estimated: 28,
          ),
        ],
        now: now,
      );

      expect(progress.morningDispensedGrams, 28);
      expect(progress.eveningDispensedGrams, 28);
      expect(progress.slot, FeedingSlot.morning);
      expect(progress.remainingGrams, 0);
      expect(progress.dispensableGrams, 0);
      expect(progress.canApply, isFalse);
      expect(progress.isDone, isTrue);
      expect(progress.progressNote, contains('Next feeding is PM'));
    });

    test('sub-gram estimate noise counts as complete', () {
      final progress = computeFeedingProgress(
        recommendedGrams: 28,
        logs: [
          _feed(
            at: DateTime.utc(2026, 11, 22, 22, 0),
            status: 'completed',
            estimated: 27.7,
          ),
        ],
        now: now,
      );

      expect(progress.remainingGrams, closeTo(0.3, 0.0001));
      expect(progress.dispensableGrams, 0);
      expect(progress.isDone, isTrue);
    });

    test('afternoon slot uses the afternoon total', () {
      final progress = computeFeedingProgress(
        recommendedGrams: 28,
        logs: [
          _feed(
            at: DateTime.utc(2026, 11, 22, 22, 0),
            status: 'completed',
            estimated: 28,
          ),
          _feed(
            at: DateTime.utc(2026, 11, 23, 10, 0),
            status: 'completed',
            estimated: 6,
          ),
        ],
        now: DateTime(2026, 11, 23, 18, 30),
      );

      expect(progress.slot, FeedingSlot.evening);
      expect(progress.slotLabel, 'PM');
      expect(progress.otherSlotDispensedGrams, 28);
      expect(progress.dispensedGrams, 6);
      expect(progress.dispensableGrams, 22);
    });

    test('ignores other days, non-dispense events and zero gram logs', () {
      final progress = computeFeedingProgress(
        recommendedGrams: 28,
        logs: [
          _feed(
            at: DateTime.utc(2026, 11, 22, 10, 0),
            status: 'completed',
            estimated: 28,
          ),
          _feed(
            at: DateTime.utc(2026, 11, 22, 23, 30),
            status: 'skipped',
            estimated: 28,
          ),
          _feed(
            at: DateTime.utc(2026, 11, 22, 22, 0),
            status: 'completed',
            estimated: 0,
            requested: 0,
          ),
          _feed(
            at: DateTime.utc(2026, 11, 22, 22, 30),
            status: 'completed',
            estimated: 4,
          ),
        ],
        now: now,
      );

      expect(progress.morningDispensedGrams, 4);
      expect(progress.dispensableGrams, 24);
    });

    test('respects the selected batch window', () {
      final progress = computeFeedingProgress(
        recommendedGrams: 28,
        logs: [
          _feed(
            at: DateTime.utc(2026, 11, 22, 22, 0),
            status: 'completed',
            estimated: 28,
          ),
        ],
        now: now,
        batchStart: DateTime(2026, 11, 24),
      );

      expect(progress.morningDispensedGrams, 0);
      expect(progress.dispensableGrams, 28);
    });

    test('feedingManilaDate converts UTC instants to Manila dates', () {
      expect(
        feedingManilaDate(DateTime.utc(2026, 11, 22, 22, 0)),
        DateTime(2026, 11, 23),
      );
    });
  });
}
