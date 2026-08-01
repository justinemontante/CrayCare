// ignore_for_file: non_constant_identifier_names

class NotificationItem {
  final String id;
  final String notif_type;
  final String title;
  final String body;
  final DateTime created_at;
  bool is_read;

  NotificationItem({
    required this.id,
    required this.notif_type,
    required this.title,
    required this.body,
    required this.created_at,
    this.is_read = false,
  });

  bool isUnreadBy(String uid) => !is_read;
}
