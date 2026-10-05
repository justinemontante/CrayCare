import 'package:craycare/models/notification_item.dart';
import 'package:craycare/utils/notification_snapshot_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationItem _notification(String id) => NotificationItem(
  id: id,
  notif_type: 'operational',
  title: id,
  body: 'Test notification',
  created_at: DateTime.utc(2026, 10, 4),
);

void main() {
  group('reconcileNotificationsForSnapshot', () {
    test('keeps cached items when an offline snapshot may be incomplete', () {
      final result = reconcileNotificationsForSnapshot(
        current: [_notification('cached-old'), _notification('cached-current')],
        snapshotIds: ['cached-current'],
        isFromCache: true,
      );

      expect(result.map((item) => item.id), ['cached-old', 'cached-current']);
    });

    test('removes stale items missing from a server-confirmed snapshot', () {
      final result = reconcileNotificationsForSnapshot(
        current: [_notification('deleted'), _notification('still-present')],
        snapshotIds: ['still-present'],
        isFromCache: false,
      );

      expect(result.map((item) => item.id), ['still-present']);
    });

    test('clears all items when the server-confirmed collection is empty', () {
      final result = reconcileNotificationsForSnapshot(
        current: [_notification('deleted-1'), _notification('deleted-2')],
        snapshotIds: const [],
        isFromCache: false,
      );

      expect(result, isEmpty);
    });
  });
}
