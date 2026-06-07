import 'package:flutter/foundation.dart';

class ScheduleItem {
  final String time;
  final String ampm;
  final bool enabled;
  final String? createdBy;
  ScheduleItem(this.time, this.ampm, {this.enabled = true, this.createdBy});
}

class LogEntry {
  final String action;
  final String type;
  final String time;
  final String date;
  final String userName;
  final int timestamp;
  LogEntry(this.action, this.type, this.time, this.date,
      {this.userName = '', this.timestamp = 0});
}

class FeedState {
  static final schedules = ValueNotifier<List<ScheduleItem>>([]);
  static final feederLogs = ValueNotifier<List<LogEntry>>([]);
}
