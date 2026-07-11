import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/control_types.dart';
import 'sensor_service.dart';
import 'settings_service.dart';

class FeederService extends ChangeNotifier {
  static final FeederService instance = FeederService._();
  FeederService._();

  static Map<String, dynamic> _convertMap(Object? value) {
    if (value is Map) {
      return value.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  bool _initialized = false;

  String get _userBase => 'feeder';

  DatabaseReference get _commandsRef =>
      FirebaseDatabase.instance.ref('$_userBase/commands');
  DatabaseReference get _statusRef =>
      FirebaseDatabase.instance.ref('$_userBase/status');
  DatabaseReference get _schedulesRef =>
      FirebaseDatabase.instance.ref('$_userBase/schedules');
  DatabaseReference get _logsRef =>
      FirebaseDatabase.instance.ref('$_userBase/logs');

  StreamSubscription<DatabaseEvent>? _statusSub;
  StreamSubscription<DatabaseEvent>? _schedulesSub;
  StreamSubscription<DatabaseEvent>? _logsSub;

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
      _listenStatus();
      _listenSchedules();
      _listenLogs();
      _startScheduleTimer();
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          _cancelSubscriptions();
          _listenStatus();
          _listenSchedules();
          _listenLogs();
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
      _statusSub = _statusRef.onValue.listen(
        (event) {
          _lastError = null;
          if (event.snapshot.value == null) return;
          try {
            final data =
                _convertMap(event.snapshot.value as Map);
            _isRunning = data['isRunning'] == true;
            _feedSource = (data['feedSource'] as String?) ?? '';
            _feedCount = (data['feedCount'] as num?)?.toInt() ?? _feedCount;
            _hopperLevel = (data['hopperLevel'] as num?)?.toDouble() ?? 100;
            _feederError = (data['feederError'] as String?) ?? '';
            if (_feederError.isNotEmpty && !_isRunning) {
              _statusRef.update({'feederError': ''});
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
        },
        onError: (error) {
          _lastError = error.toString();
          debugPrint('[FeederService] Status stream error: $error');
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('[FeederService] Status listen error: $e');
    }
  }

  void _listenSchedules() {
    _schedulesSub?.cancel();
    try {
      _schedulesSub = _schedulesRef.onValue.listen(
        (event) {
          try {
            final data = event.snapshot.value;
            _schedules.clear();
            _scheduleKeys.clear();
            if (data != null && data is Map) {
              final entries =
                  (_convertMap(data)).entries.toList();
              entries.sort((a, b) {
                final aVal = _convertMap(a.value);
                final bVal = _convertMap(b.value);
                return _toMinutes(aVal).compareTo(_toMinutes(bVal));
              });
              for (final entry in entries) {
                final val = _convertMap(entry.value);
                _scheduleKeys.add(entry.key);
                _schedules.add(ScheduleItem(
                  val['time'] as String? ?? '6:00',
                  val['ampm'] as String? ?? 'AM',
                  enabled: val['enabled'] as bool? ?? true,
                  isDone: val['isDone'] as bool? ?? false,
                  grams: (val['grams'] as num?)?.toDouble(),
                ));
              }
            }
            FeedState.schedules.value = List.from(_schedules);
          } catch (e) {
            debugPrint('[FeederService] Schedules parse error: $e');
          }
          notifyListeners();
        },
        onError: (error) {
          debugPrint('[FeederService] Schedules stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('[FeederService] Schedules listen error: $e');
    }
  }

  void _listenLogs() {
    _logsSub?.cancel();
    try {
      _logsSub = _logsRef.orderByChild('timestamp').limitToLast(50).onValue.listen(
        (event) {
          try {
            final data = event.snapshot.value;
            _logs.clear();
            if (data != null && data is Map) {
              final entries =
                  (_convertMap(data)).entries.toList();
              entries.sort((a, b) {
                final aVal = _convertMap(a.value);
                final bVal = _convertMap(b.value);
                final aTs = aVal['timestamp'] as int? ?? 0;
                final bTs = bVal['timestamp'] as int? ?? 0;
                return bTs.compareTo(aTs);
              });
              for (final entry in entries) {
                final val = _convertMap(entry.value);
                _logs.add(LogEntry(
                  val['action'] as String? ?? '',
                  val['type'] as String? ?? 'auto',
                  val['time'] as String? ?? '',
                  val['date'] as String? ?? '',

                  timestamp: val['timestamp'] as int? ?? 0,
                ));
              }
            }
            FeedState.feederLogs.value = List.from(_logs);
          } catch (e) {
            debugPrint('[FeederService] Logs parse error: $e');
          }
          notifyListeners();
        },
        onError: (error) {
          debugPrint('[FeederService] Logs stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('[FeederService] Logs listen error: $e');
    }
  }

  void feedNow({String source = 'manual', String? scheduleKey, double? grams}) {
    try {
      final Map<String, dynamic> cmd = {
        'action': 'feed_now',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'source': 'flutter-app',
      };
      if (grams != null) {
        cmd['grams'] = grams;
      }
      _commandsRef.push().set(cmd);
      final gramsStr = grams != null ? ' (${grams.toStringAsFixed(1)}g)' : '';
      if (source == 'scheduled') {
        _addLogEntry(
          action: 'Auto feed dispensed$gramsStr',
          type: 'auto',
        );
        final dateKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
        if (scheduleKey != null) {
          try {
            final parent = _commandsRef.parent;
            if (parent != null) {
              parent.child('dispatched/$dateKey/$scheduleKey').set(true);
            }
          } catch (_) {}
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
      _logsRef.push().set({
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
      _schedulesRef.push().set({
        'time': time,
        'ampm': ampm,
        'enabled': true,
        'isDone': false,
        'grams': grams,
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
      _schedulesRef.child(_scheduleKeys[index]).remove();
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
      _schedulesRef.child(_scheduleKeys[index]).update({
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
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month}-${now.day}';
    if (_lastCheckDate != todayKey) {
      _lastCheckDate = todayKey;
      _missedLogged.clear();
      final updates = <String, dynamic>{};
      for (final key in _scheduleKeys) {
        updates['$key/isDone'] = false;
      }
      if (updates.isNotEmpty) {
        _schedulesRef.update(updates);
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

  int _toMinutes(Map<String, dynamic> s) {
    final time = s['time'] as String? ?? '6:00';
    final ampm = s['ampm'] as String? ?? 'AM';
    int h = int.tryParse(time.split(':')[0]) ?? 6;
    final m = int.tryParse(time.split(':')[1]) ?? 0;
    if (ampm == 'PM' && h != 12) h += 12;
    if (ampm == 'AM' && h == 12) h = 0;
    return h * 60 + m;
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
