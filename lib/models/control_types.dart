import 'package:flutter/foundation.dart';

const manilaUtcOffset = Duration(hours: 8);
const defaultFeederGrams = 20.0;

/// Matches the fixed-cycle production firmware; never silently round a dose up.
String? validateFeederGrams(double? grams) {
  final amount = grams ?? defaultFeederGrams;
  if (!amount.isFinite || amount < 20 || amount > 200 || amount % 20 != 0) {
    return 'Use 20–200 g in steps of 20 g (estimated per servo cycle).';
  }
  return null;
}

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
  final String? lastOutcome;
  final DateTime? lastOccurrenceAt;

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
    this.lastOutcome,
    this.lastOccurrenceAt,
  });
}

/// Date-scoped terminal outcome. Legacy isDone alone is not proof of dispensing.
String? feederOutcomeOnDate(ScheduleItem schedule, DateTime date) {
  final instant = schedule.lastOccurrenceAt;
  if (instant == null) return null;
  final at = manilaWallClock(instant);
  if (at.year != date.year ||
      at.month != date.month ||
      at.day != date.day ||
      at.hour * 60 + at.minute != feederScheduleMinutes(schedule) ||
      !feederScheduleWasEffectiveAt(schedule, at)) {
    return null;
  }
  return switch (schedule.lastOutcome) {
    'completed' => 'completed',
    'skipped_insufficient' || 'blocked' => 'skipped',
    'failed' => 'failed',
    _ => null,
  };
}

/// Prefer explicit, occurrence-linked device outcomes over inferred missed logs.
String? feederRecordedOutcome(
  ScheduleItem schedule,
  DateTime date,
  Iterable<LogEntry> logs,
) {
  final stored = feederOutcomeOnDate(schedule, date);
  if (stored != null) return stored;
  for (final log in logs) {
    if (log.timestamp <= 0 || log.type != 'auto') continue;
    final at = manilaWallClock(
      DateTime.fromMillisecondsSinceEpoch(
        log.occurrenceTimestamp ?? log.timestamp,
        isUtc: true,
      ),
    );
    if (at.year != date.year || at.month != date.month || at.day != date.day) {
      continue;
    }
    if (!feederScheduleWasEffectiveAt(schedule, at)) continue;
    final time = '${schedule.time} ${schedule.ampm}';
    if (log.scheduleKey != null) {
      if (log.scheduleKey != schedule.id || log.scheduleTime != time) continue;
    } else if (log.time != time) {
      continue;
    }
    final outcome = switch (log.status) {
      'completed' => 'completed',
      'skipped_insufficient' || 'blocked' => 'skipped',
      'failed' => 'failed',
      _ => null,
    };
    if (outcome != null) return outcome;
    if (log.status == null &&
        (log.action.toLowerCase().contains('dispensed feed (scheduled)') ||
            log.action.toLowerCase().contains('auto feed dispensed'))) {
      return 'completed';
    }
  }
  return null;
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
bool feederScheduleWasEffectiveAt(ScheduleItem schedule, DateTime occurrence) {
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
    if (!feederScheduleWasEffectiveAt(schedule, candidate) ||
        feederOutcomeOnDate(schedule, date) != null) {
      continue;
    }
    if (!candidate.isBefore(now)) return candidate;
  }
  return null;
}

class ScheduledFeedOccurrence {
  final ScheduleItem schedule;
  final DateTime at;

  const ScheduledFeedOccurrence(this.schedule, this.at);
}

enum ManualFeedScheduleGuardLevel { clear, warning, blocked }

class ManualFeedScheduleGuard {
  final ManualFeedScheduleGuardLevel level;
  final ScheduleItem? schedule;
  final DateTime? occurrence;

  const ManualFeedScheduleGuard._(this.level, this.schedule, this.occurrence);

  const ManualFeedScheduleGuard.clear()
    : this._(ManualFeedScheduleGuardLevel.clear, null, null);

  bool get isBlocked => level == ManualFeedScheduleGuardLevel.blocked;
  bool get needsConfirmation => level == ManualFeedScheduleGuardLevel.warning;
}

/// Protects a manual Feed Now request from colliding with an enabled automatic
/// schedule. The scheduled minute and the final minute before it are blocked;
/// the surrounding 15-minute window requires owner confirmation.
ManualFeedScheduleGuard manualFeedScheduleGuard(
  Iterable<ScheduleItem> schedules,
  DateTime now, {
  Duration warningWindow = const Duration(minutes: 15),
}) {
  ManualFeedScheduleGuard? nearestWarning;
  Duration? nearestDistance;

  for (final schedule in schedules) {
    if (!schedule.enabled) continue;
    final minutes = feederScheduleMinutes(schedule);
    for (var dayOffset = -1; dayOffset <= 1; dayOffset++) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: dayOffset));
      if (!feederScheduleRunsOnDate(schedule, date)) continue;
      final occurrence = DateTime(
        date.year,
        date.month,
        date.day,
        minutes ~/ 60,
        minutes % 60,
      );
      if (!feederScheduleWasEffectiveAt(schedule, occurrence)) continue;

      final sameScheduledMinute =
          occurrence.year == now.year &&
          occurrence.month == now.month &&
          occurrence.day == now.day &&
          occurrence.hour == now.hour &&
          occurrence.minute == now.minute;
      final untilSchedule = occurrence.difference(now);
      if (sameScheduledMinute ||
          (!untilSchedule.isNegative &&
              untilSchedule <= const Duration(minutes: 1))) {
        return ManualFeedScheduleGuard._(
          ManualFeedScheduleGuardLevel.blocked,
          schedule,
          occurrence,
        );
      }

      final distance = untilSchedule.abs();
      if (distance <= warningWindow &&
          (nearestDistance == null || distance < nearestDistance)) {
        nearestDistance = distance;
        nearestWarning = ManualFeedScheduleGuard._(
          ManualFeedScheduleGuardLevel.warning,
          schedule,
          occurrence,
        );
      }
    }
  }

  return nearestWarning ?? const ManualFeedScheduleGuard.clear();
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
  final String? commandId;
  final String action;
  final String type;
  final String time;
  final String date;
  final int timestamp;
  final String? scheduleKey;
  final String? scheduleTime;
  final String? status;
  final double? requestedGrams;
  final double? estimatedDispensedGrams;
  final int? occurrenceTimestamp;
  final double? estimatedAvailableGrams;
  final double? feedLevelBefore;
  final double? feedLevelAfter;
  final bool? levelChangeDetected;

  LogEntry(
    this.action,
    this.type,
    this.time,
    this.date, {
    this.timestamp = 0,
    this.commandId,
    this.scheduleKey,
    this.scheduleTime,
    this.status,
    this.requestedGrams,
    this.estimatedDispensedGrams,
    this.occurrenceTimestamp,
    this.estimatedAvailableGrams,
    this.feedLevelBefore,
    this.feedLevelAfter,
    this.levelChangeDetected,
  });
}

/// Only a response for this exact request can finish a manual progress panel.
String? manualFeedingOutcome({
  required String? commandId,
  required String? statusCommandId,
  required String status,
  required Iterable<LogEntry> logs,
}) {
  if (commandId == null || commandId.isEmpty) return null;
  const terminal = {'completed', 'blocked', 'skipped_insufficient', 'failed'};
  for (final log in logs) {
    if (log.commandId == commandId && terminal.contains(log.status)) {
      return log.status;
    }
  }
  return statusCommandId == commandId && terminal.contains(status)
      ? status
      : null;
}

class FeedState {
  static final schedules = ValueNotifier<List<ScheduleItem>>([]);
  static final feederLogs = ValueNotifier<List<LogEntry>>([]);
}
