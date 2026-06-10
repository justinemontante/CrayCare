import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/control_types.dart';

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

  // ─── Firebase Refs (lazy) ───
  DatabaseReference? _commandsRef;
  DatabaseReference? _statusRef;
  DatabaseReference? _schedulesRef;
  DatabaseReference? _logsRef;

  // ─── Subscriptions ───
  StreamSubscription<DatabaseEvent>? _statusSub;
  StreamSubscription<DatabaseEvent>? _schedulesSub;
  StreamSubscription<DatabaseEvent>? _logsSub;

  // ─── State ───
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
  final Set<String> _dispatchedToday = {};
  String _lastCheckDate = '';

  // ─── Getters ───
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

  // ─── Init (call once from app startup) ───
  void init() {
    if (_initialized) return;
    _initialized = true;
    try {
      _commandsRef = FirebaseDatabase.instance.ref('feeder/commands');
      _statusRef = FirebaseDatabase.instance.ref('feeder/status');
      _schedulesRef = FirebaseDatabase.instance.ref('feeder/schedules');
      _logsRef = FirebaseDatabase.instance.ref('feeder/logs');
      _listenStatus();
      _listenSchedules();
      _listenLogs();
      _startScheduleTimer();
    } catch (e) {
      debugPrint('[FeederService] Initialization error: $e');
    }
  }

  // ─── Status Listener ───
  void _listenStatus() {
    if (_statusRef == null) return;
    _statusSub?.cancel();
    try {
      _statusSub = _statusRef!.onValue.listen(
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
              _statusRef!.update({'feederError': ''});
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

  // ─── Schedules Listener ───
  void _listenSchedules() {
    if (_schedulesRef == null) return;
    _schedulesSub?.cancel();
    try {
      _schedulesSub = _schedulesRef!.onValue.listen(
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
                  createdBy: val['createdBy'] as String?,
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

  // ─── Logs Listener ───
  void _listenLogs() {
    if (_logsRef == null) return;
    _logsSub?.cancel();
    try {
      _logsSub = _logsRef!.orderByChild('timestamp').limitToLast(50).onValue.listen(
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
                  userName: val['userName'] as String? ?? '',
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

  // ─── Actions ───

  void feedNow({String source = 'manual', String? scheduleKey}) {
    if (_commandsRef == null) return;
    try {
      _commandsRef!.push().set({
        'action': 'feed_now',
        'timestamp': ServerValue.timestamp,
        'source': 'flutter-app',
      });
      if (source == 'scheduled') {
        _addLogEntry(
          action: 'Auto feed dispensed',
          type: 'auto',
        );
        final dateKey = '${DateTime.now().month}/${DateTime.now().day}';
        if (scheduleKey != null) {
          try {
            _commandsRef!.parent!.child('dispatched/$dateKey/$scheduleKey').set(true);
          } catch (_) {}
        }
      } else {
        final name = _getUserName();
        _addLogEntry(
          action: '$name manually fed',
          type: 'manual',
          userName: name,
        );
      }
    } catch (e) {
      debugPrint('[FeederService] feedNow error: $e');
    }
    notifyListeners();
  }

  void logFeedFailure() {
    final name = _getUserName();
    _addLogEntry(
      action: '$name \u2014 Feed failed to dispense',
      type: 'error',
      userName: name,
    );
  }

  void _addLogEntry({required String action, required String type, String? userName}) {
    if (_logsRef == null) return;
    userName ??= _getUserName();
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
      _logsRef!.push().set({
        'action': action,
        'type': type,
        'time': timeStr,
        'date': dateStr,
        'userName': userName,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[FeederService] addLogEntry error: $e');
    }
  }

  void addSchedule(String time, String ampm) {
    if (_schedulesRef == null) return;
    final name = _getUserName();
    try {
      _schedulesRef!.push().set({
        'time': time,
        'ampm': ampm,
        'enabled': true,
        'createdBy': name,
      });
      _addLogEntry(
        action: '$name scheduled auto feed at $time $ampm',
        type: 'auto',
        userName: name,
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
    if (_schedulesRef == null) return;
    if (index < 0 || index >= _scheduleKeys.length) return;
    final name = _getUserName();
    final timeStr = getScheduleTime(index);
    try {
      _schedulesRef!.child(_scheduleKeys[index]).remove();
      _addLogEntry(
        action: '$name removed schedule at $timeStr',
        type: 'auto',
        userName: name,
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
  }) {
    if (_schedulesRef == null) return;
    if (index < 0 || index >= _scheduleKeys.length) return;
    final name = _getUserName();
    try {
      _schedulesRef!.child(_scheduleKeys[index]).update({
        'time': time,
        'ampm': ampm,
        if (enabled != null) 'enabled': enabled,
      });
      _addLogEntry(
        action: '$name edited schedule to $time $ampm',
        type: 'auto',
        userName: name,
      );
    } catch (e) {
      debugPrint('[FeederService] editSchedule error: $e');
    }
    notifyListeners();
  }

  // ─── Schedule Timer ───

  void _startScheduleTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkSchedules();
    });
  }

  void _checkSchedules() {
    final now = DateTime.now();
    final todayKey = '${now.month}/${now.day}';
    if (_lastCheckDate != todayKey) {
      _dispatchedToday.clear();
      _lastCheckDate = todayKey;
    }
    for (int i = 0; i < _schedules.length; i++) {
      final s = _schedules[i];
      if (!s.enabled) continue;
      int h = int.parse(s.time.split(':')[0]);
      final m = int.parse(s.time.split(':')[1]);
      if (s.ampm == 'PM' && h != 12) h += 12;
      if (s.ampm == 'AM' && h == 12) h = 0;
      if (now.hour == h && now.minute == m) {
        final key = i < _scheduleKeys.length
            ? _scheduleKeys[i]
            : '${s.time}_${s.ampm}';
        if (!_dispatchedToday.contains(key)) {
          _dispatchedToday.add(key);
          feedNow(source: 'scheduled', scheduleKey: key);
          debugPrint('[FeederService] Auto-dispatch: $key');
        }
      }
    }
  }

  // ─── Helpers ───

  String _getUserName() {
    return FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown';
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

  // ─── Dispose ───
  @override
  void dispose() {
    _statusSub?.cancel();
    _schedulesSub?.cancel();
    _logsSub?.cancel();
    _scheduleTimer?.cancel();
    super.dispose();
  }
}
