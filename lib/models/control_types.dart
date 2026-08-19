import 'package:flutter/foundation.dart';

class ScheduleItem {
  final String time;
  final String ampm;
  final bool enabled;
  final bool isDone;
  final double? grams;

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
  });
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
  LogEntry(this.action, this.type, this.time, this.date, {this.timestamp = 0});
}

class FeedState {
  static final schedules = ValueNotifier<List<ScheduleItem>>([]);
  static final feederLogs = ValueNotifier<List<LogEntry>>([]);
}
