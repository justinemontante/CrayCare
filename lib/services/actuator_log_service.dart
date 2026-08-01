import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/control_types.dart';

class AutoActuatorEvent {
  final String actuatorId;
  final String actuatorLabel;
  final String action;
  final DateTime timestamp;
  const AutoActuatorEvent({
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

  final StreamController<AutoActuatorEvent> _autoControlController =
      StreamController<AutoActuatorEvent>.broadcast();
  Stream<AutoActuatorEvent> get autoControlEvents => _autoControlController.stream;

  void init() {
    if (_initialized) return;

    if (FirebaseAuth.instance.currentUser == null) {
      // Auth hasn't resolved the persisted session yet. Don't burn the
      // _initialized flag - instead wait for the first auth state change
      // and start the real listeners once a user is actually available.
      _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null && !_initialized) {
          _startListening();
        }
      });
      return;
    }

    _startListening();
  }

  void _startListening() async {
    if (_initialized) return;
    _initialized = true;
    _authSub?.cancel();
    _authSub = null;

    // Legacy deviceLogs migrated to tanks/{tank_id}/actuator_logs, filtered by the
    // 'actuator_type' field instead of 'actuatorId'.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final profileDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final tankId = profileDoc.data()?['tank_id'] as String? ?? uid;
    final tankLogsRef =
        FirebaseFirestore.instance.collection('tanks').doc(tankId).collection('actuator_logs');

    for (final actuatorId in actuatorIds) {
      _logs[actuatorId] = [];
      final sub = tankLogsRef
          .where('actuator_type', isEqualTo: actuatorId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots()
          .listen((snapshot) {
        final list = snapshot.docs.map((doc) {
          final map = doc.data();
          return LogEntry(
            map['action'] as String? ?? map['message'] as String? ?? '',
            map['type'] as String? ?? map['log_level'] as String? ?? '',
            map['time'] as String? ?? '',
            map['date'] as String? ?? '',
            timestamp: map['timestamp'] as int? ?? 0,
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

            final tsRaw = data['timestamp'] as num? ?? 0;
            final tsMs = tsRaw < 100000000000 ? tsRaw * 1000 : tsRaw;
            final ts = DateTime.fromMillisecondsSinceEpoch(tsMs.toInt());
            final label = actuatorLabels[actuatorId] ?? actuatorId;

            _autoControlController.add(AutoActuatorEvent(
              actuatorId: actuatorId,
              actuatorLabel: label,
              action: action,
              timestamp: ts,
            ));
          }
        }
      });
      _subs.add(sub);
    }

    Future.delayed(const Duration(seconds: 3), () {
      _warmup = false;
    });
  }

  List<LogEntry> getLogs(String actuatorId) => _logs[actuatorId] ?? [];

  Map<String, List<LogEntry>> get allLogs =>
      Map.unmodifiable(_logs);

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
