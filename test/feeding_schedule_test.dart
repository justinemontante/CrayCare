import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/models/control_types.dart';

void main() {
  group('feeder repeat-day scheduling', () {
    test('Manila wall clock does not retain the shifted UTC flag', () {
      final now = manilaWallClock(DateTime.utc(2026, 8, 19, 6, 52));

      expect(now, DateTime(2026, 8, 19, 14, 52));
      expect(now.isUtc, isFalse);
      final schedules = [
        ScheduleItem('6:00', 'AM', days: '0001000'),
        ScheduleItem('4:00', 'PM', days: '0001000'),
      ];

      expect(nextEnabledFeeding(schedules, now)?.schedule.time, '4:00');
    });

    test('selects the nearest of multiple enabled times today', () {
      final now = DateTime(2026, 8, 19, 10, 0); // Wednesday.
      final schedules = [
        ScheduleItem('8:00', 'AM'),
        ScheduleItem('6:00', 'PM'),
        ScheduleItem('2:00', 'PM'),
      ];

      final next = nextEnabledFeeding(schedules, now);

      expect(next?.schedule.time, '2:00');
      expect(next?.schedule.ampm, 'PM');
      expect(next?.at, DateTime(2026, 8, 19, 14, 0));
    });

    test('ignores a disabled nearer schedule', () {
      final now = DateTime(2026, 8, 19, 10, 0);
      final schedules = [
        ScheduleItem('11:00', 'AM', enabled: false),
        ScheduleItem('2:00', 'PM'),
      ];

      final next = nextEnabledFeeding(schedules, now);

      expect(next?.schedule.time, '2:00');
      expect(next?.at, DateTime(2026, 8, 19, 14, 0));
    });

    test('moves to the next active repeat day after todays time passes', () {
      final now = DateTime(2026, 8, 19, 15, 0); // Wednesday.
      final weekdays = ScheduleItem('2:00', 'PM', days: '0111110');

      final next = nextFeederScheduleOccurrence(weekdays, now);

      expect(next, DateTime(2026, 8, 20, 14, 0)); // Thursday.
    });

    test('honors the Sunday-first day mask across a weekend', () {
      final now = DateTime(2026, 8, 21, 16, 0); // Friday.
      final mondayOnly = ScheduleItem('7:30', 'AM', days: '0100000');

      final next = nextFeederScheduleOccurrence(mondayOnly, now);

      expect(next, DateTime(2026, 8, 24, 7, 30));
    });

    test('completed daily schedule advances to tomorrow', () {
      final now = DateTime(2026, 8, 19, 7, 0);
      final daily = ScheduleItem('8:00', 'AM', isDone: true);

      final next = nextEnabledFeeding(
        [daily],
        now,
        skipToday: (schedule) => schedule.isDone,
      );

      expect(next?.at, DateTime(2026, 8, 20, 8, 0));
    });

    test('returns null when every repeat day is off', () {
      final schedule = ScheduleItem('8:00', 'AM', days: '0000000');

      expect(
        nextFeederScheduleOccurrence(schedule, DateTime(2026, 8, 19, 7)),
        isNull,
      );
    });

    test('detects same-time overlap even when amounts and masks differ', () {
      final first = ScheduleItem(
        '4:00',
        'PM',
        grams: 20,
        days: '0110000', // Monday and Tuesday.
      );
      final second = ScheduleItem(
        '4:00',
        'PM',
        grams: 35,
        days: '0101000', // Monday and Wednesday.
      );

      expect(feederSchedulesConflict(first, second), isTrue);
      expect(feederScheduleConflictMessage(second, first), contains('Monday'));
    });

    test('allows the same time on completely different days', () {
      final monday = ScheduleItem('4:00', 'PM', days: '0100000');
      final wednesday = ScheduleItem('4:00', 'PM', days: '0001000');

      expect(feederSchedulesConflict(monday, wednesday), isFalse);
    });

    test('allows different times on the same day', () {
      final first = ScheduleItem('4:00', 'PM', days: '0100000');
      final second = ScheduleItem('5:00', 'PM', days: '0100000');

      expect(feederSchedulesConflict(first, second), isFalse);
    });
  });

  group('schedule effective occurrence', () {
    test('new schedule after today occurrence is not considered due', () {
      final schedule = ScheduleItem('2:00', 'PM', effectiveAt: DateTime.utc(2026, 8, 20, 8, 30));
      expect(feederScheduleWasEffectiveAt(schedule, DateTime(2026, 8, 20, 14)), isFalse);
    });
    test('schedule created before occurrence remains due', () {
      final schedule = ScheduleItem('2:00', 'PM', effectiveAt: DateTime.utc(2026, 8, 20, 5));
      expect(feederScheduleWasEffectiveAt(schedule, DateTime(2026, 8, 20, 14)), isTrue);
    });
    test('legacy schedule keeps previous behavior', () {
      expect(feederScheduleWasEffectiveAt(ScheduleItem('2:00', 'PM'), DateTime(2026, 8, 20, 14)), isTrue);
    });
  });
}
