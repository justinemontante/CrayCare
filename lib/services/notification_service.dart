import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import '../models/notification_item.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background msg: ${message.messageId}');
  if (message.notification != null) {
    debugPrint(
      '[FCM] Notification payload present, system will handle display.',
    );
    return;
  }
  try {
    final localNotif = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    await localNotif.initialize(
      const InitializationSettings(android: androidSettings),
    );
    final manager = localNotif
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
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
    final isCritical = data['critical'] == 'true';
    final isWarning = !isCritical && data['warning'] == 'true';
    final isOperational = data['operational'] == 'true';
    if (!isCritical &&
        !isFeeding &&
        !isSampling &&
        !isWarning &&
        !isOperational) {
      return;
    }
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
          final map = prefsDoc.data()!;
          if (isCritical && map['critical'] == false) return;
          if (!isCritical) {
            if (isFeeding && map['feeding'] == false) return;
            if (isSampling && map['sampling'] == false) return;
            if (isWarning && map['warning'] == false) return;
            if (isOperational && map['operational'] == false) return;
          }
        }
      }
    } catch (e) {
      debugPrint('[FCM] Error reading preferences in background: $e');
    }
    final playSound = data['sound'] != 'false';
    final vibrate = data['vibration'] != 'false';
    final title =
        data['title'] ?? message.notification?.title ?? 'CrayCare Alert';
    final body =
        data['body'] ?? message.notification?.body ?? data['message'] ?? '';
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
          sound: !playSound
              ? null
              : const RawResourceAndroidNotificationSound('default'),
        ),
      ),
    );
  } catch (e) {
    debugPrint('[FCM] Background notification error: $e');
  }
}

class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._();
  final List<NotificationItem> _notifications = [];
  bool _initialized = false;
  bool _notifSound = true;
  bool _notifVibration = true;
  bool _notifCritical = true;
  bool _notifWarning = true;
  bool _notifFeeding = true;
  bool _notifSampling = true;
  bool _notifOperational = true;
  String? _userRole;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _profileFirestoreSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _prefsSub;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _appSettingsChannel = MethodChannel(
    'com.example.craycare/app_settings',
  );
  StreamSubscription? _tokenSub;

  Iterable<NotificationItem> get _visibleNotifications =>
      _notifications.where((n) => n.notif_type != 'device_auto');
  List<NotificationItem> get notifications =>
      List.unmodifiable(_visibleNotifications);

  bool unreadStatus(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return false;
    final idx = _notifications.indexWhere((n) => n.id == id);
    return idx != -1 && _notifications[idx].isUnreadBy(uid);
  }

  int get unreadCount {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return uid.isEmpty
        ? 0
        : _visibleNotifications.where((n) => n.isUnreadBy(uid)).length;
  }

  int get criticalCount =>
      _visibleNotifications.where((n) => n.notif_type == 'critical').length;
  List<NotificationItem> get todayNotifications =>
      _visibleNotifications.where((n) => _isToday(n.created_at)).toList();
  int get todayCount => todayNotifications.length;
  int get reminderCount =>
      _visibleNotifications.where((n) => n.notif_type == 'reminder').length;

  void init() {
    if (_initialized) return;
    _initialized = true;
    if (FirebaseAuth.instance.currentUser != null) {
      _listenProfile();
    }
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _notifications.clear();
      _cancelSubscriptions();
      _userRole = null;
      if (user != null) _listenProfile();
      notifyListeners();
    });
  }

  Future<void> _removeCurrentDeviceToken(User user, String token) async {
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final snap = await userRef.get();
    final updates = <String, dynamic>{
      'fcmTokens': FieldValue.arrayRemove([token]),
    };
    if (snap.data()?['fcmToken'] == token) {
      updates['fcmToken'] = FieldValue.delete();
    }
    await userRef.update(updates);
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
          _userRole = profile['role']?.toString().trim().toLowerCase();
          if (_userRole == 'admin') {
            _notifSub?.cancel();
            _prefsSub?.cancel();
            _notifications.clear();
            try {
              final token = await FirebaseMessaging.instance.getToken();
              if (token != null) await _removeCurrentDeviceToken(user, token);
            } catch (e, stack) {
              debugPrint('[Notif] FCM token cleanup error: $e\n$stack');
            }
            notifyListeners();
          } else {
            _listenFirebase();
            _loadUserPrefs();
            try {
              final token = await FirebaseMessaging.instance.getToken();
              if (token != null) await _saveToken(token);
            } catch (e, stack) {
              debugPrint('[Notif] token error: $e\n$stack');
            }
          }
        });
  }

  Future<void> initFCM() async {
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      await _localNotifications.initialize(
        const InitializationSettings(android: androidSettings),
      );
      final manager = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
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
      final messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
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

  Future<AuthorizationStatus> notificationAuthorizationStatus() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus;
  }

  Future<bool> requestNotificationPermission() async {
    try {
      final manager = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await manager?.requestNotificationsPermission();

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('[NotificationService] Permission request error: $e');
      return false;
    }
  }

  Future<bool> openNotificationSettings() async {
    try {
      return await _appSettingsChannel.invokeMethod<bool>(
            'openNotificationSettings',
          ) ??
          false;
    } on PlatformException catch (e) {
      debugPrint('[NotificationService] Open settings error: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      if (_userRole == 'admin') {
        await _removeCurrentDeviceToken(user, token);
        return;
      }
      if (_userRole != 'owner') return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[NotificationService] Token save error: $e');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final isFeeding = data['feeding'] == 'true';
    final isSampling = data['sampling'] == 'true';
    final isCritical = data['critical'] == 'true';
    final isWarning = !isCritical && data['warning'] == 'true';
    final isOperational = data['operational'] == 'true';
    if (!isCritical &&
        !isFeeding &&
        !isSampling &&
        !isWarning &&
        !isOperational) {
      return;
    }
    if (isCritical && !_notifCritical) return;
    if (!isCritical) {
      if (isFeeding && !_notifFeeding) return;
      if (isSampling && !_notifSampling) return;
      if (isWarning && !_notifWarning) return;
      if (isOperational && !_notifOperational) return;
    }
    final playSound = data['sound'] != 'false' && _notifSound;
    final vibrate = data['vibration'] != 'false' && _notifVibration;
    final title =
        data['title'] ?? message.notification?.title ?? 'CrayCare Alert';
    final body =
        data['body'] ?? message.notification?.body ?? data['message'] ?? '';
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
            sound: !playSound
                ? null
                : const RawResourceAndroidNotificationSound('default'),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NotificationService] Foreground notification error: $e');
    }
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    _notifSub?.cancel();
    _prefsSub?.cancel();
    _profileFirestoreSub?.cancel();
    super.dispose();
  }

  void _loadUserPrefs() {
    if (_userRole != 'owner') return;
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
          _notifOperational = map['operational'] as bool? ?? true;
          notifyListeners();
        });
  }

  void _cancelSubscriptions() {
    _notifSub?.cancel();
    _prefsSub?.cancel();
    _profileFirestoreSub?.cancel();
    _profileFirestoreSub = null;
  }

  void _listenFirebase() {
    if (_userRole != 'owner') return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    _notifSub?.cancel();
    _notifSub = FirebaseFirestore.instance
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
              DateTime createdDt;
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
              if (idx != -1) _notifications[idx].is_read = isReadRaw;
            } else if (change.type == DocumentChangeType.removed) {
              _notifications.removeWhere((n) => n.id == key);
            }
          }
          _notifications.sort((a, b) => b.created_at.compareTo(a.created_at));
          notifyListeners();
        });
  }

  void markAllRead() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    final visible = _visibleNotifications.toList();
    for (final n in visible) {
      n.is_read = true;
    }
    notifyListeners();
    final fs = FirebaseFirestore.instance;
    for (final n in visible) {
      fs
          .collection('notifications')
          .doc(n.id)
          .update({'is_read': true})
          .catchError((_) {});
    }
  }

  void markAsRead(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    for (final n in _notifications) {
      if (n.id == id) {
        n.is_read = true;
        notifyListeners();
        FirebaseFirestore.instance
            .collection('notifications')
            .doc(id)
            .update({'is_read': true})
            .catchError((_) {});
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

  static const _manilaOffset = Duration(hours: 8);
  DateTime _manilaNow() => DateTime.now().toUtc().add(_manilaOffset);
  DateTime _toManila(DateTime dt) => dt.toUtc().add(_manilaOffset);
  bool _isToday(DateTime dt) {
    final now = _manilaNow();
    final value = _toManila(dt);
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }
}
