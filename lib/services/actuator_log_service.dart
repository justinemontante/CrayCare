import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/control_types.dart';
import '../utils/prediction_timestamp.dart';

class AutoActuatorEvent {
  final String eventId;
  final String actuatorId;
  final String actuatorLabel;
  final String action;
  final DateTime timestamp;
  const AutoActuatorEvent({
    required this.eventId,
    required this.actuatorId,
    required this.actuatorLabel,
    required this.action,
    required this.timestamp,
  });
}

class ActuatorLogService extends ChangeNotifier {
  static final ActuatorLogService instance = ActuatorLogService._();
  ActuatorLogService._();

  static const actuatorIds = ['aerator1', 'aerator2', 'pump'];
  static const actuatorLabels = {
    'aerator1': 'Aerator 1',
    'aerator2': 'Aerator 2',
    'pump': 'Water Pump',
  };

  final Map<String, List<LogEntry>> _logs = {};
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs = [];
  bool _initialized = false;
  bool _warmup = true;
  final Set<String> _seenKeys = {};
  StreamSubscription<User?>? _authSub;
  String? _listeningUid;

  final StreamController<AutoActuatorEvent> _autoControlController =
      StreamController<AutoActuatorEvent>.broadcast();
  Stream<AutoActuatorEvent> get autoControlEvents => _autoControlController.stream;

  void init() {
    if (_initialized) return;
    _initialized = true;

    // authStateChanges emits the current auth state immediately after the
    // listener is registered. Use that single startup path instead of also
    // calling _restartListening(currentUser), which could race the initial
    // auth event and attach two sets of actuator Firestore listeners.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(_restartListening(user));
    });
  }

  Future<void> _restartListening(User? user) async {
    final uid = user?.uid;
    if (uid != null && uid == _listeningUid && _subs.isNotEmpty) return;

    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    _logs.clear();
    _seenKeys.clear();
    _warmup = true;
    _listeningUid = uid;

    if (uid == null) {
      notifyListeners();
      return;
    }

    try {
      final profileDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final profile = profileDoc.data();
      // Admins do not own operational tank data and Firestore rules deny these
      // reads, so do not create noisy listeners for an admin account.
      if (profile?['role'] == 'admin') {
        notifyListeners();
        return;
      }
      final tankId = uid;
      await _startTankListeners(uid, tankId);
    } catch (e) {
      debugPrint('[ActuatorLogService] Listener setup error: $e');
      notifyListeners();
    }
  }

  Future<void> _startTankListeners(String uid, String tankId) async {
    // Abort if auth changed while the profile lookup was in flight.
    if (_listeningUid != uid || FirebaseAuth.instance.currentUser?.uid != uid) {
      return;
    }

    final tankLogsRef = FirebaseFirestore.instance
        .collection('tanks')
        .doc(tankId)
        .collection('actuator_logs');

    for (final actuatorId in actuatorIds) {
      _logs[actuatorId] = [];
      final sub = tankLogsRef
          .where('actuator_type', isEqualTo: actuatorId)
          .orderBy('logged_at', descending: true)
          .limit(50)
          .snapshots()
          .listen((snapshot) {
        // Ignore a late event from a subscription whose account was replaced.
        if (_listeningUid != uid) return;

        final list = snapshot.docs.map((doc) {
          final map = doc.data();
          // Accept the canonical epoch-ms value plus legacy/admin-written
          // Timestamp, DateTime, ISO string, or epoch-second representations.
          final parsed = parsePredictionTimestamp(map['logged_at']);
          final dt = parsed?.toLocal();
          final ts = parsed?.millisecondsSinceEpoch ?? 0;
          return LogEntry(
            map['action'] as String? ?? '',
            map['type'] as String? ?? '',
            dt == null ? '' : _formatTime(dt),
            dt == null ? '' : _formatDate(dt),
            timestamp: ts,
          );
        }).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        _logs[actuatorId] = list;
        notifyListeners();

        if (!_warmup) {
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final data = change.doc.data();
            if (data == null) continue;
            final action = data['action'] as String? ?? '';
            final key = change.doc.id;
            if (_seenKeys.contains(key)) continue;
            _seenKeys.add(key);
            if (!action.contains('(AUTO)')) continue;

            final ts = parsePredictionTimestamp(data['logged_at']);
            if (ts == null) continue;
            final label = actuatorLabels[actuatorId] ?? actuatorId;

            _autoControlController.add(AutoActuatorEvent(
              eventId: change.doc.id,
              actuatorId: actuatorId,
              actuatorLabel: label,
              action: action,
              timestamp: ts.toLocal(),
            ));
          }
        }
      }, onError: (e) {
        if (_listeningUid == uid) {
          debugPrint('[ActuatorLogService] $actuatorId stream error: $e');
        }
      });
      _subs.add(sub);
    }

    Future.delayed(const Duration(seconds: 3), () {
      if (_listeningUid == uid) _warmup = false;
    });
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Formats an epoch-ms timestamp as "3:45 PM" (matches the old ESP32
  /// pre-formatted string).
  static String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }

  /// Formats an epoch-ms timestamp as "Aug 17, 2026".
  static String _formatDate(DateTime dt) =>
      '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

  List<LogEntry> getLogs(String actuatorId) => _logs[actuatorId] ?? [];

  Map<String, List<LogEntry>> get allLogs => Map.unmodifiable(_logs);

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _authSub?.cancel();
    _authSub = null;
    _autoControlController.close();
    super.dispose();
  }
}
