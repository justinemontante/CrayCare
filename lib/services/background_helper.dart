import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackgroundHelper {
  static const _notifChannelId = 'craycare_alerts';
  static const _notifChannelName = 'CrayCare Alerts';
  static const _notifChannelDesc = 'Sensor threshold alerts';

  static String get _userId => FirebaseAuth.instance.currentUser?.uid ?? '';

  static Future<void> checkAndDispatchFeeding() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final fs = FirebaseFirestore.instance;
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';

    final schedSnap = await fs.collection('feederSchedules').get();
    if (schedSnap.docs.isEmpty) return;
    final schedDocs = schedSnap.docs;

    final latestSnap = await fs.collection('sensorReadings').doc('latest').get();
    bool feedSafe = true;
    String blockReason = '';
    if (latestSnap.exists && latestSnap.data() != null) {
      final latest = latestSnap.data()!;
      final turbAir = latest['turbidityAir'] == true;
      final turb = (latest['turbidity'] as num?)?.toDouble() ?? 0.0;

      final configSnap = await fs.collection('config').doc(uid).get();
      double turbMax = 25.0;
      if (configSnap.exists && configSnap.data() != null) {
        final config = configSnap.data()!;
        final ranges = config['ranges'] as Map<String, dynamic>?;
        if (ranges != null) {
          final turbRange = ranges['turb'] as Map<String, dynamic>?;
          if (turbRange != null) {
            turbMax = (turbRange['max'] as num?)?.toDouble() ?? 25.0;
          }
        }
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

      final dispatchedKey = doc.id;
      final dispatchedDoc = await fs
          .collection('feederDispatched')
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

        await fs.collection('feederLogs').add({
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
        'timestamp': FieldValue.serverTimestamp(),
        'source': 'background',
      };
      if (grams != null) {
        cmd['grams'] = grams;
      }
      await fs.collection('feederCommands').add(cmd);

      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      final ampmStr = h >= 12 ? 'PM' : 'AM';
      final timeStr = '$h12:${m.toString().padLeft(2, '0')} $ampmStr';
      final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';

      await fs.collection('feederLogs').add({
        'action': 'Auto feed dispensed$gramsStr',
        'type': 'auto',
        'time': timeStr,
        'date': dateStr,
        'timestamp': now.millisecondsSinceEpoch,
      });

      await fs.collection('feederDispatched').doc(todayKey).set({
        dispatchedKey: true,
      }, SetOptions(merge: true));

      debugPrint('[BackgroundHelper] Dispatched feed for $time $ampm$gramsStr');
    }
  }

  static Future<void> showPendingNotifications() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final fs = FirebaseFirestore.instance;
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    final nowMins = now.hour * 60 + now.minute;

    final schedSnap = await fs.collection('feederSchedules').get();
    if (schedSnap.docs.isEmpty) return;
    final schedDocs = schedSnap.docs;

    final localNotif = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await localNotif.initialize(const InitializationSettings(
      android: androidSettings,
    ));

    for (final doc in schedDocs) {
      final s = doc.data();
      if (s['enabled'] != true) continue;

      final time = s['time'] as String? ?? '6:00';
      final ampm = s['ampm'] as String? ?? 'AM';
      int h = int.parse(time.split(':')[0]);
      final m = int.parse(time.split(':')[1]);
      if (ampm == 'PM' && h != 12) h += 12;
      if (ampm == 'AM' && h == 12) h = 0;

      final schedMins = h * 60 + m;
      final reminderKey = 'reminder_${todayKey}_${doc.id}';
      final confirmKey = 'confirm_${todayKey}_${doc.id}';

      final reminderMarker = await fs
          .collection('notifMarkers')
          .doc('${uid}_$reminderKey')
          .get();
      final confirmMarker = await fs
          .collection('notifMarkers')
          .doc('${uid}_$confirmKey')
          .get();

      final prefsDoc = await fs.collection('notifPrefs').doc(uid).get();
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
        await fs.collection('notifMarkers').doc('${uid}_$reminderKey').set({'uid': uid, 'markerKey': reminderKey, 'value': true, 'updatedAt': FieldValue.serverTimestamp()});
      }

      if (isFeedingEnabled && !confirmMarker.exists && nowMins > schedMins && nowMins <= schedMins + 15) {
        final dispatchedDoc = await fs
            .collection('feederDispatched')
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
          await fs.collection('notifMarkers').doc('${uid}_$confirmKey').set({'uid': uid, 'markerKey': confirmKey, 'value': true, 'updatedAt': FieldValue.serverTimestamp()});
        }
      }
    }
  }

  static Future<void> checkSamplingReminders() async {
    final uid = _userId;
    if (uid.isEmpty) return;
    final now = DateTime.now();
    final fs = FirebaseFirestore.instance;

    Map<String, dynamic>? tank;
    try {
      final configSnap = await fs.collection('config').doc(uid).get();
      if (configSnap.exists) tank = configSnap.data();
    } catch (e) {
      debugPrint('[BackgroundHelper] Failed to read config from Firestore: $e');
    }
    if (tank == null) return;

    final isInitialized = tank['isInitialized'] as bool? ?? false;
    if (!isInitialized) return;

    int effectiveSampleTs = 0;
    try {
      final samplingSnap = await fs
          .collection('sampling')
          .where('uid', isEqualTo: uid)
          .get();
      if (samplingSnap.docs.isNotEmpty) {
        int? latestTs;
        for (final doc in samplingSnap.docs) {
          final data = doc.data();
          final ts = data['date'] as int?;
          if (ts != null && (latestTs == null || ts > latestTs)) latestTs = ts;
        }
        effectiveSampleTs = latestTs ?? (tank['stockingDate'] as int? ?? 0);
      } else {
        effectiveSampleTs = tank['stockingDate'] as int? ?? 0;
      }
    } catch (e) {
      debugPrint('[BackgroundHelper] Failed to read sampling from Firestore: $e');
      effectiveSampleTs = tank['stockingDate'] as int? ?? 0;
    }
    if (effectiveSampleTs <= 0) return;

    final effectiveLastDate = DateTime.fromMillisecondsSinceEpoch(effectiveSampleTs);
    final effectiveDate = DateTime(effectiveLastDate.year, effectiveLastDate.month, effectiveLastDate.day);
    final daysSince = now.difference(effectiveDate).inDays;
    if (daysSince < 7) return;

    const markerKey = 'sampling_reminder';
    final markerDoc = await fs.collection('notifMarkers').doc('${uid}_$markerKey').get();
    if (markerDoc.exists && markerDoc.data() != null) {
      final data = markerDoc.data()!;
      final val = data['value'];
      if (val is Map) {
        final lastSampleTs = val['sampleTs'] as int? ?? 0;
        final lastReminderTs = val['reminderTs'] as int? ?? 0;
        if (lastSampleTs == effectiveSampleTs && lastReminderTs > 0) {
          final lastReminder = DateTime.fromMillisecondsSinceEpoch(lastReminderTs);
          if (now.difference(lastReminder).inDays < 7) return;
        }
      } else if (val is int && val > 0) {
        final lastReminder = DateTime.fromMillisecondsSinceEpoch(val);
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

    await fs.collection('notifMarkers').doc('${uid}_$markerKey').set({
      'uid': uid,
      'markerKey': markerKey,
      'value': {
        'reminderTs': now.millisecondsSinceEpoch,
        'sampleTs': effectiveSampleTs,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
