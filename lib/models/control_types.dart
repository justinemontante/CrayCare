import 'package:flutter/foundation.dart';

class ScheduleItem {
  final String time;
  final String ampm;
  final bool enabled;
  ScheduleItem(this.time, this.ampm, {this.enabled = true});
}

class LogEntry {
  final String action;
  final String type;
  final String time;
  final String date;
  LogEntry(this.action, this.type, this.time, this.date);
}

class FeedState {
  static final schedules = ValueNotifier<List<ScheduleItem>>([]);
  static final feederLogs = ValueNotifier<List<LogEntry>>([]);
}
