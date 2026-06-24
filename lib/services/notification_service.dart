import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'sensor_service.dart';
import 'tank_service.dart';
import '../models/notification_item.dart';
import '../models/control_types.dart';
import 'database_service.dart';

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

    final showCritical = data['critical'] != 'false';
    if (!showCritical && !isFeeding && !isSampling) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final snap = await FirebaseDatabase.instance.ref('users/${user.uid}/notifPrefs').get();
        if (snap.exists && snap.value != null) {
          final raw = snap.value as Map<Object?, Object?>;
          final map = raw.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));

          if (isFeeding && map['feeding'] == false) {
            debugPrint('[FCM] Skipping feeding notification because it is turned off in preferences.');
            return;
          }
          if (isSampling && map['sampling'] == false) {
            debugPrint('[FCM] Skipping sampling notification because it is turned off in preferences.');
            return;
          }
          if (!isFeeding && !isSampling && map['critical'] == false) {
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
        final snap = await FirebaseDatabase.instance
            .ref('users/${user.uid}/notifPrefs').get();
        if (snap.exists && snap.value != null) {
          final raw = snap.value as Map<Object?, Object?>;
          final prefs = raw.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
          playSound = prefs['sound'] != false;
          vibrate = prefs['vibration'] != false;
        }
      }
    } catch (_) {}

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
  final Map<String, String> _previousZones = {};
  int _idCounter = 0;
  bool _initialized = false;

  // Auto-control notification tracking
  final Set<String> _seenAutoLogKeys = {};
  bool _autoControlWarmup = true;
  final Map<String, String> _deviceLabels = {
    'aerator1': 'Aerator 1',
    'aerator2': 'Aerator 2',
    'pump': 'Water Pump',
  };
  final List<StreamSubscription<DatabaseEvent>> _autoControlSubs = [];

  bool _notifSound = true;
  bool _notifVibration = true;
  bool _notifCritical = true;
  bool _notifFeeding = true;
  bool _notifSampling = true;

  final Set<String> _feedingReminderSent = {};
  final Set<String> _pendingTimers = {};
  final Set<String> _osScheduled = {};
  String _lastSamplingReminderDate = '';

  String? _effectiveUid;
  DatabaseReference get _notifRef => FirebaseDatabase.instance.ref(
    'users/${_effectiveUid ?? FirebaseAuth.instance.currentUser?.uid ?? ""}/notifications',
  );
  String? _userRole;
  StreamSubscription<DatabaseEvent>? _profileSub;
  StreamSubscription<DatabaseEvent>? _notifSub;
  StreamSubscription<DatabaseEvent>? _notifChangedSub;
  StreamSubscription<DatabaseEvent>? _notifRemovedSub;
  StreamSubscription<DatabaseEvent>? _prefsSub;
  Timer? _reminderTimer;
  Timer? _slowTimer;

  bool unreadStatus(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return false;
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return false;
    return _notifications[idx].isUnreadBy(uid);
  }

  Future<void> setEffectiveUid(String uid) async {
    _cancelSubscriptions();
    _effectiveUid = uid;
    _listenFirebase();
    _loadUserPrefs();
    _initPreviousStates();
    notifyListeners();
  }

  bool get _isMonitor => _effectiveUid != null;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription? _tokenSub;

  static const _sensorLabels = {
    'temp': 'Water Temperature',
    'ph': 'pH Level',
    'do': 'Dissolved Oxygen',
    'turb': 'Turbidity',
    'waterlevel': 'Water Level',
  };

  static const _sensorUnits = {
    'temp': '\u00B0C',
    'ph': '',
    'do': 'mg/L',
    'turb': 'NTU',
    'waterlevel': 'cm',
  };

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);

  int get unreadCount {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return uid.isEmpty ? 0 : _notifications.where((n) => n.isUnreadBy(uid)).length;
  }
  int get criticalCount =>
      _notifications.where((n) => n.type == 'critical').length;

  List<NotificationItem> get todayNotifications =>
      _notifications.where((n) => _isToday(n.timestamp)).toList();

  int get todayCount => todayNotifications.length;
  int get reminderCount =>
      _notifications.where((n) => n.type == 'reminder').length;

  void init() {
    if (_initialized) return;
    _initialized = true;
    _listenFirebase();
    _loadUserPrefs();
    SensorService.instance.addListener(_onSensorUpdate);
    _initPreviousStates();
    tz.initializeTimeZones();
    _startReminderTimer();
    _initAutoControlListener();
    FeedState.schedules.addListener(_onSchedulesChanged);
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _notifications.clear();
      _effectiveUid = null;
      _cancelSubscriptions();
      _cancelAutoControlSubs();
      _userRole = null;
      if (user != null) {
        _listenProfile();
      }
      notifyListeners();
    });
  }

  void _listenProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _profileSub?.cancel();
    _profileSub = FirebaseDatabase.instance
        .ref('users/${user.uid}/profile')
        .onValue
        .listen((event) async {
          if (event.snapshot.value == null) return;
          final profile = DatabaseService.convertMap(
            event.snapshot.value as Map,
          );
          _userRole = profile['role'] as String?;

          if (_userRole == 'admin') {
            _notifSub?.cancel();
            _notifRemovedSub?.cancel();
            _prefsSub?.cancel();
            _notifications.clear();
            FirebaseDatabase.instance
                .ref('users/${user.uid}/fcmToken')
                .remove()
                .catchError((_) {});
            notifyListeners();
          } else {
            _listenFirebase();
            _loadUserPrefs();
            final messaging = FirebaseMessaging.instance;
            try {
              final token = await messaging.getToken();
              if (token != null) _saveToken(token);
            } catch (_) {}
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

      _pendingTimers.clear();
      _checkFeedingReminders();
    } catch (e) {
      debugPrint('[NotificationService] FCM init error: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (_userRole == 'admin') {
          await FirebaseDatabase.instance
              .ref('users/${user.uid}/fcmToken')
              .remove();
          return;
        }
        await FirebaseDatabase.instance
            .ref('users/${user.uid}/fcmToken')
            .set(token);
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
    final showCritical = data['critical'] != 'false';
    if (!showCritical && !isFeeding && !isSampling) return;

    if (isFeeding && !_notifFeeding) return;
    if (isSampling && !_notifSampling) return;
    if (!isFeeding && !isSampling && !_notifCritical) return;

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
    _notifRemovedSub?.cancel();
    _prefsSub?.cancel();
    _profileSub?.cancel();
    _reminderTimer?.cancel();
    _slowTimer?.cancel();
    _cancelAutoControlSubs();
    FeedState.schedules.removeListener(_onSchedulesChanged);
    SensorService.instance.removeListener(_onSensorUpdate);
    super.dispose();
  }

  void _initPreviousStates() {
    for (final key in SensorService.sensorKeys) {
      final zone = SensorService.instance.getZone(key);
      _previousZones[key] = zone;
    }
  }

  void _loadUserPrefs() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _prefsSub?.cancel();
    _prefsSub = FirebaseDatabase.instance
        .ref('users/${user.uid}/notifPrefs')
        .onValue
        .listen((e) {
          if (!e.snapshot.exists || e.snapshot.value == null) return;
          final raw = e.snapshot.value as Map<Object?, Object?>;
          final map = raw.map<String, dynamic>(
            (k, v) => MapEntry(k.toString(), v),
          );
          _notifSound = map['sound'] as bool? ?? true;
          _notifVibration = map['vibration'] as bool? ?? true;
          _notifCritical = map['critical'] as bool? ?? true;
          _notifFeeding = map['feeding'] as bool? ?? true;
          _notifSampling = map['sampling'] as bool? ?? true;
          notifyListeners();
        });
  }

  void _initAutoControlListener() {
    _cancelAutoControlSubs();
    _seenAutoLogKeys.clear();
    _autoControlWarmup = true;

    for (final deviceId in _deviceLabels.keys) {
      final ref = FirebaseDatabase.instance.ref('devices/logs/$deviceId');
      final sub = ref.onChildAdded.listen((event) {
        if (event.snapshot.value == null) return;
        final raw = event.snapshot.value as Map<Object?, Object?>;
        final map = raw.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
        final action = map['action'] as String? ?? '';
        final key = event.snapshot.key;
        if (key == null) return;

        _seenAutoLogKeys.add(key);

        // Skip during warmup to avoid notifying for existing log entries
        if (_autoControlWarmup) return;

        if (!action.contains('(AUTO)')) return;

        final tsRaw = map['timestamp'] as num? ?? 0;
        final tsMs = tsRaw < 100000000000 ? tsRaw * 1000 : tsRaw;
        final ts = DateTime.fromMillisecondsSinceEpoch(tsMs.toInt());
        final label = _deviceLabels[deviceId] ?? deviceId;

        String title, message;
        if (action.contains('ON')) {
          title = '$label turned ON';
          message = action.replaceFirst('Switched ON (AUTO) - ', '');
        } else {
          title = '$label turned OFF';
          message = action.replaceFirst('Switched OFF (AUTO) - ', '');
        }

        _addNotification(type: 'operational', title: title, message: message, timestamp: ts);
      });
      _autoControlSubs.add(sub);
    }

    // Warmup period: absorb existing log entries without creating notifications
    Future.delayed(const Duration(seconds: 3), () {
      _autoControlWarmup = false;
    });
  }

  void _cancelAutoControlSubs() {
    for (final sub in _autoControlSubs) {
      sub.cancel();
    }
    _autoControlSubs.clear();
  }

  void _startReminderTimer() {
    _preScheduleOSReminders();
    _checkFeedingReminders();
    _reminderTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkFeedingReminders();
    });
    _slowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _confirmFeedingComplete();
      _checkSamplingReminders();
    });
  }

  void _onSchedulesChanged() {
    _preScheduleOSReminders();
    _checkFeedingReminders();
  }

  void _checkFeedingReminders() {
    if (_userRole == 'admin') return;
    if (!_notifFeeding) return;
    final now = DateTime.now();
    final todayKey = '${now.month}/${now.day}';

    for (final s in FeedState.schedules.value) {
      if (!s.enabled) continue;
      int h = int.parse(s.time.split(':')[0]);
      final m = int.parse(s.time.split(':')[1]);
      if (s.ampm == 'PM' && h != 12) h += 12;
      if (s.ampm == 'AM' && h == 12) h = 0;

      final key = '${todayKey}_${s.time}_${s.ampm}';
      if (_feedingReminderSent.contains(key)) continue;
      if (h * 60 + m <= 0) continue;

      final target = DateTime(now.year, now.month, now.day, h, m).subtract(const Duration(minutes: 5));
      final scheduleDt = DateTime(now.year, now.month, now.day, h, m);
      final diff = target.difference(now);
      final schedDiff = scheduleDt.difference(now);

      if (schedDiff > Duration.zero && schedDiff <= const Duration(minutes: 5)) {
        if (!_pendingTimers.contains(key)) {
          _pendingTimers.add(key);
          if (diff > Duration.zero) {
            Future.delayed(diff, () => _fireReminder(key, s, scheduledAt: target));
          } else {
            _fireReminder(key, s, scheduledAt: target);
          }
          _scheduleOSReminder(key, s, target);
        }
      }
    }
  }

  void _preScheduleOSReminders() {
    if (_userRole == 'admin') return;
    final now = DateTime.now();
    final todayKey = '${now.month}/${now.day}';

    for (final s in FeedState.schedules.value) {
      if (!s.enabled) continue;
      int h = int.parse(s.time.split(':')[0]);
      final m = int.parse(s.time.split(':')[1]);
      if (s.ampm == 'PM' && h != 12) h += 12;
      if (s.ampm == 'AM' && h == 12) h = 0;

      final key = '${todayKey}_${s.time}_${s.ampm}';
      if (_osScheduled.contains(key)) continue;

      final target = DateTime(now.year, now.month, now.day, h, m).subtract(const Duration(minutes: 5));
      if (target.isBefore(now)) continue;

      _scheduleOSReminder(key, s, target);
    }
  }

  void _scheduleOSReminder(String key, ScheduleItem s, DateTime target) {
    if (_osScheduled.contains(key)) return;
    if (target.isBefore(DateTime.now())) return;
    _osScheduled.add(key);
    try {
      final loc = tz.local;
      final tzTarget = tz.TZDateTime.from(target, loc);
      String channelId = 'craycare_alerts_silent';
      if (_notifSound && _notifVibration) {
        channelId = 'craycare_alerts_sound_vibrate';
      } else if (_notifSound) {
        channelId = 'craycare_alerts_sound_only';
      } else if (_notifVibration) {
        channelId = 'craycare_alerts_vibrate_only';
      }
      _localNotifications.zonedSchedule(
        key.hashCode,
        'Feeding Reminder',
        'Your feeding schedule at ${s.time} ${s.ampm} will be dispensed in 5 minutes.',
        tzTarget,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'CrayCare Alerts',
            importance: _notifSound || _notifVibration ? Importance.high : Importance.low,
            priority: Priority.high,
            playSound: _notifSound,
            enableVibration: _notifVibration,
            vibrationPattern: !_notifVibration ? Int64List(0) : null,
            sound: !_notifSound ? null : RawResourceAndroidNotificationSound('default'),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('[NotificationService] OS scheduled reminder for ${s.time} ${s.ampm} at $target (id=${key.hashCode})');
    } catch (e) {
      debugPrint('[NotificationService] OS schedule error: $e');
    }
  }

  Future<void> _fireReminder(String key, ScheduleItem s, {bool showSystemNotif = true, DateTime? scheduledAt}) async {
    if (_feedingReminderSent.contains(key)) return;
    _feedingReminderSent.add(key);
    _localNotifications.cancel(key.hashCode);

    final msg = 'Your feeding schedule at ${s.time} ${s.ampm} will be dispensed in 5 minutes.';

    debugPrint('[NotificationService] Firing reminder for ${s.time} ${s.ampm}');

    final now = DateTime.now();
    int h = int.parse(s.time.split(':')[0]);
    final m = int.parse(s.time.split(':')[1]);
    if (s.ampm == 'PM' && h != 12) h += 12;
    if (s.ampm == 'AM' && h == 12) h = 0;
    final hhmm = '${h.toString().padLeft(2, '0')}${m.toString().padLeft(2, '0')}';
    final y = now.year.toString();
    final mo = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final reminderKey = 'reminder_${y}-${mo}-${d}_$hhmm';

    final scheduleLabel = '${s.time} ${s.ampm}';
    final alreadyAdded = _notifications.any(
      (n) => n.type == 'reminder' && n.message.contains(scheduleLabel),
    );

    if (!alreadyAdded) {
      _addNotification(
        type: 'reminder',
        title: 'Feeding Reminder',
        message: msg,
        timestamp: scheduledAt ?? now,
      );
    }

    if (NotificationService._preArmed.contains('${s.time}_${s.ampm}')) {
      debugPrint('[NotificationService] Pre-arm active — OS alarm will fire at exact time, skipping system notification');
      await _notifRef
          .child('markers/$reminderKey')
          .set(now.millisecondsSinceEpoch);
      return;
    }

    final markerExists = await _notifRef
        .child('markers/$reminderKey')
        .once()
        .then((s) => s.snapshot.exists);

    if (markerExists) {
      debugPrint('[NotificationService] Marker exists — worker already handled. Skipping local notif to avoid duplicate.');
      return;
    }

    await _notifRef
        .child('markers/$reminderKey')
        .set(now.millisecondsSinceEpoch);

    if (!showSystemNotif) return;

    try {
      String channelId = 'craycare_alerts_silent';
      if (_notifSound && _notifVibration) {
        channelId = 'craycare_alerts_sound_vibrate';
      } else if (_notifSound) {
        channelId = 'craycare_alerts_sound_only';
      } else if (_notifVibration) {
        channelId = 'craycare_alerts_vibrate_only';
      }
      _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'Feeding Reminder',
        msg,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'CrayCare Alerts',
            importance: _notifSound || _notifVibration ? Importance.high : Importance.low,
            priority: Priority.high,
            playSound: _notifSound,
            enableVibration: _notifVibration,
            vibrationPattern: !_notifVibration ? Int64List(0) : null,
            sound: !_notifSound ? null : RawResourceAndroidNotificationSound('default'),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NotificationService] Local notification error: $e');
    }
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

  void _checkSamplingReminders() {
    if (_userRole == 'admin') return;
    if (!_notifSampling) return;
    final now = DateTime.now();
    final todayKey = '${now.month}/${now.day}';
    if (_lastSamplingReminderDate == todayKey) return;

    final tank = TankService.instance;
    if (tank.daysSinceLastSampling < 7) return;

    // Check if last reminder was within 7 days (Firebase persisted marker)
    final markerKey = 'sampling_reminder';
    _notifRef.child('markers/$markerKey').once().then((marker) {
      if (marker.snapshot.exists) {
        final lastTs = marker.snapshot.value is int ? marker.snapshot.value as int : 0;
        if (lastTs > 0) {
          final lastReminder = DateTime.fromMillisecondsSinceEpoch(lastTs);
          if (now.difference(lastReminder).inDays < 7) return;
        }
      }

      _lastSamplingReminderDate = todayKey;
      _addNotification(
        type: 'reminder',
        title: 'Sampling Reminder',
        message:
            'It\'s been ${tank.daysSinceLastSampling} days since last sampling. Time to record growth data!',
        timestamp: now,
      );

      _notifRef.child('markers/$markerKey')
          .set(now.millisecondsSinceEpoch);
    });
  }

  void _cancelSubscriptions() {
    _notifSub?.cancel();
    _notifChangedSub?.cancel();
    _notifRemovedSub?.cancel();
    _prefsSub?.cancel();
    _profileSub?.cancel();
    _profileSub = null;
    _cancelAutoControlSubs();
  }

  void _listenFirebase() {
    _notifSub = _notifRef.onChildAdded.listen((e) {
      final key = e.snapshot.key;
      if (key == null || e.snapshot.value == null) return;
      if (_notifications.any((n) => n.id == key)) return;

      final raw = e.snapshot.value as Map<Object?, Object?>;
      final map = raw.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
      final readByRaw = map['readBy'] as Map<String, dynamic>? ?? {};
      _notifications.add(
        NotificationItem(
          id: key,
          type: map['type'] ?? 'operational',
          title: map['title'] ?? '',
          message: map['message'] ?? '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (map['timestamp'] as num).toInt(),
          ),
          readBy: readByRaw.map((k, v) => MapEntry(k, v == true)),
        ),
      );
      _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notifyListeners();
    });

    _notifChangedSub = _notifRef.onChildChanged.listen((e) {
      final key = e.snapshot.key;
      if (key == null || e.snapshot.value == null) return;
      final raw = e.snapshot.value as Map<Object?, Object?>;
      final map = raw.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
      final readByRaw = map['readBy'] as Map<String, dynamic>? ?? {};
      final idx = _notifications.indexWhere((n) => n.id == key);
      if (idx != -1) {
        _notifications[idx].readBy = readByRaw.map((k, v) => MapEntry(k, v == true));
        notifyListeners();
      }
    });

    _notifRemovedSub = _notifRef.onChildRemoved.listen((e) {
      final key = e.snapshot.key;
      if (key == null) return;
      _notifications.removeWhere((n) => n.id == key);
      notifyListeners();
    });
  }

  void _onSensorUpdate() {
    if (_userRole == 'admin') return;
    if (_isMonitor) return;
    final hasData = SensorService.sensorKeys.any(
      (k) => SensorService.instance.getZone(k) != 'UNKNOWN',
    );
    if (!hasData) return;

    final now = DateTime.now();

    for (final key in SensorService.sensorKeys) {
      final zone = SensorService.instance.getZone(key);
      final prevZone = _previousZones[key];
      final value = SensorService.instance.getLatestValue(key);
      final label = _sensorLabels[key] ?? key;
      final unit = _sensorUnits[key] ?? '';

      if (_notifCritical &&
          prevZone != null &&
          zone == 'CRITICAL' &&
          prevZone != 'CRITICAL') {
        _addNotification(
          type: 'critical',
          title: 'Critical: $label',
          message: unit.isNotEmpty
              ? '$label dropped to ${value.toStringAsFixed(1)} $unit.'
              : '$label is at ${value.toStringAsFixed(1)}.',
          timestamp: now,
        );
      } else if (_notifCritical &&
          prevZone != null &&
          zone != 'CRITICAL' &&
          prevZone == 'CRITICAL') {
        _addNotification(
          type: 'operational',
          title: '$label Normalized',
          message: unit.isNotEmpty
              ? '$label returned to optimal range (${value.toStringAsFixed(1)} $unit).'
              : '$label returned to optimal range (${value.toStringAsFixed(1)}).',
          timestamp: now,
        );
      }

      _previousZones[key] = zone;
    }
  }

  void _addNotification({
    required String type,
    required String title,
    required String message,
    required DateTime timestamp,
  }) {
    if (_userRole == 'admin') return;
    final fbRef = _notifRef.push();
    final notif = NotificationItem(
      id: fbRef.key ?? 'notif_${++_idCounter}',
      type: type,
      title: title,
      message: message,
      timestamp: timestamp,
    );

    _notifications.insert(0, notif);
    notifyListeners();

    fbRef
        .set({
          'type': notif.type,
          'title': notif.title,
          'message': notif.message,
          'timestamp': notif.timestamp.millisecondsSinceEpoch,
          'readBy': {},
        })
        .catchError((e) {
          debugPrint('[NotificationService] Failed to save: $e');
        });

    // DO NOT show native system popups when the app is in the foreground
    debugPrint(
      '[NotificationService] Local notification recorded in DB, skipping native banner in-app.',
    );
  }

  void markAllRead() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    for (final n in _notifications) {
      n.readBy[uid] = true;
    }
    notifyListeners();
    for (final n in _notifications) {
      _notifRef.child(n.id).child('readBy').child(uid).set(true).catchError((_) {});
    }
  }

  void markAsRead(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    for (final n in _notifications) {
      if (n.id == id) {
        n.readBy[uid] = true;
        notifyListeners();
        _notifRef.child(n.id).child('readBy').child(uid).set(true).catchError((_) {});
        return;
      }
    }
  }

  void clearAll() async {
    _notifications.clear();
    notifyListeners();
    try {
      await _notifRef.remove();
    } catch (e) {
      debugPrint('[NotificationService] Failed to clear Firebase: $e');
    }
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.day == now.day && dt.month == now.month && dt.year == now.year;
  }
}
