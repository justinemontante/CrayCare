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
    _loadFromFirebase();
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
    SensorService.instance.removeListener(_onSensorUpdate);
    super.dispose();
  }

  void _initPreviousStates() {
    for (final key in SensorService.sensorKeys) {
      final zone = SensorService.instance.getZone(key);
      if (zone == 'CRITICAL') {
        _previousZones[key] = 'CRITICAL';
      }
    }
  }

  void _loadFromFirebase() async {
    try {
      final snapshot = await _notifRef
          .orderByChild('timestamp')
          .limitToLast(200)
          .once();
      if (snapshot.snapshot.value == null) return;
      final data = Map<String, dynamic>.from(snapshot.snapshot.value as Map);
      final entries = data.entries.toList()
        ..sort((a, b) {
          final ta = (a.value as Map)['timestamp'] ?? 0;
          final tb = (b.value as Map)['timestamp'] ?? 0;
          return (tb as int).compareTo(ta as int);
        });

      for (final entry in entries) {
        final fbKey = entry.key;
        final map = Map<String, dynamic>.from(entry.value as Map);
        _notifications.add(
          NotificationItem(
            id: map['localId'] ?? 'fb_$fbKey',
            type: map['type'] ?? 'operational',
            title: map['title'] ?? '',
            message: map['message'] ?? '',
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              (map['timestamp'] as num).toInt(),
            ),
            unread: map['unread'] == true,
          ),
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[NotificationService] Failed to load from Firebase: $e');
    }
  }

  void _onSensorUpdate() {
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
    _idCounter++;
    final localId = 'notif_$_idCounter';
    final notif = NotificationItem(
      id: localId,
      type: type,
      title: title,
      message: message,
      timestamp: timestamp,
      unread: true,
    );

    _notifications.insert(0, notif);
    notifyListeners();

    _saveToFirebase(notif);
  }

  void _saveToFirebase(NotificationItem notif) {
    try {
      _notifRef.push().set({
        'localId': notif.id,
        'type': notif.type,
        'title': notif.title,
        'message': notif.message,
        'timestamp': notif.timestamp.millisecondsSinceEpoch,
        'unread': notif.unread,
      });
    } catch (e) {
      debugPrint('[NotificationService] Failed to save notification: $e');
    }
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
    try {
      final snapshot = await _notifRef.once();
      if (snapshot.snapshot.value == null) return;
      final data = Map<String, dynamic>.from(snapshot.snapshot.value as Map);
      for (final entry in data.entries) {
        final map = Map<String, dynamic>.from(entry.value as Map);
        if (map['unread'] == true &&
            _notifications
                    .where((n) => n.id == map['localId'])
                    .firstOrNull
                    ?.unread ==
                false) {
          await _notifRef.child(entry.key).child('unread').set(false);
        }
      }
    } catch (e) {
      debugPrint(
        '[NotificationService] Failed to update unread in Firebase: $e',
      );
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
