import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/control_types.dart';

class AutoControlEvent {
  final String deviceId;
  final String deviceLabel;
  final String action;
  final DateTime timestamp;
  const AutoControlEvent({
    required this.deviceId,
    required this.deviceLabel,
    required this.action,
    required this.timestamp,
  });
}

class DeviceLogService extends ChangeNotifier {
  static final DeviceLogService instance = DeviceLogService._();
  DeviceLogService._();

  static const deviceIds = ['aerator1', 'aerator2', 'pump'];
  static const deviceLabels = {
    'aerator1': 'Aerator 1',
    'aerator2': 'Aerator 2',
    'pump': 'Water Pump',
  };

  final Map<String, List<LogEntry>> _logs = {};
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs = [];
  bool _initialized = false;
  bool _warmup = true;
  final Set<String> _seenKeys = {};

  final StreamController<AutoControlEvent> _autoControlController =
      StreamController<AutoControlEvent>.broadcast();
  Stream<AutoControlEvent> get autoControlEvents => _autoControlController.stream;

  void init() {
    if (_initialized) return;
    _initialized = true;

    if (FirebaseAuth.instance.currentUser == null) return;

    for (final deviceId in deviceIds) {
      _logs[deviceId] = [];
      final sub = FirebaseFirestore.instance
          .collection('deviceLogs')
          .where('deviceId', isEqualTo: deviceId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots()
          .listen((snapshot) {
        final list = snapshot.docs.map((doc) {
          final map = doc.data();
          return LogEntry(
            map['action'] as String? ?? '',
            map['type'] as String? ?? '',
            map['time'] as String? ?? '',
            map['date'] as String? ?? '',
            timestamp: map['timestamp'] as int? ?? 0,
          );
        }).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        _logs[deviceId] = list;
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
            final label = deviceLabels[deviceId] ?? deviceId;

            _autoControlController.add(AutoControlEvent(
              deviceId: deviceId,
              deviceLabel: label,
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

  List<LogEntry> getLogs(String deviceId) => _logs[deviceId] ?? [];

  Map<String, List<LogEntry>> get allLogs =>
      Map.unmodifiable(_logs);

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _autoControlController.close();
    super.dispose();
  }
}
