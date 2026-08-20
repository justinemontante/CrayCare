import 'package:flutter/foundation.dart';

const manilaUtcOffset = Duration(hours: 8);
const defaultFeederGrams = 20.0;

/// Returns Manila calendar fields in a non-UTC [DateTime]. Schedule helpers
/// compare wall-clock fields, so preserving `isUtc` after adding eight hours
/// would shift comparisons by another eight hours.
DateTime manilaWallClock([DateTime? instant]) {
  final shifted = (instant ?? DateTime.now()).toUtc().add(manilaUtcOffset);
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
    shifted.millisecond,
    shifted.microsecond,
  );
}

class ScheduleItem {
  final String time;
  final String ampm;
  final bool enabled;
  final bool isDone;
  final double? grams;
  final String? id;

  /// Instant when this schedule configuration became effective. This prevents
  /// a newly-created, edited, or re-enabled schedule from being treated as a
  /// missed occurrence earlier on the same day.
  final DateTime? effectiveAt;

  /// Day-of-week mask, Sunday first: "1111111" = every day,
  /// "1010100" = Sun/Tue/Thu only. Each char is '1' (on) or '0' (off).
  final String days;

  ScheduleItem(
    this.time,
    this.ampm, {
    this.enabled = true,
    this.isDone = false,
    this.grams,
    this.days = '1111111',
    this.id,
    this.effectiveAt,
  });
}

const feederDayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/// Returns the days shared by two Sunday-first repeat masks. Legacy or
/// malformed masks are treated as daily, matching the schedule runner.
List<int> overlappingFeederDays(String first, String second) {
  bool runsOn(String mask, int day) => mask.length < 7 || mask[day] == '1';

  return [
    for (var day = 0; day < 7; day++)
      if (runsOn(first, day) && runsOn(second, day)) day,
  ];
}

/// Two schedules conflict when they would dispense at the same time on at
/// least one common day. Feed amount intentionally does not affect this rule.
bool feederSchedulesConflict(ScheduleItem first, ScheduleItem second) =>
    feederScheduleMinutes(first) == feederScheduleMinutes(second) &&
    overlappingFeederDays(first.days, second.days).isNotEmpty;

String feederScheduleConflictMessage(
  ScheduleItem requested,
  ScheduleItem existing,
) {
  final days = overlappingFeederDays(
    requested.days,
    existing.days,
  ).map((index) => feederDayNames[index]).join(', ');
  return 'A feeding schedule already exists for $days at '
      '${requested.time} ${requested.ampm}. Please select a different day or time, or edit the existing schedule.';
}

class FeederScheduleConflictException implements Exception {
  final ScheduleItem requested;
  final ScheduleItem existing;

  const FeederScheduleConflictException(this.requested, this.existing);

  String get message => feederScheduleConflictMessage(requested, existing);

  @override
  String toString() => message;
}

/// Converts a 12-hour feeder schedule into minutes after midnight.
int feederScheduleMinutes(ScheduleItem schedule) {
  final parts = schedule.time.split(':');
  var hour = int.tryParse(parts.first) ?? 6;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  if (schedule.ampm == 'PM' && hour != 12) hour += 12;
  if (schedule.ampm == 'AM' && hour == 12) hour = 0;
  return hour * 60 + minute;
}

/// Returns true when [schedule] was already effective at the supplied Manila
/// wall-clock occurrence. Legacy schedules without an effective timestamp are
/// treated as existing, preserving their previous behavior.
bool feederScheduleWasEffectiveAt(
  ScheduleItem schedule,
  DateTime occurrence,
) {
  final effectiveAt = schedule.effectiveAt;
  if (effectiveAt == null) return true;
  final effectiveManila = manilaWallClock(effectiveAt);
  return !effectiveManila.isAfter(occurrence);
}

/// Whether an enabled schedule runs on [date]. The mask is Sunday-first.
/// Older/malformed records without a complete mask retain the legacy
/// every-day behavior.
bool feederScheduleRunsOnDate(ScheduleItem schedule, DateTime date) {
  if (!schedule.enabled) return false;
  if (schedule.days.length < 7) return true;
  final dayIndex = date.weekday % 7; // Sunday=0, Monday=1, ... Saturday=6.
  return schedule.days[dayIndex] == '1';
}

/// Finds the next enabled repeat-day occurrence, including the same day when
/// its configured time has not passed. Returns null when no day is enabled.
DateTime? nextFeederScheduleOccurrence(
  ScheduleItem schedule,
  DateTime now, {
  bool skipToday = false,
}) {
  if (!schedule.enabled) return null;
  final minutes = feederScheduleMinutes(schedule);
  final hour = minutes ~/ 60;
  final minute = minutes % 60;
  final today = DateTime(now.year, now.month, now.day);

  // Seven repeat days plus today covers the next weekly occurrence even when
  // today's instance has already completed.
  for (var dayOffset = 0; dayOffset <= 7; dayOffset++) {
    if (skipToday && dayOffset == 0) continue;
    final date = today.add(Duration(days: dayOffset));
    if (!feederScheduleRunsOnDate(schedule, date)) continue;
    final candidate = DateTime(date.year, date.month, date.day, hour, minute);
    if (!candidate.isBefore(now)) return candidate;
  }
  return null;
}

class ScheduledFeedOccurrence {
  final ScheduleItem schedule;
  final DateTime at;

  const ScheduledFeedOccurrence(this.schedule, this.at);
}

/// Selects the nearest occurrence across any number of schedule times and
/// repeat-day combinations. Disabled schedules are ignored automatically.
ScheduledFeedOccurrence? nextEnabledFeeding(
  Iterable<ScheduleItem> schedules,
  DateTime now, {
  bool Function(ScheduleItem schedule)? skipToday,
}) {
  ScheduledFeedOccurrence? nearest;
  for (final schedule in schedules) {
    final occurrence = nextFeederScheduleOccurrence(
      schedule,
      now,
      skipToday: skipToday?.call(schedule) ?? false,
    );
    if (occurrence == null) continue;
    if (nearest == null || occurrence.isBefore(nearest.at)) {
      nearest = ScheduledFeedOccurrence(schedule, occurrence);
    }
  }
  return nearest;
}

class LogEntry {
  final String action;
  final String type;
  final String time;
  final String date;
  final int timestamp;
  final String? scheduleKey;
  final String? scheduleTime;

  LogEntry(
    this.action,
    this.type,
    this.time,
    this.date, {
    this.timestamp = 0,
    this.scheduleKey,
    this.scheduleTime,
  });
}

class FeedState {
  static final schedules = ValueNotifier<List<ScheduleItem>>([]);
  static final feederLogs = ValueNotifier<List<LogEntry>>([]);
}
