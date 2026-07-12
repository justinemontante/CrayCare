import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  final Map<String, List<double>> _history = {};
  final Map<String, double> _latest = {};
  bool? _turbidityAir;

  bool get turbidityAir => _turbidityAir ?? false;

  bool _initialDataLoaded = false;

  Timer? _staleTimer;
  static const _staleTimeout = Duration(seconds: 30);
  static const _initialStaleTimeout = Duration(seconds: 10);
  bool _hasLiveData = false;

  DateTime _lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastError;

  bool get initialDataLoaded => _initialDataLoaded;
  bool get hasLiveData => _hasLiveData;
  DateTime get lastUpdated => _lastUpdated;
  String? get lastError => _lastError;

  String get overallStatus {
    String status = 'NORMAL';
    for (final key in sensorKeys) {
      final zone = getZone(key);
      if (zone == 'CRITICAL') return 'CRITICAL';
      if (zone == 'WARNING') status = 'WARNING';
    }
    return status;
  }

  String getZone(String key) {
    if (!_latest.containsKey(key)) return 'UNKNOWN';
    final value = _latest[key]!;
    final ranges = SettingsService.instance.currentRanges;
    final range = ranges[key];
    if (range == null) return 'UNKNOWN';
    final min = range['min'] ?? 0.0;
    final max = range['max'] ?? 999.0;
    
    if (value < min || value > max) {
      return 'CRITICAL';
    }

    final isMaxBound = max < 999.0;
    final rangeSpan = isMaxBound ? (max - min) : min;
    final warningThreshold = rangeSpan * 0.10;
    
    final checkLower = min > 0.0;
    final checkUpper = isMaxBound;

    if ((checkLower && (value - min) < warningThreshold) ||
        (checkUpper && (max - value) < warningThreshold)) {
      return 'WARNING';
    }

    return 'OPTIMAL';
  }

  String getTrend(String key) {
    final history = _history[key];
    if (history == null || history.length < 3) return 'stable';
    final recent = history.length >= 5 ? history.sublist(history.length - 5) : history;
    final delta = recent.last - recent.first;
    final rate = delta / (recent.length - 1);

    double stableThreshold;
    double fastThreshold;

    switch (key) {
      case 'temp':
        stableThreshold = 0.02;
        fastThreshold = 0.15;
        break;
      case 'ph':
        stableThreshold = 0.01;
        fastThreshold = 0.08;
        break;
      case 'do':
        stableThreshold = 0.03;
        fastThreshold = 0.2;
        break;
      case 'turb':
        stableThreshold = 0.5;
        fastThreshold = 2.0;
        break;
      case 'waterlevel':
        stableThreshold = 0.5;
        fastThreshold = 1.5;
        break;
      default:
        stableThreshold = 0.05;
        fastThreshold = 0.3;
    }

    if (rate.abs() < stableThreshold) return 'stable';
    if (rate > 0) {
      return rate >= fastThreshold ? 'rising_fast' : 'rising';
    } else {
      return rate <= -fastThreshold ? 'falling_fast' : 'falling';
    }
  }

  double getTrendRate(String key) {
    final history = _history[key];
    if (history == null || history.length < 3) return 0.0;
    final recent = history.length >= 5 ? history.sublist(history.length - 5) : history;
    final delta = recent.last - recent.first;
    return delta / (recent.length - 1);
  }

  void _initFirebaseListener() {
    _subscription?.cancel();
    _initialDataLoaded = false;
    _staleTimer?.cancel();
    _subscription = FirebaseFirestore.instance
        .collection('sensorReadings')
        .doc('latest')
        .snapshots()
        .listen(
      (snapshot) {
        _lastError = null;
        if (!snapshot.exists || snapshot.data() == null) return;
        _parseAndUpdate(snapshot.data()!);
      },
      onError: (error) {
        _lastError = error.toString();
        debugPrint('[SensorService] Firestore stream error: $error');
        notifyListeners();
      },
    );
  }

  void _parseAndUpdate(Map<String, dynamic> data) {
    final isInitialLoad = !_initialDataLoaded;
    if (!_initialDataLoaded) {
      _initialDataLoaded = true;
    }

    if (isInitialLoad) {
      _staleTimer = Timer(_initialStaleTimeout, _markStale);
      notifyListeners();
      return;
    }

    final tempRaw = _toDouble(data['temperature']);
    final turbRaw = _toDouble(data['turbidity']);
    final doRaw = _toDouble(data['dissolvedOxygen']);
    final phRaw = _toDouble(data['phLevel']);
    final wlRaw = _toDouble(data['waterLevel']);
    final turbAirRaw = data['turbidityAir'];
    _turbidityAir = turbAirRaw is bool ? turbAirRaw : (turbAirRaw == true);

    _updateSensor('temp', tempRaw);
    if (_turbidityAir != true) {
      _updateSensor('turb', turbRaw);
    } else {
      _latest.remove('turb');
    }
    _updateSensor('do', doRaw);
    _updateSensor('ph', phRaw);
    _updateSensor('waterlevel', wlRaw);

    _lastUpdated = DateTime.now();
    _hasLiveData = true;
    _staleTimer?.cancel();
    _staleTimer = Timer(_staleTimeout, _markStale);
    notifyListeners();
  }

  void _markStale() {
    _latest.clear();
    _lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);
    _hasLiveData = false;
    notifyListeners();
    debugPrint('[SensorService] Data stale - ESP32 offline');
  }

  void _updateSensor(String key, double? value) {
    if (value == null || value < 0) {
      _latest.remove(key);
      return;
    }
    if (value == 0 && key != 'turb' && !_latest.containsKey(key)) return;

    if (!_isValidReading(key, value)) return;

    _latest[key] = value;

    if (_history[key] == null) _history[key] = [];

    _history[key]!.add(value);
    if (_history[key]!.length > 60) {
      _history[key]!.removeAt(0);
    }
  }

  bool _isValidReading(String key, double value) {
    switch (key) {
      case 'temp':
        return value >= 0 && value <= 60;
      case 'ph':
        return value >= 2 && value <= 12;
      case 'do':
        return value >= 0 && value <= 15;
      case 'turb':
        return value >= 0 && value <= 500;
      case 'waterlevel':
        return value >= 0 && value <= 300;
      default:
        return true;
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

  bool hasFreshData(String key) =>
      _latest.containsKey(key) &&
      DateTime.now().difference(_lastUpdated) < _staleTimeout;

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

    final records = <Map<String, dynamic>>[];
    for (final dateStr in days) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('sensorReadings')
            .doc('history')
            .collection(dateStr)
            .orderBy('timestamp')
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          records.add(data);
        }
      } catch (_) {}
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
