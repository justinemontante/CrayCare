class NotificationItem {
  final String id;
  final String type;
  final String title;
  final String message;
  final DateTime timestamp;
  Map<String, bool> readBy;

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    Map<String, bool>? readBy,
  }) : readBy = readBy ?? {};

  bool isUnreadBy(String uid) => uid.isEmpty || !readBy.containsKey(uid) || readBy[uid] != true;
}
