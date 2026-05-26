enum NotificationType { critical, warning, operational, reminder }

class NotificationItem {
  final String id;
  final NotificationType type;
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

  String get typeString {
    switch (type) {
      case NotificationType.critical: return 'critical';
      case NotificationType.warning: return 'warning';
      case NotificationType.operational: return 'operational';
      case NotificationType.reminder: return 'reminder';
    }
  }
}
