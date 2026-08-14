import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'actuator_log_service.dart';
import '../models/notification_item.dart';
import '../models/control_types.dart';

/// TOP-LEVEL background message handler — required by Firebase Messaging.
/// Must be outside any class and annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background msg: ${message.messageId}');

  // Pre-arm FCM — wake the app and schedule exact OS alarm at T-5m
  if (message.data['type'] == 'pre_arm') {
    debugPrint('[FCM] Pre-arm received — scheduling OS alarm');
    await _handlePreArm(message.data.cast<String, String>());
    return;
  }

  // Skip showing local notification if FCM has a 'notification' payload.
  // When app is background/terminated, the Android system auto-displays it
  // using the notification channel specified in the worker payload.
  if (message.notification != null) {
    debugPrint('[FCM] Notification payload present, system will handle display.');
    return;
  }

  try {
    final localNotif = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await localNotif.initialize(
      const InitializationSettings(android: androidSettings),
    );

    final manager = localNotif
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (manager != null) {
      await manager.createNotificationChannel(
        const AndroidNotificationChannel(
          'craycare_alerts_sound_vibrate',
          'CrayCare Alerts (Sound & Vibrate)',
          description: 'Alerts with sound and vibration enabled',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      await manager.createNotificationChannel(
        AndroidNotificationChannel(
          'craycare_alerts_sound_only',
          'CrayCare Alerts (Sound Only)',
          description: 'Alerts with sound only',
          importance: Importance.high,
          playSound: true,
          enableVibration: false,
          vibrationPattern: Int64List(0),
        ),
      );
      await manager.createNotificationChannel(
        const AndroidNotificationChannel(
          'craycare_alerts_vibrate_only',
          'CrayCare Alerts (Vibration Only)',
          description: 'Alerts with vibration only',
          importance: Importance.high,
          playSound: false,
          enableVibration: true,
          sound: null,
        ),
      );
      await manager.createNotificationChannel(
        AndroidNotificationChannel(
          'craycare_alerts_silent',
          'CrayCare Alerts (Silent)',
          description: 'Silent alerts',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          sound: null,
          vibrationPattern: Int64List(0),
        ),
      );
    }

    final data = message.data;

    final isFeeding = data['feeding'] == 'true';
    final isSampling = data['sampling'] == 'true';
    final isWarning = data['warning'] == 'true';
    final showCritical = data['critical'] != 'false';
    if (!showCritical && !isFeeding && !isSampling && !isWarning) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // notifPrefs migrated to users/{uid}/notification_settings/preferences
        final prefsDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('notification_settings')
            .doc('preferences')
            .get();
        if (prefsDoc.exists && prefsDoc.data() != null) {
          final map = prefsDoc.data()!;

          if (isFeeding && map['feeding'] == false) {
            debugPrint('[FCM] Skipping feeding notification because it is turned off in preferences.');
            return;
          }
          if (isSampling && map['sampling'] == false) {
            debugPrint('[FCM] Skipping sampling notification because it is turned off in preferences.');
            return;
          }
          if (isWarning && map['warning'] == false) {
            debugPrint('[FCM] Skipping warning notification because it is turned off in preferences.');
            return;
          }
          if (!isFeeding && !isSampling && !isWarning && map['critical'] == false) {
            debugPrint('[FCM] Skipping critical notification because it is turned off in preferences.');
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('[FCM] Error reading preferences in background: $e');
    }

    final playSound = data['sound'] != 'false';
    final vibrate = data['vibration'] != 'false';
    final title = data['title'] ?? message.notification?.title ?? 'CrayCare Alert';
    final body = data['body'] ?? message.notification?.body ?? data['message'] ?? '';

    String targetChannelId = 'craycare_alerts_silent';
    if (playSound && vibrate) {
      targetChannelId = 'craycare_alerts_sound_vibrate';
    } else if (playSound) {
      targetChannelId = 'craycare_alerts_sound_only';
    } else if (vibrate) {
      targetChannelId = 'craycare_alerts_vibrate_only';
    }

    await localNotif.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          targetChannelId,
          'CrayCare Alert',
          importance: playSound || vibrate ? Importance.high : Importance.low,
          priority: Priority.high,
          playSound: playSound,
          enableVibration: vibrate,
          vibrationPattern: !vibrate ? Int64List(0) : null,
          sound: !playSound ? null : const RawResourceAndroidNotificationSound('default'),
        ),
      ),
    );
  } catch (e) {
    debugPrint('[FCM] Background notification error: $e');
  }
}

/// Top-level handler for pre-arm FCM — schedules exact OS alarm at T-5m.
@pragma('vm:entry-point')
Future<void> _handlePreArm(Map<String, String> data) async {
  try {
    tz.initializeTimeZones();
    final timeStr = data['scheduleTime'] ?? '';
    final ampm = data['scheduleAmPm'] ?? 'AM';
    if (timeStr.isEmpty) return;

    DateTime scheduleDt;
    final epochStr = data['scheduleEpoch'];
    if (epochStr != null) {
      final ms = int.tryParse(epochStr);
      if (ms == null) return;
      scheduleDt = DateTime.fromMillisecondsSinceEpoch(ms);
    } else {
      int h = int.parse(timeStr.split(':')[0]);
      final m = int.parse(timeStr.split(':')[1]);
      if (ampm == 'PM' && h != 12) h += 12;
      if (ampm == 'AM' && h == 12) h = 0;
      final now = DateTime.now();
      scheduleDt = DateTime(now.year, now.month, now.day, h, m);
    }

    final target = scheduleDt.subtract(const Duration(minutes: 5));
    final now = DateTime.now();

    final localNotif = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await localNotif.initialize(const InitializationSettings(android: androidSettings));

    bool playSound = true;
    bool vibrate = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final prefsDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('notification_settings')
            .doc('preferences')
            .get();
        if (prefsDoc.exists && prefsDoc.data() != null) {
          final prefs = prefsDoc.data()!;
          playSound = prefs['sound'] != false;
          vibrate = prefs['vibration'] != false;
        }
      }
    } catch (e, stack) { debugPrint('[Notif] FCM token save error: $e\n$stack'); }

    String channelId = 'craycare_alerts_silent';
    if (playSound && vibrate) {
      channelId = 'craycare_alerts_sound_vibrate';
    } else if (playSound) {
      channelId = 'craycare_alerts_sound_only';
    } else if (vibrate) {
      channelId = 'craycare_alerts_vibrate_only';
    }

    final alarmId = 'prearm_${timeStr}_$ampm'.hashCode;
    final msg = 'Your feeding schedule at $timeStr $ampm will be dispensed in 5 minutes.';

    if (target.isAfter(now)) {
      final loc = tz.local;
      final tzTarget = tz.TZDateTime.from(target, loc);

      await localNotif.zonedSchedule(
        alarmId,
        'Feeding Reminder',
        msg,
        tzTarget,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId, 'CrayCare Alerts',
            importance: playSound || vibrate ? Importance.high : Importance.low,
            priority: Priority.high,
            playSound: playSound,
            enableVibration: vibrate,
            vibrationPattern: !vibrate ? Int64List(0) : null,
            sound: !playSound ? null : const RawResourceAndroidNotificationSound('default'),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );

      debugPrint('[FCM pre-arm] OS alarm set for $target (id=$alarmId, ${target.difference(now).inSeconds}s away)');
      NotificationService._preArmed.add('${timeStr}_$ampm');
    } else if (now.isBefore(scheduleDt)) {
      // Target passed but schedule hasn't — FCM arrived late, fire immediately
      await localNotif.show(
        alarmId,
        'Feeding Reminder',
        msg,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId, 'CrayCare Alerts',
            importance: playSound || vibrate ? Importance.high : Importance.low,
            priority: Priority.high,
            playSound: playSound,
            enableVibration: vibrate,
            vibrationPattern: !vibrate ? Int64List(0) : null,
            sound: !playSound ? null : const RawResourceAndroidNotificationSound('default'),
          ),
        ),
      );
      debugPrint('[FCM pre-arm] Target passed — fired immediately (${scheduleDt.difference(now).inSeconds}s before schedule)');
      NotificationService._preArmed.add('${timeStr}_$ampm');
    } else {
      debugPrint('[FCM pre-arm] Schedule already passed — skipping');
    }
  } catch (e) {
    debugPrint('[FCM pre-arm] Error: $e');
  }
}

class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  static final Set<String> _preArmed = {};

  final List<NotificationItem> _notifications = [];

  bool _initialized = false;

  // Auto-control notification tracking
  StreamSubscription<AutoActuatorEvent>? _autoControlSub;

  bool _notifSound = true;
  bool _notifVibration = true;
  bool _notifCritical = true;
  bool _notifWarning = true;
  bool _notifFeeding = true;
  bool _notifSampling = true;

  final Set<String> _feedingReminderSent = {};

  String? _userRole;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileFirestoreSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _prefsSub;
  Timer? _slowTimer;

  bool unreadStatus(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return false;
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return false;
    return _notifications[idx].isUnreadBy(uid);
  }

  // Feeding schedules are configured in — and the Cloud Function
  // (functions/notifications/index.js) dispatches/confirms them in — fixed
  // Asia/Manila wall-clock time (MANILA_OFFSET_MS there). Using
  // DateTime.now() directly would compare schedule times against the
  // DEVICE's local clock instead, causing wrong-time or duplicate
  // reminders for anyone outside that timezone. This mirrors the same
  // fixed +8h approach so both sides agree.
  static const _manilaOffset = Duration(hours: 8);
  DateTime _manilaNow() => DateTime.now().toUtc().add(_manilaOffset);

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription? _tokenSub;

  List<NotificationItem> get notifications =>
      List.unmodifiable(_notifications.where((n) => n.notif_type != 'device_auto'));

  int get unreadCount {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return uid.isEmpty ? 0 : _notifications.where((n) => n.isUnreadBy(uid)).length;
  }
  int get criticalCount =>
      _notifications.where((n) => n.notif_type == 'critical').length;

  List<NotificationItem> get todayNotifications =>
      _notifications.where((n) => _isToday(n.created_at)).toList();

  int get todayCount => todayNotifications.length;
  int get reminderCount =>
      _notifications.where((n) => n.notif_type == 'reminder').length;

  void init() {
    if (_initialized) return;
    _initialized = true;
    // Sensor alert documents are created by the server-side onSensorUpdate
    // function. Do not create a second client-side copy for the same transition.
    ActuatorLogService.instance.init();
    tz.initializeTimeZones();

    if (FirebaseAuth.instance.currentUser != null) {
      _listenFirebase();
      _loadUserPrefs();
      _startReminderTimer();
      _initAutoControlListener();
    }

    FirebaseAuth.instance.authStateChanges().listen((user) {
      _notifications.clear();
      _cancelSubscriptions();
      _cancelAutoControlSubs();
      _slowTimer?.cancel();
      _userRole = null;
      if (user != null) {
        _startReminderTimer();
        _listenProfile();
      }
      notifyListeners();
    });
  }

  void _listenProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _profileFirestoreSub?.cancel();
    _profileFirestoreSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) async {
          if (!doc.exists || doc.data() == null) return;
          final profile = doc.data()!;
          _userRole = profile['role'] as String?;

          if (_userRole == 'admin') {
            _notifSub?.cancel();
            _prefsSub?.cancel();
            _notifications.clear();
            // Remove only this device's token from the array.
            try {
              final token = await FirebaseMessaging.instance.getToken();
              if (token != null) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .update({'fcmTokens': FieldValue.arrayRemove([token])});
              }
            } catch (e, stack) { debugPrint('[Notif] FCM token cleanup error: $e\n$stack'); }
            notifyListeners();
          } else {
            _listenFirebase();
            _loadUserPrefs();
            final messaging = FirebaseMessaging.instance;
            try {
              final token = await messaging.getToken();
              if (token != null) _saveToken(token);
            } catch (e, stack) { debugPrint('[Notif] schedule error: $e\n$stack'); }
          }
        });
  }

  Future<void> initFCM() async {
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);
      await _localNotifications.initialize(initSettings);

      final manager = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (manager != null) {
        // Create 4 distinct channels for each combination of Sound & Vibration
        await manager.createNotificationChannel(
          const AndroidNotificationChannel(
            'craycare_alerts_sound_vibrate',
            'CrayCare Alerts (Sound & Vibrate)',
            description: 'Alerts with sound and vibration enabled',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );

        // Vibration is strictly OFF on this channel
        await manager.createNotificationChannel(
          AndroidNotificationChannel(
            'craycare_alerts_sound_only',
            'CrayCare Alerts (Sound Only)',
            description: 'Alerts with sound only',
            importance: Importance.high,
            playSound: true,
            enableVibration: false,
            vibrationPattern: Int64List(0),
          ),
        );

        // Sound is strictly OFF on this channel
        await manager.createNotificationChannel(
          const AndroidNotificationChannel(
            'craycare_alerts_vibrate_only',
            'CrayCare Alerts (Vibration Only)',
            description: 'Alerts with vibration only',
            importance: Importance.high,
            playSound: false,
            enableVibration: true,
            sound: null,
          ),
        );

        // Sound and Vibration are strictly OFF on this channel
        await manager.createNotificationChannel(
          AndroidNotificationChannel(
            'craycare_alerts_silent',
            'CrayCare Alerts (Silent)',
            description: 'Silent alerts',
            importance: Importance
                .low, // Importance.low ensures no sound or vibration by system default
            playSound: false,
            enableVibration: false,
            sound: null,
            vibrationPattern: Int64List(0),
          ),
        );

        await manager.requestExactAlarmsPermission();
        await manager.requestNotificationsPermission();
      }

      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Explicitly disable native system banners/alerts when the app is in the foreground
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false, // Prevents popup banner
        badge: false, // Prevents badge update in foreground
        sound: false, // Prevents native system sound in foreground
      );

      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);

      _tokenSub = messaging.onTokenRefresh.listen(_saveToken);

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      debugPrint('[NotificationService] FCM initialized');

    } catch (e) {
      debugPrint('[NotificationService] FCM init error: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (_userRole == 'admin') {
          // Admin accounts don't receive push notifications — remove this
          // device's token without affecting other logged-in devices.
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'fcmTokens': FieldValue.arrayRemove([token])});
          return;
        }
        // Store as an array so multiple devices (same account) each keep
        // their own token and all receive notifications independently.
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(
              {'fcmTokens': FieldValue.arrayUnion([token])},
              SetOptions(merge: true),
            );
      }
    } catch (e) {
      debugPrint('[NotificationService] Token save error: $e');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = message.data;

    if (data['type'] == 'pre_arm') {
      debugPrint('[NotificationService] Foreground pre-arm received — scheduling OS alarm');
      await _handlePreArm(data.cast<String, String>());
      return;
    }

    final isFeeding = data['feeding'] == 'true';
    final isSampling = data['sampling'] == 'true';
    final isWarning = data['warning'] == 'true';
    final showCritical = data['critical'] != 'false';
    if (!showCritical && !isFeeding && !isSampling && !isWarning) return;

    if (isFeeding && !_notifFeeding) return;
    if (isSampling && !_notifSampling) return;
    if (isWarning && !_notifWarning) return;
    if (!isFeeding && !isSampling && !isWarning && !_notifCritical) return;

    final playSound = data['sound'] != 'false' && _notifSound;
    final vibrate = data['vibration'] != 'false' && _notifVibration;
    final title = data['title'] ?? message.notification?.title ?? 'CrayCare Alert';
    final body = data['body'] ?? message.notification?.body ?? data['message'] ?? '';

    String channelId = 'craycare_alerts_silent';
    if (playSound && vibrate) {
      channelId = 'craycare_alerts_sound_vibrate';
    } else if (playSound) {
      channelId = 'craycare_alerts_sound_only';
    } else if (vibrate) {
      channelId = 'craycare_alerts_vibrate_only';
    }

    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'CrayCare Alert',
            importance: playSound || vibrate ? Importance.high : Importance.low,
            priority: Priority.high,
            playSound: playSound,
            enableVibration: vibrate,
            vibrationPattern: !vibrate ? Int64List(0) : null,
            sound: !playSound ? null : const RawResourceAndroidNotificationSound('default'),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NotificationService] Foreground notification error: $e');
    }
  }

  // Background handler is now a top-level function: firebaseBackgroundMessageHandler (above the class)

  @override
  void dispose() {
    _tokenSub?.cancel();
    _notifSub?.cancel();
    _prefsSub?.cancel();
    _profileFirestoreSub?.cancel();
    _slowTimer?.cancel();
    _cancelAutoControlSubs();
    super.dispose();
  }

  void _loadUserPrefs() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _prefsSub?.cancel();
    _prefsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notification_settings')
        .doc('preferences')
        .snapshots()
        .listen((doc) {
          if (!doc.exists || doc.data() == null) return;
          final map = doc.data()!;
          _notifSound = map['sound'] as bool? ?? true;
          _notifVibration = map['vibration'] as bool? ?? true;
          _notifCritical = map['critical'] as bool? ?? true;
          _notifWarning = map['warning'] as bool? ?? true;
          _notifFeeding = map['feeding'] as bool? ?? true;
          _notifSampling = map['sampling'] as bool? ?? true;
          notifyListeners();
        });
  }

  void _initAutoControlListener() {
    _autoControlSub?.cancel();
    _autoControlSub = ActuatorLogService.instance.autoControlEvents.listen((event) {
      String title, message;
      if (event.action.contains('ON')) {
        title = '${event.actuatorLabel} turned ON';
        message = event.action.replaceFirst('Switched ON (AUTO) - ', '');
      } else {
        title = '${event.actuatorLabel} turned OFF';
        message = event.action.replaceFirst('Switched OFF (AUTO) - ', '');
      }
      _addNotification(type: 'operational', title: title, message: message, timestamp: event.timestamp);
    });
  }

  void _cancelAutoControlSubs() {
    _autoControlSub?.cancel();
    _autoControlSub = null;
  }

  void _startReminderTimer() {
    // Feeding and sampling reminders are server-owned Cloud Functions. Running
    // parallel client timers created duplicate database entries and OS banners.
    _slowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _confirmFeedingComplete();
    });
  }

  Future<void> _confirmFeedingComplete() async {
    if (_userRole == 'admin') return;
    if (!_notifFeeding) return;
    final now = DateTime.now();
    final oneMinAgo = now.millisecondsSinceEpoch - 60000;

    for (final log in FeedState.feederLogs.value) {
      if (log.type != 'auto') continue;
      if (!log.action.contains('Auto feed dispensed')) continue;
      if (log.timestamp <= 0 || log.timestamp < oneMinAgo) continue;

      final confirmKey = 'confirm_${now.month}/${now.day}_${log.timestamp}';
      if (_feedingReminderSent.contains(confirmKey)) continue;
      _feedingReminderSent.add(confirmKey);
    }
  }

  void _cancelSubscriptions() {
    _notifSub?.cancel();
    _prefsSub?.cancel();
    _profileFirestoreSub?.cancel();
    _profileFirestoreSub = null;
    _cancelAutoControlSubs();
  }

  void _listenFirebase() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    final fs = FirebaseFirestore.instance;

    _notifSub?.cancel();
    _notifSub = fs
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(100)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;
        final key = doc.id;
        final isReadRaw = data['is_read'] as bool? ?? false;

        if (change.type == DocumentChangeType.added) {
          if (_notifications.any((n) => n.id == key)) continue;
          final tsData = data['created_at'];
          DateTime? createdDt;
          if (tsData is Timestamp) {
            createdDt = tsData.toDate();
          } else if (tsData is int) {
            createdDt = DateTime.fromMillisecondsSinceEpoch(tsData);
          } else {
            createdDt = DateTime.now();
          }
          _notifications.add(
            NotificationItem(
              id: key,
              notif_type: data['notif_type'] ?? 'operational',
              title: data['title'] ?? '',
              body: data['body'] ?? '',
              created_at: createdDt,
              is_read: isReadRaw,
            ),
          );
        } else if (change.type == DocumentChangeType.modified) {
          final idx = _notifications.indexWhere((n) => n.id == key);
          if (idx != -1) {
            _notifications[idx].is_read = isReadRaw;
          }
        } else if (change.type == DocumentChangeType.removed) {
          _notifications.removeWhere((n) => n.id == key);
        }
      }
      _notifications.sort((a, b) => b.created_at.compareTo(a.created_at));
      notifyListeners();
    });
  }

  void _addNotification({
    required String type,
    required String title,
    required String message,
    required DateTime timestamp,
  }) {
    if (_userRole == 'admin') return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('notifications').doc();
    final notif = NotificationItem(
      id: docRef.id,
      notif_type: type,
      title: title,
      body: message,
      created_at: timestamp,
      is_read: false,
    );

    _notifications.insert(0, notif);
    notifyListeners();

    docRef.set({
      'uid': uid,
      'notif_type': notif.notif_type,
      'title': notif.title,
      'body': notif.body,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
    }).catchError((e) {
      debugPrint('[NotificationService] Failed to save: $e');
    });

    debugPrint(
      '[NotificationService] Local notification recorded in DB, skipping native banner in-app.',
    );
  }

  void markAllRead() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    for (final n in _notifications) {
      n.is_read = true;
    }
    notifyListeners();
    final fs = FirebaseFirestore.instance;
    for (final n in _notifications) {
      fs.collection('notifications').doc(n.id).update({
        'is_read': true,
      }).catchError((_) {});
    }
  }

  void markAsRead(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    for (final n in _notifications) {
      if (n.id == id) {
        n.is_read = true;
        notifyListeners();
        FirebaseFirestore.instance.collection('notifications').doc(id).update({
          'is_read': true,
        }).catchError((_) {});
        return;
      }
    }
  }

  void clearAll() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _notifications.clear();
    notifyListeners();
    if (uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('notifications')
          .where('uid', isEqualTo: uid)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[NotificationService] Failed to clear Firebase: $e');
    }
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.day == now.day && dt.month == now.month && dt.year == now.year;
  }
}
