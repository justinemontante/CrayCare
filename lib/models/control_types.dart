class ScheduleItem {
  final String time;
  final String ampm;
  final int grams;
  ScheduleItem(this.time, this.ampm, this.grams);
}

class LogEntry {
  final String action;
  final String type;
  final String time;
  final String date;
  LogEntry(this.action, this.type, this.time, this.date);
}
