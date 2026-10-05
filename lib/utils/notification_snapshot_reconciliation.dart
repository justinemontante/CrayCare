import '../models/notification_item.dart';

/// Retains cached notifications until Firestore confirms a complete server
/// snapshot, then removes items whose documents no longer exist in the query.
List<NotificationItem> reconcileNotificationsForSnapshot({
  required Iterable<NotificationItem> current,
  required Iterable<String> snapshotIds,
  required bool isFromCache,
}) {
  final items = current.toList();
  if (isFromCache) return items;

  final visibleIds = snapshotIds.toSet();
  return items.where((item) => visibleIds.contains(item.id)).toList();
}
