import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Background feeding/notification checks. Migrated to the new Firestore
/// structure: everything feeder/sensor related now lives under
/// tanks/{tank_id}/..., and notif prefs/markers under users/{uid}/....
class BackgroundHelper {
  static const _notifChannelId = 'craycare_alerts';
  static const _notifChannelName = 'CrayCare Alerts';
  static const _notifChannelDesc = 'Sensor threshold alerts';

  static String get _userId => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Resolves tank_id from the user's profile (tanks/{tank_id}). Falls back
  /// to uid if the profile lookup fails, since tank_id == uid in this app.
  static Future<String?> _resolveTankId(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return doc.data()?['tank_id'] as String? ?? uid;
    } catch (_) {
      return uid;
    }
  }

  // Background tasks run on the device's local clock, but all schedule times
  // and Firestore date-keys are expressed in Asia/Manila wall-clock time (UTC+8)
  // to match FeederService._manilaNow() and the Cloud Function. Using
  // DateTime.now() here would cause missed-schedule mismatches for users
  // outside UTC+8.
  static const _manilaOffset = Duration(hours: 8);
  static DateTime _manilaTime() => DateTime.now().toUtc().add(_manilaOffset);

  static Future<void> checkAndDispatchFeeding() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final tankId = await _resolveTankId(uid);
    if (tankId == null) return;
    final fs = FirebaseFirestore.instance;
    final tankDoc = fs.collection('tanks').doc(tankId);
    final now = _manilaTime();
    final todayKey = '${now.year}-${now.month}-${now.day}';

    // tanks/{tank_id}/feeder_schedules
    final schedSnap = await tankDoc.collection('feeder_schedules').get();
    if (schedSnap.docs.isEmpty) return;
    final schedDocs = schedSnap.docs;

    // tanks/{tank_id}/sensor_readings/latest
    final latestSnap = await tankDoc.collection('sensor_readings').doc('latest').get();
    bool feedSafe = true;
    String blockReason = '';
    if (latestSnap.exists && latestSnap.data() != null) {
      final latest = latestSnap.data()!;
      final turbAir = latest['turbidity_air'] == true || latest['turbidityAir'] == true;
      final turb = (latest['turbidity'] as num?)?.toDouble() ?? 0.0;

      // tanks/{tank_id}/sensors/turbidity — new per-sensor threshold doc.
      double turbMax = 25.0;
      final configSnap = await tankDoc.collection('sensors').doc('turbidity').get();
      if (configSnap.exists && configSnap.data() != null) {
        final config = configSnap.data()!;
        turbMax = (config['max_value'] as num?)?.toDouble() ?? 25.0;
      }

      if (turbAir) {
        feedSafe = false;
        blockReason = 'turbidity sensor in air';
      } else if (turb > turbMax) {
        feedSafe = false;
        blockReason = 'turbidity too high (${turb.toStringAsFixed(0)} > ${turbMax.toStringAsFixed(0)} NTU)';
      }
    }

    for (final doc in schedDocs) {
      final s = doc.data();
      if (s['enabled'] != true && s['is_active'] != true) continue;

      final time = s['time'] as String? ?? s['feed_time'] as String? ?? '6:00';
      final ampm = s['ampm'] as String? ?? 'AM';
      int h = int.parse(time.split(':')[0]);
      final m = int.parse(time.split(':')[1]);
      if (ampm == 'PM' && h != 12) h += 12;
      if (ampm == 'AM' && h == 12) h = 0;

      final schedMins = h * 60 + m;
      final nowMins = now.hour * 60 + now.minute;

      if (nowMins < schedMins || nowMins > schedMins + 15) continue;

      final dispatchedKey = doc.id;
      // tanks/{tank_id}/feeder_dispatched/{dateKey}
      final dispatchedDoc = await tankDoc
          .collection('feeder_dispatched')
          .doc(todayKey)
          .get();
      final dispatchedData = dispatchedDoc.data();
      if (dispatchedData != null && dispatchedData[dispatchedKey] == true) continue;

      if (!feedSafe) {
        final months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
        final ampmStr = h >= 12 ? 'PM' : 'AM';
        final timeStr = '$h12:${m.toString().padLeft(2, '0')} $ampmStr';
        final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';

        // tanks/{tank_id}/feeder_logs
        await tankDoc.collection('feeder_logs').add({
          'action': 'Scheduled feed skipped: $blockReason',
          'type': 'skipped',
          'time': timeStr,
          'date': dateStr,
          'timestamp': now.millisecondsSinceEpoch,
          'logged_at': FieldValue.serverTimestamp(),
        });
        debugPrint('[BackgroundHelper] Skipped feed for $time $ampm: $blockReason');
        continue;
      }

      final grams = (s['grams'] as num?)?.toDouble() ?? (s['portion_grams'] as num?)?.toDouble();

      final Map<String, dynamic> cmd = {
        'command_type': 'feed_now',
        'trigger_type': 'scheduled',
        'status': 'pending',
        'issued_by': uid,
        'issued_at': FieldValue.serverTimestamp(),
        // legacy fields kept for firmware compatibility during rollout
        'action': 'feed_now',
        'timestamp': FieldValue.serverTimestamp(),
        'source': 'background',
      };
      if (grams != null) {
        cmd['grams'] = grams;
      }
      // tanks/{tank_id}/pending_commands
      await tankDoc.collection('pending_commands').add(cmd);

      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      final ampmStr = h >= 12 ? 'PM' : 'AM';
      final timeStr = '$h12:${m.toString().padLeft(2, '0')} $ampmStr';
      final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';

      await tankDoc.collection('feeder_logs').add({
        'action': 'Auto feed dispensed$gramsStr',
        'type': 'auto',
        'time': timeStr,
        'date': dateStr,
        'timestamp': now.millisecondsSinceEpoch,
        'logged_at': FieldValue.serverTimestamp(),
      });

      await tankDoc.collection('feeder_dispatched').doc(todayKey).set({
        dispatchedKey: true,
      }, SetOptions(merge: true));

      debugPrint('[BackgroundHelper] Dispatched feed for $time $ampm$gramsStr');
    }
  }

  static Future<void> showPendingNotifications() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final tankId = await _resolveTankId(uid);
    if (tankId == null) return;
    final fs = FirebaseFirestore.instance;
    final tankDoc = fs.collection('tanks').doc(tankId);
    final userDoc = fs.collection('users').doc(uid);
    final now = _manilaTime();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    final nowMins = now.hour * 60 + now.minute;

    final schedSnap = await tankDoc.collection('feeder_schedules').get();
    if (schedSnap.docs.isEmpty) return;
    final schedDocs = schedSnap.docs;

    final localNotif = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await localNotif.initialize(const InitializationSettings(
      android: androidSettings,
    ));

    for (final doc in schedDocs) {
      final s = doc.data();
      if (s['enabled'] != true && s['is_active'] != true) continue;

      final time = s['time'] as String? ?? s['feed_time'] as String? ?? '6:00';
      final ampm = s['ampm'] as String? ?? 'AM';
      int h = int.parse(time.split(':')[0]);
      final m = int.parse(time.split(':')[1]);
      if (ampm == 'PM' && h != 12) h += 12;
      if (ampm == 'AM' && h == 12) h = 0;

      final schedMins = h * 60 + m;
      final reminderKey = 'reminder_${todayKey}_${doc.id}';
      final confirmKey = 'confirm_${todayKey}_${doc.id}';

      // users/{uid}/notif_markers/{key} — no more uid prefix, path scopes it.
      final reminderMarker = await userDoc.collection('notif_markers').doc(reminderKey).get();
      final confirmMarker = await userDoc.collection('notif_markers').doc(confirmKey).get();

      // users/{uid}/notification_settings/preferences
      final prefsDoc = await userDoc.collection('notification_settings').doc('preferences').get();
      final prefs = prefsDoc.data();
      final isFeedingEnabled = prefs == null || prefs['feeding'] != false;

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
        await userDoc.collection('notif_markers').doc(reminderKey).set(
            {'markerKey': reminderKey, 'value': true, 'updatedAt': FieldValue.serverTimestamp()});
      }

      if (isFeedingEnabled && !confirmMarker.exists && nowMins > schedMins && nowMins <= schedMins + 15) {
        final dispatchedDoc = await tankDoc
            .collection('feeder_dispatched')
            .doc(todayKey)
            .get();
        final dispatchedData = dispatchedDoc.data();
        if (dispatchedData != null && dispatchedData[doc.id] == true) {
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
          await userDoc.collection('notif_markers').doc(confirmKey).set(
              {'markerKey': confirmKey, 'value': true, 'updatedAt': FieldValue.serverTimestamp()});
        }
      }
    }
  }

  static Future<void> checkSamplingReminders() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final tankId = await _resolveTankId(uid);
    if (tankId == null) return;
    final now = _manilaTime();
    final fs = FirebaseFirestore.instance;
    final userDoc = fs.collection('users').doc(uid);

    Map<String, dynamic>? tank;
    try {
      // tanks/{tank_id} — not 'config', must match TankService's writes.
      final configSnap = await fs.collection('tanks').doc(tankId).get();
      if (configSnap.exists) tank = configSnap.data();
    } catch (e) {
      debugPrint('[BackgroundHelper] Failed to read tank from Firestore: $e');
    }
    if (tank == null) return;

    final isInitialized = (tank['is_initialized'] as bool?) ?? false;
    if (!isInitialized) return;

    final currentBatchId = tank['current_batch_id'] as String?;
    final fallbackStockingTs = (tank['stocking_date'] as int?) ?? 0;

    int effectiveSampleTs = 0;
    try {
      if (currentBatchId != null && currentBatchId.isNotEmpty) {
        final samplingSnap = await fs
            .collection('tanks')
            .doc(tankId)
            .collection('batches')
            .doc(currentBatchId)
            .collection('sampling_records')
            .orderBy('sampling_date', descending: true)
            .limit(1)
            .get();
        if (samplingSnap.docs.isNotEmpty) {
          effectiveSampleTs = samplingSnap.docs.first.data()['sampling_date'] as int? ?? 0;
        }
      }
      effectiveSampleTs = effectiveSampleTs > 0 ? effectiveSampleTs : fallbackStockingTs;
    } catch (e) {
      debugPrint('[BackgroundHelper] Failed to read sampling from Firestore: $e');
      effectiveSampleTs = fallbackStockingTs;
    }
    if (effectiveSampleTs <= 0) return;

    final effectiveLastDate = DateTime.fromMillisecondsSinceEpoch(effectiveSampleTs);
    final effectiveDate = DateTime(effectiveLastDate.year, effectiveLastDate.month, effectiveLastDate.day);
    final daysSince = now.difference(effectiveDate).inDays;
    if (daysSince < 7) return;

    const markerKey = 'sampling_reminder';
    // How often to re-notify while sampling is still overdue.
    const reminderIntervalHours = 4;

    // users/{uid}/notif_markers/{markerKey}
    final markerDoc = await userDoc.collection('notif_markers').doc(markerKey).get();
    bool isFirstReminder = true;

    if (markerDoc.exists && markerDoc.data() != null) {
      final data = markerDoc.data()!;
      final val = data['value'];
      if (val is Map) {
        final lastSampleTs = val['sampleTs'] as int? ?? 0;
        final lastReminderTs = val['reminderTs'] as int? ?? 0;
        if (lastSampleTs == effectiveSampleTs && lastReminderTs > 0) {
          // User has NOT sampled yet since the last reminder — keep nudging
          // every reminderIntervalHours hours instead of waiting 7 days.
          final lastReminder = DateTime.fromMillisecondsSinceEpoch(lastReminderTs);
          if (now.difference(lastReminder).inHours < reminderIntervalHours) return;
          isFirstReminder = false;
        }
        // If lastSampleTs != effectiveSampleTs the user sampled recently;
        // the daysSince < 7 guard above already returned early.
      } else if (val is int && val > 0) {
        // Legacy marker format — treat as still-pending, same interval.
        final lastReminder = DateTime.fromMillisecondsSinceEpoch(val);
        if (now.difference(lastReminder).inHours < reminderIntervalHours) return;
        isFirstReminder = false;
      }
    }

    final localNotif = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await localNotif.initialize(const InitializationSettings(
      android: androidSettings,
    ));

    // First notification: informational. Follow-ups: increasingly urgent.
    final String notifBody = isFirstReminder
        ? "It's been $daysSince days since last sampling. Time to record growth data!"
        : "Reminder: Sampling is still overdue ($daysSince days). Please record your crayfish growth data!";

    await localNotif.show(
      '${now.millisecondsSinceEpoch}_sampling'.hashCode,
      isFirstReminder ? 'Sampling Reminder' : '⚠️ Sampling Overdue',
      notifBody,
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

    await userDoc.collection('notif_markers').doc(markerKey).set({
      'markerKey': markerKey,
      'value': {
        'reminderTs': now.millisecondsSinceEpoch,
        'sampleTs': effectiveSampleTs,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
