import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'settings_service.dart';

class SensorService extends ChangeNotifier {
  static final SensorService instance = SensorService._();
  SensorService._() {
    _initFirebaseListener();
  }

  static const List<String> sensorKeys = [
    'temp', 'ph', 'do', 'turb', 'waterlevel'
  ];

  StreamSubscription<DatabaseEvent>? _subscription;
  final DatabaseReference _latestRef = FirebaseDatabase.instance.ref('sensor_readings/latest');

  final Map<String, List<double>> _history = {};
  final Map<String, double> _latest = {};

  bool _deviceOnline = false;
  DateTime _lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime get lastUpdated => _lastUpdated;
  bool get deviceOnline => _deviceOnline;

  bool get isEspOnline {
    if (!_deviceOnline) return false;
    final diff = DateTime.now().difference(_lastUpdated);
    return diff.inSeconds < 30;
  }

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

  String get connectionLabel {
    if (isEspOnline) return 'ESP32 Connected';
    if (_lastUpdated == DateTime.fromMillisecondsSinceEpoch(0)) return 'Waiting for data...';
    final diff = DateTime.now().difference(_lastUpdated);
    if (diff.inSeconds < 60) return 'Last seen ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
    return 'ESP32 Offline';
  }

  void _initFirebaseListener() {
    _subscription?.cancel();
    _subscription = _latestRef.onValue.listen((event) {
      if (event.snapshot.value == null) return;
      _parseAndUpdate(Map<String, dynamic>.from(event.snapshot.value as Map));
    }, onError: (error) {
      debugPrint('[SensorService] Firebase stream error: $error');
    });
  }

  void _parseAndUpdate(Map<String, dynamic> data) {
    _deviceOnline = data['deviceOnline'] == true;

    final tempRaw = _toDouble(data['temperature']);
    final turbRaw = _toDouble(data['turbidityQuality']);
    final doRaw = _toDouble(data['dissolvedOxygen']);
    final phRaw = _toDouble(data['phLevel']);
    final wlRaw = _toDouble(data['waterLevelPercent']);

    _updateSensor('temp', tempRaw);
    _updateSensor('turb', turbRaw);
    _updateSensor('do', doRaw);
    _updateSensor('ph', phRaw);
    _updateSensor('waterlevel', wlRaw);

    _lastUpdated = DateTime.now();
    notifyListeners();
  }

  void _updateSensor(String key, double? value) {
    if (value == null || value < 0) return;

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

  bool hasSensorData(String key) => _latest.containsKey(key);
  double getLatestValue(String key) => _latest[key] ?? 0.0;

  List<double> getData(String key) => _history[key] ?? [];

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}