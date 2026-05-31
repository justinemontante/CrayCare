class NotificationItem {
  final String id;
  final String type;
  final String title;
  final String message;
  final DateTime timestamp;
  bool unread;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.unread = true,
  });
}
