import 'package:flutter/foundation.dart';

class ScheduleItem {
  final String time;
  final String ampm;
  final bool enabled;
  final bool isDone;
  ScheduleItem(this.time, this.ampm, {this.enabled = true, this.isDone = false});
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
