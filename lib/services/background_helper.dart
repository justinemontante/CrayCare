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
    final todayKey = '${now.year}-${now.month}-${now.day}';

    final schedSnap = await db.ref('feeder/schedules').get();
    if (!schedSnap.exists) return;
    final schedData = schedSnap.value;
    if (schedData is! Map) return;

    // Check feed safety before dispatching any scheduled feed
    final latestSnap = await db.ref('sensor_readings/latest').get();
    bool feedSafe = true;
    String blockReason = '';
    if (latestSnap.exists && latestSnap.value is Map) {
      final latest = Map<String, dynamic>.from(latestSnap.value as Map);
      final turbAir = latest['turbidityAir'] == true;
      final turb = (latest['turbidity'] as num?)?.toDouble() ?? 0.0;

      final rangesSnap = await db.ref('sensor_readings/config/ranges/turb').get();
      double turbMax = 25.0;
      if (rangesSnap.exists && rangesSnap.value is Map) {
        final r = Map<String, dynamic>.from(rangesSnap.value as Map);
        turbMax = (r['max'] as num?)?.toDouble() ?? 25.0;
      }

      if (turbAir) {
        feedSafe = false;
        blockReason = 'turbidity sensor in air';
      } else if (turb > turbMax) {
        feedSafe = false;
        blockReason = 'turbidity too high (${turb.toStringAsFixed(0)} > ${turbMax.toStringAsFixed(0)} NTU)';
      }
    }

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
          .ref('feeder/dispatched/$todayKey/$dispatchedKey')
          .get();
      if (marker.exists) continue;

      if (!feedSafe) {
        final months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
        final ampmStr = h >= 12 ? 'PM' : 'AM';
        final timeStr = '$h12:${m.toString().padLeft(2, '0')} $ampmStr';
        final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';

        await db.ref('feeder/logs').push().set({
          'action': 'Scheduled feed skipped: $blockReason',
          'type': 'skipped',
          'time': timeStr,
          'date': dateStr,
          'timestamp': now.millisecondsSinceEpoch,
        });
        debugPrint('[BackgroundHelper] Skipped feed for $time $ampm: $blockReason');
        continue;
      }

      final grams = (s['grams'] as num?)?.toDouble();

      final Map<String, dynamic> cmd = {
        'action': 'feed_now',
        'timestamp': ServerValue.timestamp,
        'source': 'background',
      };
      if (grams != null) {
        cmd['grams'] = grams;
      }
      await db.ref('feeder/commands').push().set(cmd);

      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      final ampmStr = h >= 12 ? 'PM' : 'AM';
      final timeStr = '$h12:${m.toString().padLeft(2, '0')} $ampmStr';
      final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';

      await db.ref('feeder/logs').push().set({
        'action': 'Auto feed dispensed$gramsStr',
        'type': 'auto',
        'time': timeStr,
        'date': dateStr,
        'timestamp': now.millisecondsSinceEpoch,
      });

      await db.ref('feeder/dispatched/$todayKey/$dispatchedKey').set(true);

      debugPrint('[BackgroundHelper] Dispatched feed for $time $ampm$gramsStr');
    }
  }

  static Future<void> showPendingNotifications() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final db = FirebaseDatabase.instance;

    final profileSnap = await db.ref('users/$uid/profile').get();
    final profile = profileSnap.value is Map ? profileSnap.value as Map : {};
    final ownerUid = profile['ownerUid'] as String?;
    final notifTargetUid = (ownerUid != null && ownerUid.isNotEmpty) ? ownerUid : uid;

    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
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
          .ref('users/$notifTargetUid/notifications/markers/$reminderKey')
          .get();
      final confirmMarker = await db
          .ref('users/$notifTargetUid/notifications/markers/$confirmKey')
          .get();

      // Read user preference for feeding notification
      final prefsSnap = await db.ref('users/$notifTargetUid/notifPrefs').get();
      final prefs = prefsSnap.value is Map ? prefsSnap.value as Map : {};
      final isFeedingEnabled = prefs['feeding'] != false;

      if (isFeedingEnabled && !reminderMarker.exists && nowMins >= schedMins - 15 && nowMins < schedMins) {
        final msg = 'Your feeding schedule at $time $ampm will be dispensed in 5 minutes.';
        await localNotif.show(
          '${now.millisecondsSinceEpoch}_reminder'.hashCode,
          'Feeding Reminder',
          msg,
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
        await db.ref('users/$notifTargetUid/notifications/markers/$reminderKey').set(true);
      }

      if (isFeedingEnabled && !confirmMarker.exists && nowMins > schedMins && nowMins <= schedMins + 15) {
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
          await db.ref('users/$notifTargetUid/notifications/markers/$confirmKey').set(true);
        }
      }
    }
  }

  static Future<void> checkSamplingReminders() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final db = FirebaseDatabase.instance;
    final now = DateTime.now();

    // Check if current user is a monitor, read owner's tank data
    final profileSnap = await db.ref('users/$uid/profile').get();
    final profile = profileSnap.value is Map ? profileSnap.value as Map : {};
    final ownerUid = profile['ownerUid'] as String?;
    final tankOwnerUid = (ownerUid != null && ownerUid.isNotEmpty) ? ownerUid : uid;

    final tankSnap = await db.ref('tank_data/$tankOwnerUid/inventory').get();
    if (!tankSnap.exists) return;
    final tank = tankSnap.value;
    if (tank is! Map) return;

    final isInitialized = tank['isInitialized'] as bool? ?? false;
    if (!isInitialized) return;

    final int lastSampleTs;
    if (tank.containsKey('lastSampleDate')) {
      lastSampleTs = tank['lastSampleDate'] as int;
    } else {
      lastSampleTs = tank['stockingDate'] as int? ?? 0;
    }
    if (lastSampleTs <= 0) return;

    final lastSampleDate = DateTime.fromMillisecondsSinceEpoch(lastSampleTs);
    final daysSince = now.difference(lastSampleDate).inDays;

    if (daysSince < 7) return;

    const markerKey = 'sampling_reminder';
    final marker = await db.ref('users/$tankOwnerUid/notifications/markers/$markerKey').get();
    if (marker.exists) {
      final lastReminderTs = marker.value is int ? marker.value as int : 0;
      if (lastReminderTs > 0) {
        final lastReminder = DateTime.fromMillisecondsSinceEpoch(lastReminderTs);
        if (now.difference(lastReminder).inDays < 7) return;
      }
    }

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

    await db.ref('users/$tankOwnerUid/notifications/markers/$markerKey')
        .set(now.millisecondsSinceEpoch);
  }
}
