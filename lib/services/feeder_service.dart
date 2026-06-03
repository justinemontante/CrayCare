import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/control_types.dart';

class FeederService extends ChangeNotifier {
  static final FeederService instance = FeederService._();
  FeederService._();

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
  bool _autoMode = true;
  bool _isRunning = false;
  String _feedSource = '';
  int _feedCount = 0;
  double _hopperLevel = 100;
  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastError;

  final List<LogEntry> _logs = [];
  final List<ScheduleItem> _schedules = [];
  final List<String> _scheduleKeys = [];

  // ─── Getters ───
  bool get autoMode => _autoMode;
  bool get isRunning => _isRunning;
  String get feedSource => _feedSource;
  int get feedCount => _feedCount;
  double get hopperLevel => _hopperLevel;
  DateTime get lastSeen => _lastSeen;
  String? get lastError => _lastError;

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
                Map<String, dynamic>.from(event.snapshot.value as Map);
            _autoMode = data['mode'] == 'auto';
            _isRunning = data['isRunning'] == true;
            _feedSource = (data['feedSource'] as String?) ?? '';
            _feedCount = (data['feedCount'] as num?)?.toInt() ?? _feedCount;
            _hopperLevel = (data['hopperLevel'] as num?)?.toDouble() ?? 100;
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
                  (Map<String, dynamic>.from(data)).entries.toList();
              entries.sort((a, b) {
                final aVal = Map<String, dynamic>.from(a.value);
                final bVal = Map<String, dynamic>.from(b.value);
                return _toMinutes(aVal).compareTo(_toMinutes(bVal));
              });
              for (final entry in entries) {
                final val = Map<String, dynamic>.from(entry.value);
                _scheduleKeys.add(entry.key);
                _schedules.add(ScheduleItem(
                  val['time'] as String? ?? '6:00',
                  val['ampm'] as String? ?? 'AM',
                  enabled: val['enabled'] as bool? ?? true,
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
                  (Map<String, dynamic>.from(data)).entries.toList();
              entries.sort((a, b) {
                final aVal = Map<String, dynamic>.from(a.value);
                final bVal = Map<String, dynamic>.from(b.value);
                final aTs = aVal['timestamp'] as int? ?? 0;
                final bTs = bVal['timestamp'] as int? ?? 0;
                return bTs.compareTo(aTs);
              });
              for (final entry in entries) {
                final val = Map<String, dynamic>.from(entry.value);
                _logs.add(LogEntry(
                  val['action'] as String? ?? '',
                  val['type'] as String? ?? 'auto',
                  val['time'] as String? ?? '',
                  val['date'] as String? ?? '',
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

  void feedNow() {
    if (_commandsRef == null) return;
    try {
      _commandsRef!.push().set({
        'action': 'feed_now',
        'timestamp': ServerValue.timestamp,
        'source': 'flutter-app',
      });
    } catch (e) {
      debugPrint('[FeederService] feedNow error: $e');
    }
    notifyListeners();
  }

  Future<void> toggleMode() async {
    if (_commandsRef == null) return;
    final newMode = _autoMode ? 'manual' : 'auto';
    _autoMode = !_autoMode;
    notifyListeners();
    try {
      await _commandsRef!.push().set({
        'action': 'set_mode',
        'mode': newMode,
        'timestamp': ServerValue.timestamp,
        'source': 'flutter-app',
      });
    } catch (e) {
      _autoMode = !_autoMode;
      notifyListeners();
      debugPrint('[FeederService] toggleMode error: $e');
    }
  }

  void addSchedule(String time, String ampm) {
    if (_schedulesRef == null) return;
    try {
      _schedulesRef!.push().set({
        'time': time,
        'ampm': ampm,
        'enabled': true,
      });
    } catch (e) {
      debugPrint('[FeederService] addSchedule error: $e');
    }
    notifyListeners();
  }

  void deleteSchedule(int index) {
    if (_schedulesRef == null) return;
    if (index < 0 || index >= _scheduleKeys.length) return;
    try {
      _schedulesRef!.child(_scheduleKeys[index]).remove();
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
    try {
      _schedulesRef!.child(_scheduleKeys[index]).update({
        'time': time,
        'ampm': ampm,
        if (enabled != null) 'enabled': enabled,
      });
    } catch (e) {
      debugPrint('[FeederService] editSchedule error: $e');
    }
    notifyListeners();
  }

  // ─── Helpers ───

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
    super.dispose();
  }
}
