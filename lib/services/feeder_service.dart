import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/control_types.dart';

class FeederService extends ChangeNotifier {
  static final FeederService instance = FeederService._();
  FeederService._() {
    _init();
  }

  // ─── Firebase Refs ───
  final DatabaseReference _commandsRef =
      FirebaseDatabase.instance.ref('feeder/commands');
  final DatabaseReference _statusRef =
      FirebaseDatabase.instance.ref('feeder/status');
  final DatabaseReference _schedulesRef =
      FirebaseDatabase.instance.ref('feeder/schedules');
  final DatabaseReference _logsRef =
      FirebaseDatabase.instance.ref('feeder/logs');

  // ─── Subscriptions ───
  StreamSubscription<DatabaseEvent>? _statusSub;
  StreamSubscription<DatabaseEvent>? _schedulesSub;
  StreamSubscription<DatabaseEvent>? _logsSub;

  // ─── State ───
  bool _autoMode = true;
  bool _isRunning = false;
  double _hopperLevel = 100;
  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastError;

  final List<LogEntry> _logs = [];
  final List<ScheduleItem> _schedules = [];
  final List<String> _scheduleKeys = [];

  // ─── Getters ───
  bool get autoMode => _autoMode;
  bool get isRunning => _isRunning;
  double get hopperLevel => _hopperLevel;
  DateTime get lastSeen => _lastSeen;
  String? get lastError => _lastError;

  bool get isOnline =>
      DateTime.now().difference(_lastSeen).inSeconds < 30;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  List<ScheduleItem> get schedules => List.unmodifiable(_schedules);

  // ─── Init ───
  void _init() {
    _listenStatus();
    _listenSchedules();
    _listenLogs();
  }

  // ─── Status Listener ───
  void _listenStatus() {
    _statusSub?.cancel();
    _statusSub = _statusRef.onValue.listen(
      (event) {
        _lastError = null;
        if (event.snapshot.value == null) return;
        final data =
            Map<String, dynamic>.from(event.snapshot.value as Map);

        _autoMode = data['mode'] == 'auto';
        _isRunning = data['isRunning'] == true;
        _hopperLevel = (data['hopperLevel'] as num?)?.toDouble() ?? 100;

        final seen = data['lastSeen'];
        if (seen is int && seen > 0) {
          _lastSeen =
              DateTime.fromMillisecondsSinceEpoch(seen);
        } else if (seen is double && seen > 0) {
          _lastSeen =
              DateTime.fromMillisecondsSinceEpoch(seen.toInt());
        }

        notifyListeners();
      },
      onError: (error) {
        _lastError = error.toString();
        debugPrint('[FeederService] Status stream error: $error');
        notifyListeners();
      },
    );
  }

  // ─── Schedules Listener ───
  void _listenSchedules() {
    _schedulesSub?.cancel();
    _schedulesSub = _schedulesRef.onValue.listen(
      (event) {
        final data = event.snapshot.value;
        _schedules.clear();
        _scheduleKeys.clear();
        if (data != null && data is Map) {
          final entries =
              (data as Map<String, dynamic>).entries.toList();
          entries.sort((a, b) {
            final aVal = a.value as Map<String, dynamic>;
            final bVal = b.value as Map<String, dynamic>;
            return _toMinutes(aVal).compareTo(_toMinutes(bVal));
          });
          for (final entry in entries) {
            final val = entry.value as Map<String, dynamic>;
            _scheduleKeys.add(entry.key);
            _schedules.add(ScheduleItem(
              val['time'] as String? ?? '6:00',
              val['ampm'] as String? ?? 'AM',
              enabled: val['enabled'] as bool? ?? true,
            ));
          }
        }
        FeedState.schedules.value = List.from(_schedules);
        notifyListeners();
      },
      onError: (error) {
        debugPrint('[FeederService] Schedules stream error: $error');
      },
    );
  }

  // ─── Logs Listener ───
  void _listenLogs() {
    _logsSub?.cancel();
    _logsSub = _logsRef.orderByChild('timestamp').limitToLast(50).onValue.listen(
      (event) {
        final data = event.snapshot.value;
        _logs.clear();
        if (data != null && data is Map) {
          final entries =
              (data as Map<String, dynamic>).entries.toList();
          entries.sort((a, b) {
            final aVal = a.value as Map<String, dynamic>;
            final bVal = b.value as Map<String, dynamic>;
            final aTs = aVal['timestamp'] as int? ?? 0;
            final bTs = bVal['timestamp'] as int? ?? 0;
            return bTs.compareTo(aTs);
          });
          for (final entry in entries) {
            final val = entry.value as Map<String, dynamic>;
            _logs.add(LogEntry(
              val['action'] as String? ?? '',
              val['type'] as String? ?? 'auto',
              val['time'] as String? ?? '',
              val['date'] as String? ?? '',
            ));
          }
        }
        FeedState.feederLogs.value = List.from(_logs);
        notifyListeners();
      },
      onError: (error) {
        debugPrint('[FeederService] Logs stream error: $error');
      },
    );
  }

  // ─── Actions ───

  Future<void> feedNow() async {
    try {
      await _commandsRef.push().set({
        'action': 'feed_now',
        'timestamp': ServerValue.timestamp,
        'source': 'flutter-app',
      });
    } catch (e) {
      debugPrint('[FeederService] feedNow error: $e');
    }
  }

  Future<void> toggleMode() async {
    final newMode = _autoMode ? 'manual' : 'auto';
    try {
      await _commandsRef.push().set({
        'action': 'set_mode',
        'mode': newMode,
        'timestamp': ServerValue.timestamp,
        'source': 'flutter-app',
      });
    } catch (e) {
      debugPrint('[FeederService] toggleMode error: $e');
    }
  }

  Future<void> addSchedule(
    String time,
    String ampm,
  ) async {
    try {
      await _schedulesRef.push().set({
        'time': time,
        'ampm': ampm,
        'enabled': true,
      });
    } catch (e) {
      debugPrint('[FeederService] addSchedule error: $e');
    }
  }

  Future<void> deleteSchedule(int index) async {
    if (index < 0 || index >= _scheduleKeys.length) return;
    try {
      await _schedulesRef.child(_scheduleKeys[index]).remove();
    } catch (e) {
      debugPrint('[FeederService] deleteSchedule error: $e');
    }
  }

  Future<void> editSchedule(
    int index, {
    required String time,
    required String ampm,
    bool? enabled,
  }) async {
    if (index < 0 || index >= _scheduleKeys.length) return;
    try {
      await _schedulesRef.child(_scheduleKeys[index]).update({
        'time': time,
        'ampm': ampm,
        if (enabled != null) 'enabled': enabled,
      });
    } catch (e) {
      debugPrint('[FeederService] editSchedule error: $e');
    }
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
