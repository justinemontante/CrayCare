import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/control_types.dart';
import 'connectivity_service.dart';
import 'sensor_service.dart';
import 'settings_service.dart';

class FeederService extends ChangeNotifier {
  static final FeederService instance = FeederService._();
  FeederService._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Formats an epoch-ms timestamp as "3:45 PM" (matches the old pre-formatted
  /// string the ESP32 used to send).
  static String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }

  /// Formats an epoch-ms timestamp as "Aug 17, 2026".
  static String _formatDate(DateTime dt) =>
      '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

  // The feeder schedule times (and the Cloud Function that dispatches/confirms
  // them) are always expressed in Asia/Manila wall-clock time, regardless of
  // where the viewing device is physically located (e.g. someone
  // checking in from a different timezone). Using DateTime.now() directly
  // would compare schedule times against the DEVICE's local clock instead,
  // causing missed-schedule false positives and feederDispatched date-key
  // mismatches with the Cloud Function (functions/notifications/index.js,
  // which hardcodes MANILA_OFFSET_MS). Mirror that same fixed +8h approach
  // here so both sides agree on "today" and "now".
  static const _manilaOffset = Duration(hours: 8);
  DateTime _manilaNow() => DateTime.now().toUtc().add(_manilaOffset);

  bool _initialized = false;

  /// Resolved tank_id for the signed-in user. Feeder data now lives under
  /// tanks/{tank_id}/feeder, feeder_schedules, feeder_logs, feeder_commands.
  String? _tankId;

  Future<String?> _resolveTankId() async {
    if (_tankId != null) return _tankId;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final profileDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final profile = profileDoc.data();
    if (profile?['role'] == 'admin') return null;
    var tankId = profile?['tank_id'] as String?;
    if (tankId == null || tankId.isEmpty) {
      tankId = uid;
      // Same safe legacy claim used by SensorService/TankService.
      await profileDoc.reference.set({'tank_id': uid}, SetOptions(merge: true));
    }
    _tankId = tankId;
    return _tankId;
  }

  DocumentReference<Map<String, dynamic>>? _tankDoc() =>
      _tankId == null ? null : FirebaseFirestore.instance.collection('tanks').doc(_tankId);

  StreamSubscription? _statusSub;
  StreamSubscription? _schedulesSub;
  StreamSubscription? _logsSub;

  bool _isRunning = false;
  String _feedSource = '';
  int _feedCount = 0;
  double _hopperLevel = 100;
  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastError;
  String _feederError = '';

  final List<LogEntry> _logs = [];
  final List<ScheduleItem> _schedules = [];
  final List<String> _scheduleKeys = [];

  Timer? _scheduleTimer;
  String _lastCheckDate = '';
  final Set<String> _missedLogged = {};

  bool get isRunning => _isRunning;
  String get feedSource => _feedSource;
  int get feedCount => _feedCount;
  double get hopperLevel => _hopperLevel;
  DateTime get lastSeen => _lastSeen;
  String? get lastError => _lastError;
  String get feederError => _feederError;

  bool get isOnline =>
      DateTime.now().difference(_lastSeen).inSeconds < 30;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  List<ScheduleItem> get schedules => List.unmodifiable(_schedules);

  void init() {
    if (_initialized) return;
    _initialized = true;
    try {
      _startScheduleTimer();
      if (FirebaseAuth.instance.currentUser != null) {
        _reinitListeners();
      }
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          _cancelSubscriptions();
          _tankId = null;
          _reinitListeners();
        } else {
          _cancelSubscriptions();
          _tankId = null;
        }
      });
    } catch (e) {
      debugPrint('[FeederService] Initialization error: $e');
    }
    ConnectivityService.instance.addOnConnectCallback(_onReconnect);
  }

  Future<void> _reinitListeners() async {
    final tankId = await _resolveTankId();
    if (tankId == null) {
      debugPrint('[FeederService] No tank_id resolved for user; feeder listeners not started.');
      return;
    }
    _listenStatus();
    _listenSchedules();
    _listenLogs();
  }

  bool canFeedNow() {
    final ranges = SettingsService.instance.currentRanges;
    final turbMax = ranges['turb']?['max'] ?? 999.0;
    final turb = SensorService.instance.getLatestValue('turb');
    if (SensorService.instance.turbidityAir) return false;
    if (turb > turbMax) return false;
    return true;
  }

  void _onReconnect() {
    debugPrint('[FeederService] Internet reconnected — refreshing listeners');
    if (FirebaseAuth.instance.currentUser != null) {
      _cancelSubscriptions();
      unawaited(_reinitListeners());
    }
  }

  void _cancelSubscriptions() {
    _statusSub?.cancel();
    _schedulesSub?.cancel();
    _logsSub?.cancel();
    _statusSub = null;
    _schedulesSub = null;
    _logsSub = null;
  }

  void _listenStatus() {
    _statusSub?.cancel();
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    try {
      _statusSub = tankDoc
          .collection('feeder')
          .doc('status')
          .snapshots()
          .listen((snapshot) {
        _lastError = null;
        if (!snapshot.exists || snapshot.data() == null) return;
        try {
          final data = snapshot.data()!;
          _isRunning = data['isRunning'] == true || data['status'] == 'dispensing';
          _feedSource = (data['feedSource'] as String?) ?? '';
          _feedCount = (data['feedCount'] as num?)?.toInt() ?? _feedCount;
          _hopperLevel = (data['hopperLevel'] as num?)?.toDouble() ?? 100;
          // Device status is ESP-owned. The app only displays feederError;
          // firmware clears it on its next heartbeat. Owner-side writes here
          // were denied by the security rules and caused noisy permission errors.
          _feederError = (data['feederError'] as String?) ?? '';
          final seen = data['lastSeen'];
          if (seen is int && seen > 0) {
            _lastSeen = DateTime.fromMillisecondsSinceEpoch(seen);
          } else if (seen is double && seen > 0) {
            _lastSeen = DateTime.fromMillisecondsSinceEpoch(seen.toInt());
          }
        } catch (e) {
          debugPrint('[FeederService] Status parse error: $e');
        }
        notifyListeners();
      }, onError: (error) {
        _lastError = error.toString();
        debugPrint('[FeederService] Status stream error: $error');
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[FeederService] Status listen error: $e');
    }
  }

  void _listenSchedules() {
    _schedulesSub?.cancel();
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    try {
      _schedulesSub = tankDoc
          .collection('feeder_schedules')
          .orderBy('timeValue')
          .limit(20)
          .snapshots()
          .listen((snapshot) {
        try {
          _schedules.clear();
          _scheduleKeys.clear();
          for (final doc in snapshot.docs) {
            final data = doc.data();
            _scheduleKeys.add(doc.id);
            _schedules.add(ScheduleItem(
              data['time'] as String? ?? '6:00',
              data['ampm'] as String? ?? 'AM',
              enabled: data['enabled'] as bool? ?? data['is_active'] as bool? ?? true,
              isDone: data['isDone'] as bool? ?? false,
              grams: (data['grams'] as num?)?.toDouble() ?? (data['portion_grams'] as num?)?.toDouble(),
            ));
          }
          FeedState.schedules.value = List.from(_schedules);
        } catch (e) {
          debugPrint('[FeederService] Schedules parse error: $e');
        }
        notifyListeners();
      }, onError: (error) {
        debugPrint('[FeederService] Schedules stream error: $error');
      });
    } catch (e) {
      debugPrint('[FeederService] Schedules listen error: $e');
    }
  }

  void _listenLogs() {
    _logsSub?.cancel();
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    try {
      _logsSub = tankDoc
          .collection('feeder_logs')
          .orderBy('logged_at', descending: true)
          .limit(50)
          .snapshots()
          .listen((snapshot) {
        try {
          _logs.clear();
          for (final doc in snapshot.docs) {
            final data = doc.data();
            // time/date are derived from logged_at (no longer stored) so the
            // display matches the single source of truth for "when".
            final ts = data['logged_at'] as int? ?? 0;
            final dt = ts > 0
                ? DateTime.fromMillisecondsSinceEpoch(ts).toLocal()
                : null;
            _logs.add(LogEntry(
              data['action'] as String? ?? '',
              data['type'] as String? ?? 'auto',
              dt == null ? '' : _formatTime(dt),
              dt == null ? '' : _formatDate(dt),
              timestamp: ts,
            ));
          }
          FeedState.feederLogs.value = List.from(_logs);
        } catch (e) {
          debugPrint('[FeederService] Logs parse error: $e');
        }
        notifyListeners();
      }, onError: (error) {
        debugPrint('[FeederService] Logs stream error: $error');
      });
    } catch (e) {
      debugPrint('[FeederService] Logs listen error: $e');
    }
  }

  Future<void> feedNow({String source = 'manual', String? scheduleKey, double? grams}) async {
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      // New structure: tanks/{tank_id}/feeder_commands/{autoId}
      // ESP32 listens here, executes, then deletes the command.
      final cmd = <String, dynamic>{
        'command_type': 'feed_now',
        'issued_by': uid,
        'issued_at': FieldValue.serverTimestamp(),
      };
      if (grams != null) {
        cmd['grams'] = grams;
      }
      await tankDoc.collection('feeder_commands').add(cmd);
      // NOTE: do NOT write a feeder_logs entry here.
      // The ESP32 writes the confirmed log after the servo physically completes,
      // which is the reliable source of truth. Writing here too causes duplicates.
      if (source == 'scheduled' && scheduleKey != null) {
        final mNow = _manilaNow();
        await tankDoc
            .collection('feeder_dispatched')
            .doc('${mNow.year}-${mNow.month}-${mNow.day}')
            .set({scheduleKey: true}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[FeederService] feedNow error: $e');
    }
    notifyListeners();
  }

  Future<void> logFeedFailure() async {
    await _addLogEntry(
      action: 'Feed failed to dispense',
      type: 'error',
    );
  }

  Future<void> _addLogEntry({required String action, required String type}) async {
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    try {
      // tanks/{tank_id}/feeder_logs/{autoId}
      await tankDoc.collection('feeder_logs').add({
        'action': action,
        'type': type,
        'logged_at': DateTime.now().millisecondsSinceEpoch,
        'trigger_type': type == 'auto' ? 'scheduled' : 'manual',
      });
    } catch (e) {
      debugPrint('[FeederService] addLogEntry error: $e');
    }
  }

  Future<void> addSchedule(String time, String ampm, {double? grams}) async {
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    try {
      final parts = time.split(':');
      final h = int.tryParse(parts[0]) ?? 6;
      final m = int.tryParse(parts[1]) ?? 0;
      final hour24 = ampm == 'PM'
          ? (h == 12 ? 12 : h + 12)
          : (h == 12 ? 0 : h);
      final timeValue = hour24 * 60 + m;
      // tanks/{tank_id}/feeder_schedules/{autoId}
      await tankDoc.collection('feeder_schedules').add({
        'time': time,
        'ampm': ampm,
        'enabled': true,
        'is_active': true,
        'isDone': false,
        'grams': grams,
        'portion_grams': grams,
        'feed_time': time,
        'timeValue': timeValue,
        'created_at': FieldValue.serverTimestamp(),
      });
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';
      await _addLogEntry(
        action: 'Scheduled auto feed at $time $ampm$gramsStr',
        type: 'auto',
      );
    } catch (e) {
      debugPrint('[FeederService] addSchedule error: $e');
    }
    notifyListeners();
  }

  String getScheduleTime(int index) {
    if (index < 0 || index >= _schedules.length) return '';
    final s = _schedules[index];
    return '${s.time} ${s.ampm}';
  }

  Future<void> deleteSchedule(int index) async {
    if (index < 0 || index >= _scheduleKeys.length) return;
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    final timeStr = getScheduleTime(index);
    try {
      await tankDoc.collection('feeder_schedules').doc(_scheduleKeys[index]).delete();
      await _addLogEntry(
        action: 'Removed schedule at $timeStr',
        type: 'auto',
      );
    } catch (e) {
      debugPrint('[FeederService] deleteSchedule error: $e');
    }
    notifyListeners();
  }

  Future<void> editSchedule(int index, {
    required String time,
    required String ampm,
    bool? enabled,
    double? grams,
    bool clearGrams = false,
  }) async {
    if (index < 0 || index >= _scheduleKeys.length) return;
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    try {
      final parts = time.split(':');
      final hour = int.tryParse(parts.first) ?? 6;
      final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final timeValue = (ampm == 'PM' && hour != 12 ? hour + 12 : (ampm == 'AM' && hour == 12 ? 0 : hour)) * 60 + minute;
      await tankDoc.collection('feeder_schedules').doc(_scheduleKeys[index]).update({
        'time': time,
        'ampm': ampm,
        'feed_time': time,
        'timeValue': timeValue,
        'enabled': enabled ?? true,
        'is_active': enabled ?? true,
        'isDone': false,
        'grams': grams,
        'portion_grams': grams,
      });
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';
      await _addLogEntry(
        action: 'Edited schedule to $time $ampm$gramsStr',
        type: 'auto',
      );
    } catch (e) {
      debugPrint('[FeederService] editSchedule error: $e');
    }
    notifyListeners();
  }

  void _startScheduleTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_checkSchedules());
    });
  }

  Future<void> _checkSchedules() async {
    final tankDoc = _tankDoc();
    if (tankDoc == null) return;
    final now = _manilaNow();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (_lastCheckDate != todayKey) {
      _lastCheckDate = todayKey;
      _missedLogged.clear();
      for (final key in _scheduleKeys) {
        await tankDoc.collection('feeder_schedules').doc(key).update({'isDone': false});
      }
    }

    for (int i = 0; i < _schedules.length; i++) {
      final s = _schedules[i];
      if (!s.enabled || s.isDone) continue;
      final key = i < _scheduleKeys.length
          ? _scheduleKeys[i]
          : '${s.time}_${s.ampm}';
      if (_missedLogged.contains(key)) continue;

      int h = int.parse(s.time.split(':')[0]);
      final m = int.parse(s.time.split(':')[1]);
      if (s.ampm == 'PM' && h != 12) h += 12;
      if (s.ampm == 'AM' && h == 12) h = 0;
      final scheduleDt = DateTime(now.year, now.month, now.day, h, m);
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final expectedDate = '${months[now.month - 1]} ${now.day}, ${now.year}';
      final expectedTime = '${s.time} ${s.ampm}';
      final alreadyConfirmed = _logs.any((log) {
        final action = log.action.toLowerCase();
        return log.type == 'auto' &&
            (action.contains('dispensed feed (scheduled)') ||
                action.contains('auto feed dispensed')) &&
            log.time == expectedTime &&
            log.date == expectedDate;
      });
      if (alreadyConfirmed) continue;

      if (now.difference(scheduleDt).inMinutes >= 5) {
        _missedLogged.add(key);
        final reason = isOnline
            ? 'No confirmed feeder log received'
            : 'ESP was offline';
        await _addLogEntry(
          action: 'Feed skipped - $reason',
          type: 'missed',
        );
        debugPrint('[FeederService] Missed schedule: $key ($reason)');
      }
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _schedulesSub?.cancel();
    _logsSub?.cancel();
    _scheduleTimer?.cancel();
    super.dispose();
  }
}
