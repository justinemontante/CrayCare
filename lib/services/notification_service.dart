import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'sensor_service.dart';
import 'tank_service.dart';
import '../models/notification_item.dart';
import '../models/control_types.dart';
import 'database_service.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final List<NotificationItem> _notifications = [];
  final Map<String, String> _previousZones = {};
  int _idCounter = 0;
  bool _initialized = false;

  bool _notifSound = true;
  bool _notifVibration = true;
  bool _notifCritical = true;
  bool _notifFeeding = true;
  bool _notifSampling = false;

  final Set<String> _feedingReminderSent = {};
  String _lastSamplingReminderDate = '';

  DatabaseReference get _notifRef =>
      FirebaseDatabase.instance.ref('users/${FirebaseAuth.instance.currentUser?.uid ?? ""}/notifications');
  String? _userRole;
  StreamSubscription<DatabaseEvent>? _profileSub;
  StreamSubscription<DatabaseEvent>? _notifSub;
  StreamSubscription<DatabaseEvent>? _notifRemovedSub;
  StreamSubscription<DatabaseEvent>? _prefsSub;
  Timer? _reminderTimer;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription? _tokenSub;

  static const String _channelId = 'craycare_alerts';
  static const String _channelName = 'CrayCare Alerts';
  static const String _channelDesc = 'Sensor threshold alerts';

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

  int get unreadCount => _notifications.where((n) => n.unread).length;
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
    _startReminderTimer();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _notifications.clear();
      _notifSub?.cancel();
      _notifRemovedSub?.cancel();
      _prefsSub?.cancel();
      _profileSub?.cancel();
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
      final profile = DatabaseService.convertMap(event.snapshot.value as Map);
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
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(
        android: androidSettings,
      );
      await _localNotifications.initialize(initSettings);

      final manager = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (manager != null) {
        // Create 4 distinct channels for each combination of Sound & Vibration
        await manager.createNotificationChannel(const AndroidNotificationChannel(
          'craycare_alerts_sound_vibrate',
          'CrayCare Alerts (Sound & Vibrate)',
          description: 'Alerts with sound and vibration enabled',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ));

        // Vibration is strictly OFF on this channel
        await manager.createNotificationChannel(AndroidNotificationChannel(
          'craycare_alerts_sound_only',
          'CrayCare Alerts (Sound Only)',
          description: 'Alerts with sound only',
          importance: Importance.high,
          playSound: true,
          enableVibration: false,
          vibrationPattern: Int64List(0),
        ));

        // Sound is strictly OFF on this channel
        await manager.createNotificationChannel(const AndroidNotificationChannel(
          'craycare_alerts_vibrate_only',
          'CrayCare Alerts (Vibration Only)',
          description: 'Alerts with vibration only',
          importance: Importance.high,
          playSound: false,
          enableVibration: true,
          sound: null,
        ));

        // Sound and Vibration are strictly OFF on this channel
        await manager.createNotificationChannel(AndroidNotificationChannel(
          'craycare_alerts_silent',
          'CrayCare Alerts (Silent)',
          description: 'Silent alerts',
          importance: Importance.low, // Importance.low ensures no sound or vibration by system default
          playSound: false,
          enableVibration: false,
          sound: null,
          vibrationPattern: Int64List(0),
        ));
      }

      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

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

      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

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
    // Standard Behavior: Skip showing the native push notification banner when user is already in-app.
    // The UI database listeners will automatically catch and display the new record in the notification logs.
    debugPrint('[NotificationService] Foreground message received, skipping native banner to follow app standards.');
  }

  @pragma('vm:entry-point')
  static Future<void> _onBackgroundMessage(RemoteMessage message) async {
    debugPrint('[NotificationService] Background msg: ${message.messageId}');
    try {
      final localNotif = FlutterLocalNotificationsPlugin();
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      await localNotif.initialize(const InitializationSettings(
        android: androidSettings,
      ));

      // Re-initialize dynamic channels in background context to ensure they exist for the system
      final manager = localNotif
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (manager != null) {
        await manager.createNotificationChannel(const AndroidNotificationChannel(
          'craycare_alerts_sound_vibrate',
          'CrayCare Alerts (Sound & Vibrate)',
          description: 'Alerts with sound and vibration enabled',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ));

        await manager.createNotificationChannel(AndroidNotificationChannel(
          'craycare_alerts_sound_only',
          'CrayCare Alerts (Sound Only)',
          description: 'Alerts with sound only',
          importance: Importance.high,
          playSound: true,
          enableVibration: false,
          vibrationPattern: Int64List(0),
        ));

        await manager.createNotificationChannel(const AndroidNotificationChannel(
          'craycare_alerts_vibrate_only',
          'CrayCare Alerts (Vibration Only)',
          description: 'Alerts with vibration only',
          importance: Importance.high,
          playSound: false,
          enableVibration: true,
          sound: null,
        ));

        await manager.createNotificationChannel(AndroidNotificationChannel(
          'craycare_alerts_silent',
          'CrayCare Alerts (Silent)',
          description: 'Silent alerts',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          sound: null,
          vibrationPattern: Int64List(0),
        ));
      }

      final data = message.data;
      final showCritical = data['critical'] != 'false';
      if (!showCritical) return;

      final playSound = data['sound'] != 'false';
      final vibrate = data['vibration'] != 'false';
      final title = data['title'] ?? 'CrayCare Alert';
      final body = data['body'] ?? data['message'] ?? '';

      // Dynamically pick the right channel in background using payloads sent by FCM worker
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
            sound: !playSound ? null : RawResourceAndroidNotificationSound('default'),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NotificationService] Background notification error: $e');
    }
  }


  @override
  void dispose() {
    _tokenSub?.cancel();
    _notifSub?.cancel();
    _notifRemovedSub?.cancel();
    _prefsSub?.cancel();
    _profileSub?.cancel();
    _reminderTimer?.cancel();
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
      final map = raw.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
      _notifSound = map['sound'] as bool? ?? true;
      _notifVibration = map['vibration'] as bool? ?? true;
      _notifCritical = map['critical'] as bool? ?? true;
      _notifFeeding = map['feeding'] as bool? ?? true;
      _notifSampling = map['sampling'] as bool? ?? false;
      notifyListeners();
    });
  }

  void _startReminderTimer() {
    _reminderTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkFeedingReminders();
      _confirmFeedingComplete();
      _checkSamplingReminders();
    });
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

      final schedMins = h * 60 + m;
      final nowMins = now.hour * 60 + now.minute;
      if (schedMins > 0 && nowMins == schedMins - 1) {
        final key = '${todayKey}_${s.time}_${s.ampm}';
        if (_feedingReminderSent.contains(key)) return;
        _feedingReminderSent.add(key);

        _addNotification(
          type: 'reminder',
          title: 'Feeding Reminder',
          message: 'Scheduled feeding at ${s.time} ${s.ampm} starts in 1 minute.',
          timestamp: now,
        );
      }
    }
  }

  void _confirmFeedingComplete() {
    if (_userRole == 'admin') return;
    if (!_notifFeeding) return;
    final now = DateTime.now();
    final todayKey = '${now.month}/${now.day}';
    final oneMinAgo = now.millisecondsSinceEpoch - 60000;

    for (final log in FeedState.feederLogs.value) {
      if (log.type != 'auto') continue;
      if (!log.action.contains('Auto feed dispensed')) continue;
      if (log.timestamp <= 0 || log.timestamp < oneMinAgo) continue;

      final confirmKey = 'confirm_${todayKey}_${log.timestamp}';
      if (_feedingReminderSent.contains(confirmKey)) return;
      _feedingReminderSent.add(confirmKey);

      _addNotification(
        type: 'reminder',
        title: 'Feeding Complete',
        message: 'Feed has been dispensed successfully.',
        timestamp: now,
      );
    }
  }

  void _checkSamplingReminders() {
    if (_userRole == 'admin') return;
    if (!_notifSampling) return;
    final now = DateTime.now();
    final todayKey = '${now.month}/${now.day}';
    if (_lastSamplingReminderDate == todayKey) return;

    final tank = TankService.instance;
    if (tank.daysSinceLastSampling >= 7 && tank.canSample) {
      _lastSamplingReminderDate = todayKey;
      _addNotification(
        type: 'reminder',
        title: 'Sampling Reminder',
        message: 'It\'s been ${tank.daysSinceLastSampling} days since last sampling. Time to record growth data!',
        timestamp: now,
      );
    }
  }

  void _listenFirebase() {
    _notifSub = _notifRef.onChildAdded.listen((e) {
      final key = e.snapshot.key;
      if (key == null || e.snapshot.value == null) return;
      if (_notifications.any((n) => n.id == key)) return;

      final raw = e.snapshot.value as Map<Object?, Object?>;
      final map = raw.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
      _notifications.add(
        NotificationItem(
          id: key,
          type: map['type'] ?? 'operational',
          title: map['title'] ?? '',
          message: map['message'] ?? '',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (map['timestamp'] as num).toInt(),
          ),
          unread: map['unread'] == true,
        ),
      );
      _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notifyListeners();
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
      unread: true,
    );

    _notifications.insert(0, notif);
    notifyListeners();

    fbRef.set({
      'type': notif.type,
      'title': notif.title,
      'message': notif.message,
      'timestamp': notif.timestamp.millisecondsSinceEpoch,
      'unread': notif.unread,
    }).catchError((e) {
      debugPrint('[NotificationService] Failed to save: $e');
    });

    // DO NOT show native system popups when the app is in the foreground
    debugPrint('[NotificationService] Local notification recorded in DB, skipping native banner in-app.');
  }

  void markAllRead() {
    for (final n in _notifications) {
      n.unread = false;
    }
    notifyListeners();
    _updateUnreadInFirebase();
  }

  void markAsRead(String id) {
    for (final n in _notifications) {
      if (n.id == id) {
        n.unread = false;
        notifyListeners();
        _updateUnreadInFirebase();
        return;
      }
    }
  }

  void _updateUnreadInFirebase() async {
    for (final n in _notifications.where((n) => !n.unread)) {
      try {
        await _notifRef.child(n.id).child('unread').set(false);
      } catch (_) {}
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
