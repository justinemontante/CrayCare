import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/control_types.dart';
import 'sensor_service.dart';
import 'settings_service.dart';

class FeederService extends ChangeNotifier {
  static final FeederService instance = FeederService._();
  FeederService._();

  // The feeder schedule times (and the Cloud Function that dispatches/confirms
  // them) are always expressed in Asia/Manila wall-clock time, regardless of
  // where the viewing device is physically located (e.g. a "monitor" user
  // checking in from a different timezone). Using DateTime.now() directly
  // would compare schedule times against the DEVICE's local clock instead,
  // causing missed-schedule false positives and feederDispatched date-key
  // mismatches with the Cloud Function (functions/notifications/index.js,
  // which hardcodes MANILA_OFFSET_MS). Mirror that same fixed +8h approach
  // here so both sides agree on "today" and "now".
  static const _manilaOffset = Duration(hours: 8);
  DateTime _manilaNow() => DateTime.now().toUtc().add(_manilaOffset);

  bool _initialized = false;

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
        _listenStatus();
        _listenSchedules();
        _listenLogs();
      }
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          _cancelSubscriptions();
          _listenStatus();
          _listenSchedules();
          _listenLogs();
        } else {
          _cancelSubscriptions();
        }
      });
    } catch (e) {
      debugPrint('[FeederService] Initialization error: $e');
    }
  }

  bool canFeedNow() {
    final ranges = SettingsService.instance.currentRanges;
    final turbMax = ranges['turb']?['max'] ?? 999.0;
    final turb = SensorService.instance.getLatestValue('turb');
    if (SensorService.instance.turbidityAir) return false;
    if (turb > turbMax) return false;
    return true;
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
    try {
      _statusSub = FirebaseFirestore.instance
          .collection('feederStatus')
          .doc('status')
          .snapshots()
          .listen((snapshot) {
        _lastError = null;
        if (!snapshot.exists || snapshot.data() == null) return;
        try {
          final data = snapshot.data()!;
          _isRunning = data['isRunning'] == true;
          _feedSource = (data['feedSource'] as String?) ?? '';
          _feedCount = (data['feedCount'] as num?)?.toInt() ?? _feedCount;
          _hopperLevel = (data['hopperLevel'] as num?)?.toDouble() ?? 100;
          _feederError = (data['feederError'] as String?) ?? '';
          if (_feederError.isNotEmpty && !_isRunning) {
            FirebaseFirestore.instance
                .collection('feederStatus')
                .doc('status')
                .update({'feederError': ''});
            _feederError = '';
          }
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
    try {
      _schedulesSub = FirebaseFirestore.instance
          .collection('feederSchedules')
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
              enabled: data['enabled'] as bool? ?? true,
              isDone: data['isDone'] as bool? ?? false,
              grams: (data['grams'] as num?)?.toDouble(),
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
    try {
      _logsSub = FirebaseFirestore.instance
          .collection('feederLogs')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots()
          .listen((snapshot) {
        try {
          _logs.clear();
          for (final doc in snapshot.docs) {
            final data = doc.data();
            _logs.add(LogEntry(
              data['action'] as String? ?? '',
              data['type'] as String? ?? 'auto',
              data['time'] as String? ?? '',
              data['date'] as String? ?? '',
              timestamp: data['timestamp'] as int? ?? 0,
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

  void feedNow({String source = 'manual', String? scheduleKey, double? grams}) {
    try {
      final cmd = <String, dynamic>{
        'action': 'feed_now',
        'timestamp': FieldValue.serverTimestamp(),
        'source': 'flutter-app',
      };
      if (grams != null) {
        cmd['grams'] = grams;
      }
      FirebaseFirestore.instance.collection('feederCommands').add(cmd);
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';
      if (source == 'scheduled') {
        _addLogEntry(
          action: 'Auto feed dispensed$gramsStr',
          type: 'auto',
        );
        if (scheduleKey != null) {
          final mNow = _manilaNow();
          FirebaseFirestore.instance
              .collection('feederDispatched')
              .doc('${mNow.year}-${mNow.month}-${mNow.day}')
              .set({scheduleKey: true}, SetOptions(merge: true));
        }
      } else {
        _addLogEntry(
          action: 'Feed dispensed$gramsStr',
          type: 'manual',
        );
      }
    } catch (e) {
      debugPrint('[FeederService] feedNow error: $e');
    }
    notifyListeners();
  }

  void logFeedFailure() {
    _addLogEntry(
      action: 'Feed failed to dispense',
      type: 'error',
    );
  }

  void _addLogEntry({required String action, required String type}) {
    final now = DateTime.now();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateStr = '${months[now.month - 1]} ${now.day}, ${now.year}';
    final h = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$h:${now.minute.toString().padLeft(2, '0')} $ampm';
    try {
      FirebaseFirestore.instance.collection('feederLogs').add({
        'action': action,
        'type': type,
        'time': timeStr,
        'date': dateStr,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[FeederService] addLogEntry error: $e');
    }
  }

  void addSchedule(String time, String ampm, {double? grams}) {
    try {
      final parts = time.split(':');
      final h = int.tryParse(parts[0]) ?? 6;
      final m = int.tryParse(parts[1]) ?? 0;
      final timeValue = (ampm == 'PM' && h != 12 ? h + 12 : h) * 60 + m;
      FirebaseFirestore.instance.collection('feederSchedules').add({
        'time': time,
        'ampm': ampm,
        'enabled': true,
        'isDone': false,
        'grams': grams,
        'timeValue': timeValue,
      });
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';
      _addLogEntry(
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

  void deleteSchedule(int index) {
    if (index < 0 || index >= _scheduleKeys.length) return;
    final timeStr = getScheduleTime(index);
    try {
      FirebaseFirestore.instance.collection('feederSchedules').doc(_scheduleKeys[index]).delete();
      _addLogEntry(
        action: 'Removed schedule at $timeStr',
        type: 'auto',
      );
    } catch (e) {
      debugPrint('[FeederService] deleteSchedule error: $e');
    }
    notifyListeners();
  }

  void editSchedule(int index, {
    required String time,
    required String ampm,
    bool? enabled,
    double? grams,
    bool clearGrams = false,
  }) {
    if (index < 0 || index >= _scheduleKeys.length) return;
    try {
      FirebaseFirestore.instance.collection('feederSchedules').doc(_scheduleKeys[index]).update({
        'time': time,
        'ampm': ampm,
        'enabled': enabled ?? true,
        'isDone': false,
        'grams': grams,
      });
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';
      _addLogEntry(
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
      _checkSchedules();
    });
  }

  void _checkSchedules() {
    final now = _manilaNow();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (_lastCheckDate != todayKey) {
      _lastCheckDate = todayKey;
      _missedLogged.clear();
      for (final key in _scheduleKeys) {
        FirebaseFirestore.instance.collection('feederSchedules').doc(key).update({'isDone': false});
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
      if (now.difference(scheduleDt).inMinutes >= 5) {
        _missedLogged.add(key);
        final reason = isOnline
            ? 'Feeder did not respond'
            : 'ESP was offline';
        _addLogEntry(
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
