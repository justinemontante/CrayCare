import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/models/control_types.dart';

void main() {
  final today = DateTime(2026, 8, 26, 16, 5);
  final occurrence = DateTime.utc(2026, 8, 26, 8);

  ScheduleItem schedule({
    String? status,
    DateTime? at,
    bool done = false,
    DateTime? effective,
  }) => ScheduleItem(
    '4:00',
    'PM',
    id: 'sched',
    isDone: done,
    lastOutcome: status,
    lastOccurrenceAt: at,
    effectiveAt: effective,
  );

  test('only supported fixed-cycle doses are accepted', () {
    for (final dose in <double?>[null, 20, 40, 200]) {
      expect(validateFeederGrams(dose), isNull);
    }
    for (final dose in [
      0.0,
      -20.0,
      25.0,
      35.0,
      201.0,
      double.nan,
      double.infinity,
    ]) {
      expect(validateFeederGrams(dose), isNotNull);
    }
  });
  test('legacy done flag alone cannot claim completed feeding', () {
    expect(feederRecordedOutcome(schedule(done: true), today, []), isNull);
  });
  test('skipped and blocked are not completed', () {
    for (final status in ['skipped_insufficient', 'blocked']) {
      expect(
        feederOutcomeOnDate(
          schedule(status: status, at: occurrence, done: true),
          today,
        ),
        'skipped',
      );
    }
    expect(
      feederOutcomeOnDate(schedule(status: 'failed', at: occurrence), today),
      'failed',
    );
    expect(
      feederOutcomeOnDate(schedule(status: 'completed', at: occurrence), today),
      'completed',
    );
  });
  test('yesterday and pre-edit outcomes do not complete today', () {
    expect(
      feederOutcomeOnDate(
        schedule(
          status: 'completed',
          at: occurrence.subtract(const Duration(days: 1)),
        ),
        today,
      ),
      isNull,
    );
    expect(
      feederOutcomeOnDate(
        schedule(
          status: 'completed',
          at: occurrence,
          effective: occurrence.add(const Duration(seconds: 1)),
        ),
        today,
      ),
      isNull,
    );
  });
  test('explicit skipped log overrides legacy done flag', () {
    final log = LogEntry(
      'Skipped - Insufficient feed',
      'auto',
      '4:00 PM',
      'Aug 26, 2026',
      timestamp: occurrence.millisecondsSinceEpoch,
      scheduleKey: 'sched',
      scheduleTime: '4:00 PM',
      status: 'skipped_insufficient',
    );
    expect(
      feederRecordedOutcome(schedule(done: true), today, [log]),
      'skipped',
    );
  });
  test('offline outcome uses occurrence date, not upload/completion date', () {
    final log = LogEntry(
      'Dispensed feed (Scheduled)',
      'auto',
      '4:00 PM',
      'Aug 27, 2026',
      timestamp: occurrence.add(const Duration(days: 1)).millisecondsSinceEpoch,
      occurrenceTimestamp: occurrence.millisecondsSinceEpoch,
      scheduleKey: 'sched',
      scheduleTime: '4:00 PM',
      status: 'completed',
    );
    expect(feederRecordedOutcome(schedule(), today, [log]), 'completed');
    expect(
      feederRecordedOutcome(schedule(), today.add(const Duration(days: 1)), [
        log,
      ]),
      isNull,
    );
  });
  test('manual feed cannot complete a scheduled occurrence', () {
    final log = LogEntry(
      'Dispensed feed (Manual)',
      'manual',
      '4:00 PM',
      'Aug 26, 2026',
      timestamp: occurrence.millisecondsSinceEpoch,
      status: 'completed',
    );
    expect(feederRecordedOutcome(schedule(), today, [log]), isNull);
  });

  test('manual feeding is blocked during the minute before a schedule', () {
    final item = ScheduleItem('6:00', 'PM', days: '1111111');
    final guard = manualFeedScheduleGuard([
      item,
    ], DateTime(2026, 9, 4, 17, 59, 15));
    expect(guard.isBlocked, isTrue);
  });

  test('manual feeding is blocked throughout the scheduled minute', () {
    final item = ScheduleItem('6:00', 'PM', days: '1111111');
    final guard = manualFeedScheduleGuard([
      item,
    ], DateTime(2026, 9, 4, 18, 0, 45));
    expect(guard.isBlocked, isTrue);
  });

  test('manual feeding needs confirmation within fifteen minutes', () {
    final item = ScheduleItem('6:00', 'PM', days: '1111111');
    final guard = manualFeedScheduleGuard([item], DateTime(2026, 9, 4, 17, 50));
    expect(guard.needsConfirmation, isTrue);
  });

  test('recent scheduled feeding also requires confirmation', () {
    final item = ScheduleItem('6:00', 'PM', days: '1111111');
    final guard = manualFeedScheduleGuard([item], DateTime(2026, 9, 4, 18, 5));
    expect(guard.needsConfirmation, isTrue);
  });

  test('manual feeding is clear outside the warning window', () {
    final item = ScheduleItem('6:00', 'PM', days: '1111111');
    final guard = manualFeedScheduleGuard([item], DateTime(2026, 9, 4, 17, 40));
    expect(guard.level, ManualFeedScheduleGuardLevel.clear);
  });
}
