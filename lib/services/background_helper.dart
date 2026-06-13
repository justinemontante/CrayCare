import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackgroundHelper {
  static const _notifChannelId = 'craycare_alerts';
  static const _notifChannelName = 'CrayCare Alerts';
  static const _notifChannelDesc = 'Sensor threshold alerts';

  static String get _userId => FirebaseAuth.instance.currentUser?.uid ?? '';

  static Future<void> checkAndDispatchFeeding() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final db = FirebaseDatabase.instance;
    final now = DateTime.now();
    final todayKey = '${now.month}/${now.day}';

    final schedSnap = await db.ref('feeder/schedules').get();
    if (!schedSnap.exists) return;
    final schedData = schedSnap.value;
    if (schedData is! Map) return;

    for (final entry in schedData.entries) {
      final s = entry.value;
      if (s is! Map) continue;
      if (s['enabled'] != true) continue;

      final time = s['time'] as String? ?? '6:00';
      final ampm = s['ampm'] as String? ?? 'AM';
      int h = int.parse(time.split(':')[0]);
      final m = int.parse(time.split(':')[1]);
      if (ampm == 'PM' && h != 12) h += 12;
      if (ampm == 'AM' && h == 12) h = 0;

      final schedMins = h * 60 + m;
      final nowMins = now.hour * 60 + now.minute;

      if (nowMins < schedMins || nowMins > schedMins + 15) continue;

      final dispatchedKey = '${entry.key}';
      final marker = await db
          .ref('users/$uid/feeder/dispatched/$todayKey/$dispatchedKey')
          .get();
      if (marker.exists) continue;

      await db.ref('feeder/commands').push().set({
        'action': 'feed_now',
        'timestamp': ServerValue.timestamp,
        'source': 'background',
      });

      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      final ampmStr = h >= 12 ? 'PM' : 'AM';
      final timeStr = '$h12:${m.toString().padLeft(2, '0')} $ampmStr';
      final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';

      await db.ref('feeder/logs').push().set({
        'action': 'Auto feed dispensed',
        'type': 'auto',
        'time': timeStr,
        'date': dateStr,
        'timestamp': now.millisecondsSinceEpoch,
      });

      await db.ref('feeder/dispatched/$todayKey/$dispatchedKey').set(true);

      debugPrint('[BackgroundHelper] Dispatched feed for $time $ampm');
    }
  }

  static Future<void> showPendingNotifications() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final db = FirebaseDatabase.instance;
    final now = DateTime.now();
    final todayKey = '${now.month}/${now.day}';
    final nowMins = now.hour * 60 + now.minute;

    final schedSnap = await db.ref('feeder/schedules').get();
    if (!schedSnap.exists) return;
    final schedData = schedSnap.value;
    if (schedData is! Map) return;

    final localNotif = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await localNotif.initialize(const InitializationSettings(
      android: androidSettings,
    ));

    for (final entry in schedData.entries) {
      final s = entry.value;
      if (s is! Map || s['enabled'] != true) continue;

      final time = s['time'] as String? ?? '6:00';
      final ampm = s['ampm'] as String? ?? 'AM';
      int h = int.parse(time.split(':')[0]);
      final m = int.parse(time.split(':')[1]);
      if (ampm == 'PM' && h != 12) h += 12;
      if (ampm == 'AM' && h == 12) h = 0;

      final schedMins = h * 60 + m;
      final reminderKey = 'reminder_${todayKey}_${entry.key}';
      final confirmKey = 'confirm_${todayKey}_${entry.key}';

      final reminderMarker = await db
          .ref('users/$uid/notifications/markers/$reminderKey')
          .get();
      final confirmMarker = await db
          .ref('users/$uid/notifications/markers/$confirmKey')
          .get();

      if (!reminderMarker.exists && nowMins == schedMins - 1) {
        await localNotif.show(
          '${now.millisecondsSinceEpoch}_reminder'.hashCode,
          'Feeding Reminder',
          'Scheduled feeding at $time $ampm starts in 1 minute.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _notifChannelId,
              _notifChannelName,
              channelDescription: _notifChannelDesc,
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
        await db.ref('users/$uid/notifications/markers/$reminderKey').set(true);
      }

      if (!confirmMarker.exists && nowMins > schedMins && nowMins <= schedMins + 15) {
        final dispatchedMarker = '${entry.key}';
        final dispatched = await db
            .ref('feeder/dispatched/$todayKey/$dispatchedMarker')
            .get();
        if (dispatched.exists) {
          await localNotif.show(
            '${now.millisecondsSinceEpoch}_confirm'.hashCode,
            'Feeding Complete',
            'Feed has been dispensed successfully.',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                _notifChannelId,
                _notifChannelName,
                channelDescription: _notifChannelDesc,
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
          await db.ref('users/$uid/notifications/markers/$confirmKey').set(true);
        }
      }
    }
  }

  static Future<void> checkSamplingReminders() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final db = FirebaseDatabase.instance;
    final now = DateTime.now();
    final todayKey = '${now.month}/${now.day}';
    final markerKey = 'sampling_reminder_$todayKey';

    final marker = await db.ref('users/$uid/notifications/markers/$markerKey').get();
    if (marker.exists) return;

    final tankSnap = await db.ref('users/$uid/tank/config').get();
    if (!tankSnap.exists) return;
    final tank = tankSnap.value;
    if (tank is! Map) return;

    final isInitialized = tank['isInitialized'] as bool? ?? false;
    if (!isInitialized) return;

    final stockingDate = tank['stockingDate'] as int? ?? 0;
    final sampleCount = tank['sampleCount'] as int? ?? 0;
    final daysSince = stockingDate > 0
        ? now.difference(DateTime.fromMillisecondsSinceEpoch(stockingDate)).inDays
        : 999;

    if (daysSince >= 7 && sampleCount > 0) {
      final localNotif = FlutterLocalNotificationsPlugin();
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      await localNotif.initialize(const InitializationSettings(
        android: androidSettings,
      ));

      await localNotif.show(
        '${now.millisecondsSinceEpoch}_sampling'.hashCode,
        'Sampling Reminder',
        "It's been $daysSince days since last sampling. Time to record growth data!",
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _notifChannelId,
            _notifChannelName,
            channelDescription: _notifChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );

      await db.ref('users/$uid/notifications/markers/$markerKey').set(true);
    }
  }
}
