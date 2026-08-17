import 'package:flutter/foundation.dart';

class ScheduleItem {
  final String time;
  final String ampm;
  final bool enabled;
  final bool isDone;
  final double? grams;

  /// Day-of-week mask, Monday first: "1111111" = every day,
  /// "1010100" = Mon/Wed/Fri only. Each char is '1' (on) or '0' (off).
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

class LogEntry {
  final String action;
  final String type;
  final String time;
  final String date;
  final int timestamp;
  LogEntry(this.action, this.type, this.time, this.date,
      {this.timestamp = 0});
}

class FeedState {
  static final schedules = ValueNotifier<List<ScheduleItem>>([]);
  static final feederLogs = ValueNotifier<List<LogEntry>>([]);
}
