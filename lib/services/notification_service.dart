import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/notification_item.dart';

/// TOP-LEVEL background message handler — required by Firebase Messaging.
/// Must be outside any class and annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background msg: ${message.messageId}');

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
    final isCritical = data['critical'] == 'true';
    // Only treat as a warning-only event when critical is explicitly "false"
    // (resolved sensor event) or absent (non-sensor push). Critical pushes
    // also carry warning: "true", so reading warning alone would hide the
    // critical alert whenever the owner disabled only the warning toggle.
    final isWarning = !isCritical && data['warning'] == 'true';
    final isOperational = data['operational'] == 'true';
    if (!isCritical && !isFeeding && !isSampling && !isWarning && !isOperational) return;

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

          // Critical alerts always win. Only respect the per-category
          // toggles once we know the push is not critical.
          if (isCritical && map['critical'] == false) {
            debugPrint('[FCM] Skipping critical notification because it is turned off in preferences.');
            return;
          }
          if (!isCritical) {
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

  String? _userRole;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileFirestoreSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _prefsSub;
  bool unreadStatus(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return false;
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return false;
    return _notifications[idx].isUnreadBy(uid);
  }

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
    // Sensor/actuator alert documents are created server-side by the
    // Cloud Functions (onSensorUpdate, onAutoActuatorLogCreate).
    if (FirebaseAuth.instance.currentUser != null) {
      _listenFirebase();
      _loadUserPrefs();
    }

    FirebaseAuth.instance.authStateChanges().listen((user) {
      _notifications.clear();
      _cancelSubscriptions();
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

    final isFeeding = data['feeding'] == 'true';
    final isSampling = data['sampling'] == 'true';
    final isCritical = data['critical'] == 'true';
    // Same logic as the background handler: critical payloads also carry
    // warning="true", so only treat warning as its own category when the
    // critical flag is not set.
    final isWarning = !isCritical && data['warning'] == 'true';
    final isOperational = data['operational'] == 'true';
    if (!isCritical && !isFeeding && !isSampling && !isWarning && !isOperational) return;

    // Critical alerts bypass every other toggle; only the Critical toggle
    // can silence them. This prevents a disabled Warning toggle from hiding
    // a Critical alert that ships in the same FCM payload.
    if (isCritical && !_notifCritical) return;
    if (!isCritical) {
      if (isFeeding && !_notifFeeding) return;
      if (isSampling && !_notifSampling) return;
      if (isWarning && !_notifWarning) return;
    }

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

  void _cancelSubscriptions() {
    _notifSub?.cancel();
    _prefsSub?.cancel();
    _profileFirestoreSub?.cancel();
    _profileFirestoreSub = null;
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
    String? documentId,
  }) {
    if (_userRole == 'admin') return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    final docRef = FirebaseFirestore.instance.collection('notifications').doc(documentId);
    if (_notifications.any((n) => n.id == docRef.id)) return;
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

  static const _manilaOffset = Duration(hours: 8);
  DateTime _manilaNow() => DateTime.now().toUtc().add(_manilaOffset);

  bool _isToday(DateTime dt) {
    final now = _manilaNow();
    final dtManila = dt.isUtc ? dt.add(_manilaOffset) : dt;
    return dtManila.year == now.year &&
        dtManila.month == now.month &&
        dtManila.day == now.day;
  }
}
