import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'sensor_service.dart';
import '../models/notification_item.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final List<NotificationItem> _notifications = [];
  final Map<String, String> _previousZones = {};
  int _idCounter = 0;
  bool _initialized = false;

  final DatabaseReference _notifRef = FirebaseDatabase.instance.ref(
    'notifications',
  );
  StreamSubscription<DatabaseEvent>? _notifSub;
  StreamSubscription<DatabaseEvent>? _notifRemovedSub;

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
    SensorService.instance.addListener(_onSensorUpdate);
    _initPreviousStates();
  }

  Future<void> initFCM() async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(
        android: androidSettings,
      );
      await _localNotifications.initialize(initSettings);

      const androidChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      final messaging = FirebaseMessaging.instance;

      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
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
        await FirebaseDatabase.instance
            .ref('users/${user.uid}/fcmToken')
            .set(token);
      }
    } catch (e) {
      debugPrint('[NotificationService] Token save error: $e');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? 'CrayCare Alert';
    final body = message.notification?.body ?? '';

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _onBackgroundMessage(RemoteMessage message) async {
    debugPrint('[NotificationService] Background msg: ${message.messageId}');
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    _notifSub?.cancel();
    _notifRemovedSub?.cancel();
    SensorService.instance.removeListener(_onSensorUpdate);
    super.dispose();
  }

  void _initPreviousStates() {
    for (final key in SensorService.sensorKeys) {
      final zone = SensorService.instance.getZone(key);
      _previousZones[key] = zone;
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

      if (prevZone != null && zone == 'CRITICAL' && prevZone != 'CRITICAL') {
        _addNotification(
          type: 'critical',
          title: 'Critical: $label',
          message: unit.isNotEmpty
              ? '$label dropped to ${value.toStringAsFixed(1)} $unit.'
              : '$label is at ${value.toStringAsFixed(1)}.',
          timestamp: now,
        );
      } else if (prevZone != null &&
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
