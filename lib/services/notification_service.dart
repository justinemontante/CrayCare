import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import '../models/notification_item.dart';
import '../utils/prediction_timestamp.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  // Background FCM callbacks run in a separate isolate on Android. Initialize
  // Firebase here before touching Auth or Firestore; otherwise notification
  // preferences can silently fail to load and the handler may use defaults.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[FCM] Background Firebase initialization error: $e');
  }

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
  // Show only notifications created since the notification reset on
  // 2026-10-31. Existing Firestore documents stay intact but remain hidden.
  static final DateTime _notificationsVisibleFromUtc = DateTime.utc(
    2026,
    10,
    31,
    5,
    54,
    42,
  );
  static const int _notificationCacheLimit = 100;
  static const String _notificationCacheKeyPrefix = 'notifications_cache_v2_';
  static const String _notificationCursorSecondsKeyPrefix =
      'notifications_cursor_seconds_v2_';
  static const String _notificationCursorNanosKeyPrefix =
      'notifications_cursor_nanos_v2_';
  static const String _notificationCursorIdKeyPrefix =
      'notifications_cursor_id_v2_';
  final List<NotificationItem> _notifications = [];
  Future<void> _cacheWriteQueue = Future<void>.value();
  Timestamp? _notificationCursor;
  String? _notificationCursorId;
  int _notificationSyncGeneration = 0;
  bool _initialized = false;
  bool _notifSound = true;
  bool _notifVibration = true;
  bool _notifCritical = true;
  bool _notifWarning = true;
  bool _notifFeeding = true;
  bool _notifSampling = true;
  bool _notifOperational = true;
  String? _userRole;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _profileFirestoreSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _prefsSub;
  String? _notificationListenerUid;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _appSettingsChannel = MethodChannel(
    'com.example.craycare/app_settings',
  );
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;

  Iterable<NotificationItem> get _visibleNotifications => _notifications.where(
    (notification) =>
        !notification.created_at.toUtc().isBefore(_notificationsVisibleFromUtc),
  );
  List<NotificationItem> get notifications =>
      List.unmodifiable(_visibleNotifications);

  bool unreadStatus(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return false;
    final idx = _notifications.indexWhere((n) => n.id == id);
    return idx != -1 && _notifications[idx].isUnread;
  }

  int get unreadCount {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return uid.isEmpty
        ? 0
        : _visibleNotifications.where((n) => n.isUnread).length;
  }

  int get criticalCount => _visibleNotifications
      .where((n) => n.notif_type == 'critical' && _isToday(n.created_at))
      .length;
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
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _notifications.clear();
      _cancelSubscriptions();
      _notificationCursor = null;
      _notificationCursorId = null;
      _notificationSyncGeneration++;
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
            _notifSub = null;
            _notificationListenerUid = null;
            _prefsSub?.cancel();
            _prefsSub = null;
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
      await _tokenSub?.cancel();
      _tokenSub = messaging.onTokenRefresh.listen(_saveToken);
      await _foregroundMessageSub?.cancel();
      _foregroundMessageSub = FirebaseMessaging.onMessage.listen(
        _onForegroundMessage,
      );
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
      // Save for owner AND unknown/null role (fresh-login race).
      // Admin cleanup happens on next role sync if needed.
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
    _authSub?.cancel();
    _authSub = null;
    _tokenSub?.cancel();
    _tokenSub = null;
    _foregroundMessageSub?.cancel();
    _foregroundMessageSub = null;
    _notifSub?.cancel();
    _notifSub = null;
    _notificationListenerUid = null;
    _prefsSub?.cancel();
    _prefsSub = null;
    _profileFirestoreSub?.cancel();
    _profileFirestoreSub = null;
    _initialized = false;
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
    _notificationSyncGeneration++;
    _notifSub?.cancel();
    _prefsSub?.cancel();
    _profileFirestoreSub?.cancel();
    _notifSub = null;
    _notificationListenerUid = null;
    _prefsSub = null;
    _profileFirestoreSub = null;
  }

  void _listenFirebase() {
    if (_userRole != 'owner') return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    // Profile snapshots can fire for unrelated profile changes. Keep the
    // existing query listener instead of restarting it and leaving old
    // in-memory notifications behind.
    if (_notificationListenerUid == uid) return;

    _notifSub?.cancel();
    _notificationListenerUid = uid;
    final generation = ++_notificationSyncGeneration;
    unawaited(_startNotificationSync(uid, generation));
  }

  Future<void> _startNotificationSync(String uid, int generation) async {
    await _loadNotificationCache(uid);
    if (!_isCurrentNotificationSync(uid, generation)) return;

    final collection = FirebaseFirestore.instance
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .where(
          'created_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            _notificationsVisibleFromUtc,
          ),
        );

    if (_notificationCursor == null || _notificationCursorId == null) {
      final initialQuery = collection
          .orderBy('created_at', descending: true)
          .limit(_notificationCacheLimit);
      QuerySnapshot<Map<String, dynamic>>? initial;
      try {
        initial = await initialQuery.get(
          const GetOptions(source: Source.serverAndCache),
        );
      } catch (error) {
        debugPrint('[Notif] Initial server sync failed: $error');
        try {
          initial = await initialQuery.get(
            const GetOptions(source: Source.cache),
          );
        } catch (cacheError) {
          debugPrint('[Notif] Initial cache sync failed: $cacheError');
        }
      }
      if (!_isCurrentNotificationSync(uid, generation)) return;
      if (initial != null) {
        for (final doc in initial.docs) {
          _upsertNotification(doc.id, doc.data());
          if (!initial.metadata.isFromCache) {
            _advanceNotificationCursor(doc.id, doc.data());
          }
        }
        _sortAndLimitNotifications();
        _persistNotificationCache(uid);
        notifyListeners();
      }
    }

    if (!_isCurrentNotificationSync(uid, generation)) return;
    var liveQuery = collection
        .orderBy('created_at')
        .orderBy(FieldPath.documentId);
    final cursor = _notificationCursor;
    final cursorId = _notificationCursorId;
    if (cursor != null && cursorId != null) {
      liveQuery = liveQuery.startAfter([cursor, cursorId]);
    }
    _notifSub = liveQuery
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snapshot) {
            if (!_isCurrentNotificationSync(uid, generation)) return;
            var changed = false;
            for (final change in snapshot.docChanges) {
              final doc = change.doc;
              if (change.type == DocumentChangeType.removed) {
                final beforeCount = _notifications.length;
                _notifications.removeWhere((n) => n.id == doc.id);
                changed |= _notifications.length != beforeCount;
                continue;
              }
              final data = doc.data();
              if (data == null) continue;
              changed |= _upsertNotification(doc.id, data);
              if (!snapshot.metadata.isFromCache) {
                _advanceNotificationCursor(doc.id, data);
              }
            }
            if (changed || !snapshot.metadata.isFromCache) {
              _sortAndLimitNotifications();
              _persistNotificationCache(uid);
              notifyListeners();
            }
          },
          onError: (Object error) {
            debugPrint('[Notif] Incremental notification sync failed: $error');
          },
        );
  }

  bool _isCurrentNotificationSync(String uid, int generation) =>
      generation == _notificationSyncGeneration &&
      _notificationListenerUid == uid &&
      FirebaseAuth.instance.currentUser?.uid == uid;

  Future<void> _loadNotificationCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_notificationCacheKeyPrefix$uid');
      final cached = <NotificationItem>[];
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final value in decoded) {
            if (value is! Map) continue;
            final map = Map<String, dynamic>.from(value);
            final createdMs = map['created_at_ms'];
            if (map['id'] is! String || createdMs is! num) continue;
            final createdAt = DateTime.fromMillisecondsSinceEpoch(
              createdMs.toInt(),
              isUtc: true,
            ).toLocal();
            if (createdAt.toUtc().isBefore(_notificationsVisibleFromUtc)) {
              continue;
            }
            cached.add(
              NotificationItem(
                id: map['id'] as String,
                notif_type: map['notif_type']?.toString() ?? 'operational',
                title: map['title']?.toString() ?? '',
                body: map['body']?.toString() ?? '',
                created_at: createdAt,
                is_read: map['is_read'] as bool? ?? false,
              ),
            );
          }
        }
      }
      final seconds = prefs.getInt('$_notificationCursorSecondsKeyPrefix$uid');
      final nanos = prefs.getInt('$_notificationCursorNanosKeyPrefix$uid');
      final cursorId = prefs.getString('$_notificationCursorIdKeyPrefix$uid');
      _notifications
        ..clear()
        ..addAll(cached);
      if (seconds != null && nanos != null && cursorId != null) {
        _notificationCursor = Timestamp(seconds, nanos);
        _notificationCursorId = cursorId;
      }
      _sortAndLimitNotifications();
      notifyListeners();
    } catch (error) {
      debugPrint('[Notif] Could not load local notification cache: $error');
    }
  }

  bool _upsertNotification(String id, Map<String, dynamic> data) {
    final createdAt = parsePredictionTimestamp(data['created_at'])?.toLocal();
    if (createdAt == null ||
        createdAt.toUtc().isBefore(_notificationsVisibleFromUtc)) {
      return false;
    }
    final notification = NotificationItem(
      id: id,
      notif_type: data['notif_type']?.toString() ?? 'operational',
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      created_at: createdAt,
      is_read: data['is_read'] as bool? ?? false,
    );
    final index = _notifications.indexWhere((item) => item.id == id);
    if (index == -1) {
      _notifications.add(notification);
      return true;
    }
    final previous = _notifications[index];
    if (previous.notif_type == notification.notif_type &&
        previous.title == notification.title &&
        previous.body == notification.body &&
        previous.created_at == notification.created_at &&
        previous.is_read == notification.is_read) {
      return false;
    }
    _notifications[index] = notification;
    return true;
  }

  void _advanceNotificationCursor(String id, Map<String, dynamic> data) {
    final value = data['created_at'];
    if (value is! Timestamp) return;
    final current = _notificationCursor;
    final comparison = current == null ? 1 : value.compareTo(current);
    if (comparison > 0 ||
        (comparison == 0 &&
            (_notificationCursorId == null ||
                id.compareTo(_notificationCursorId!) > 0))) {
      _notificationCursor = value;
      _notificationCursorId = id;
    }
  }

  void _sortAndLimitNotifications() {
    _notifications.sort((a, b) => b.created_at.compareTo(a.created_at));
    if (_notifications.length > _notificationCacheLimit) {
      _notifications.removeRange(
        _notificationCacheLimit,
        _notifications.length,
      );
    }
  }

  void _persistNotificationCache(String uid) {
    final content = jsonEncode(
      _notifications
          .map(
            (notification) => {
              'id': notification.id,
              'notif_type': notification.notif_type,
              'title': notification.title,
              'body': notification.body,
              'created_at_ms': notification.created_at
                  .toUtc()
                  .millisecondsSinceEpoch,
              'is_read': notification.is_read,
            },
          )
          .toList(growable: false),
    );
    final cursor = _notificationCursor;
    final cursorId = _notificationCursorId;
    _cacheWriteQueue = _cacheWriteQueue
        .then((_) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('$_notificationCacheKeyPrefix$uid', content);
          if (cursor != null && cursorId != null) {
            await prefs.setInt(
              '$_notificationCursorSecondsKeyPrefix$uid',
              cursor.seconds,
            );
            await prefs.setInt(
              '$_notificationCursorNanosKeyPrefix$uid',
              cursor.nanoseconds,
            );
            await prefs.setString(
              '$_notificationCursorIdKeyPrefix$uid',
              cursorId,
            );
          }
        })
        .catchError((Object error) {
          debugPrint('[Notif] Could not save local notification cache: $error');
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
    _persistNotificationCache(uid);
  }

  void markAsRead(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    for (final n in _visibleNotifications) {
      if (n.id == id) {
        n.is_read = true;
        notifyListeners();
        FirebaseFirestore.instance
            .collection('notifications')
            .doc(id)
            .update({'is_read': true})
            .catchError((_) {});
        _persistNotificationCache(uid);
        return;
      }
    }
  }

  Future<void> clearAll() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      final batch = FirebaseFirestore.instance.batch();
      final idsToDelete = _visibleNotifications.map((n) => n.id).toList();
      for (final id in idsToDelete) {
        batch.delete(
          FirebaseFirestore.instance.collection('notifications').doc(id),
        );
      }
      if (idsToDelete.isNotEmpty) await batch.commit();
      _notifications.removeWhere((n) => idsToDelete.contains(n.id));
      _persistNotificationCache(uid);
      notifyListeners();
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
