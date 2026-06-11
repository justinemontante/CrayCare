import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'settings_service.dart';

class SensorService extends ChangeNotifier {
  static final SensorService instance = SensorService._();
  SensorService._() {
    _initFirebaseListener();
    FirebaseAuth.instance.authStateChanges().listen((_) {
      _initFirebaseListener();
    });
  }

  static const List<String> sensorKeys = [
    'temp',
    'ph',
    'do',
    'turb',
    'waterlevel',
  ];

  StreamSubscription<DatabaseEvent>? _subscription;
  DatabaseReference get _latestRef =>
      FirebaseDatabase.instance.ref('sensor_readings/latest');

  final Map<String, List<double>> _history = {};
  final Map<String, double> _latest = {};

  bool _initialDataLoaded = false;

  Timer? _staleTimer;
  static const _staleTimeout = Duration(seconds: 30);

  DateTime _lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastError;

  DateTime get lastUpdated => _lastUpdated;
  String? get lastError => _lastError;

  String get overallStatus {
    for (final key in sensorKeys) {
      if (getZone(key) == 'CRITICAL') return 'CRITICAL';
    }
    return 'NORMAL';
  }

  String getZone(String key) {
    if (!_latest.containsKey(key)) return 'UNKNOWN';
    final value = _latest[key]!;
    final ranges = SettingsService.instance.currentRanges;
    final range = ranges[key];
    if (range == null) return 'UNKNOWN';
    final min = range['min'] ?? 0.0;
    final max = range['max'] ?? 999.0;
    if (value >= min && value <= max) return 'OPTIMAL';
    return 'CRITICAL';
  }

  void _initFirebaseListener() {
    _subscription?.cancel();
    _initialDataLoaded = false;
    _staleTimer?.cancel();
    _subscription = _latestRef.onValue.listen(
      (event) {
        _lastError = null;
        if (event.snapshot.value == null) return;
        final raw = event.snapshot.value as Map<Object?, Object?>;
        _parseAndUpdate(raw.map<String, dynamic>((k, v) => MapEntry(k.toString(), v)));
      },
      onError: (error) {
        _lastError = error.toString();
        debugPrint('[SensorService] Firebase stream error: $error');
        notifyListeners();
      },
    );
  }

  void _parseAndUpdate(Map<String, dynamic> data) {
    if (!_initialDataLoaded) {
      _initialDataLoaded = true;
      _staleTimer = Timer(_staleTimeout, _markStale);
    }

    final tempRaw = _toDouble(data['temperature']);
    final turbRaw = _toDouble(data['turbidity']);
    final doRaw = _toDouble(data['dissolvedOxygen']);
    final phRaw = _toDouble(data['phLevel']);
    final wlRaw = _toDouble(data['waterLevel']);

    _updateSensor('temp', tempRaw);
    _updateSensor('turb', turbRaw);
    _updateSensor('do', doRaw);
    _updateSensor('ph', phRaw);
    _updateSensor('waterlevel', wlRaw);

    _lastUpdated = DateTime.now();
    _staleTimer?.cancel();
    _staleTimer = Timer(_staleTimeout, _markStale);
    notifyListeners();
  }

  void _markStale() {
    _latest.clear();
    _lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
    debugPrint('[SensorService] Data stale - ESP32 offline');
  }

  void _updateSensor(String key, double? value) {
    if (value == null || value < 0) {
      _latest.remove(key);
      return;
    }
    if (value == 0 && !_latest.containsKey(key)) return;

    _latest[key] = value;

    if (_history[key] == null) _history[key] = [];

    _history[key]!.add(value);
    if (_history[key]!.length > 60) {
      _history[key]!.removeAt(0);
    }
  }

  double _toDouble(dynamic v) {
    if (v is int) return v.toDouble();
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return -1;
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return null;
  }

  bool hasSensorData(String key) => _latest.containsKey(key);
  double getLatestValue(String key) => _latest[key] ?? 0.0;

  List<double> getData(String key) => _history[key] ?? [];

  Future<List<Map<String, dynamic>>> fetchHistoryRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final days = <String>[];
    for (var d = DateTime(start.year, start.month, start.day);
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      days.add(
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
    }

    const historyBase = 'sensor_readings/history';
    final snapshots = await Future.wait(
      days.map((dateStr) =>
          FirebaseDatabase.instance.ref('$historyBase/$dateStr').get()),
    );

    final records = <Map<String, dynamic>>[];
    for (int di = 0; di < days.length; di++) {
      final dateStr = days[di];
      final snapshot = snapshots[di];
      if (snapshot.value == null) continue;
      final map = snapshot.value as Map<Object?, Object?>;
      final nodeDate = DateTime(
        int.parse(dateStr.split('-')[0]),
        int.parse(dateStr.split('-')[1]),
        int.parse(dateStr.split('-')[2]),
      );
      for (final entry in map.entries) {
        final record = entry.value as Map<Object?, Object?>;
        final r = record.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
        final rawTs = _toInt(r['timestamp']);
        if (rawTs != null) {
          final dt = DateTime.fromMillisecondsSinceEpoch(
            rawTs < 100000000000 ? rawTs * 1000 : rawTs,
          );
          if ((dt.difference(nodeDate).abs().inDays) > 30) {
            r['timestamp'] = nodeDate
                .add(const Duration(hours: 12))
                .millisecondsSinceEpoch ~/ 1000;
          }
        }
        records.add(r);
      }
    }
    records.sort(
      (a, b) => (_toInt(a['timestamp']) ?? 0).compareTo(_toInt(b['timestamp']) ?? 0),
    );
    return records;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _staleTimer?.cancel();
    super.dispose();
  }
}
