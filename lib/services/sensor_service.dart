import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:math';

class SensorService extends ChangeNotifier {
  static final SensorService instance = SensorService._();
  SensorService._() {
    _generateInitialData();
    _startLiveUpdates();
  }

  final _rng = Random(42);
  final Map<String, List<double>> _data = {};
  Timer? _liveTimer;

  // Configuration for sensors
  final Map<String, Map<String, double>> seeds = {
    'temp': {'min': 24.0, 'max': 32.0},
    'ph': {'min': 6.5, 'max': 9.0},
    'do': {'min': 2.5, 'max': 7.0},
    'turb': {'min': 10.0, 'max': 70.0},
    'waterlevel': {'min': 100.0, 'max': 200.0},
  };

  void _generateInitialData() {
    seeds.forEach((key, bounds) {
      _data[key] = List.generate(60, (_) {
        return bounds['min']! +
            _rng.nextDouble() * (bounds['max']! - bounds['min']!);
      });
    });
  }

  void _startLiveUpdates() {
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _pushNewData();
    });
  }

  DateTime lastUpdated = DateTime.now();

  void _pushNewData() {
    seeds.forEach((key, bounds) {
      final list = _data[key]!;
      list.removeAt(0);
      final lastVal = list.last;
      // Increased fluctuation for visible changes
      double newVal = lastVal + (_rng.nextDouble() - 0.5) * 3.0;
      newVal = newVal.clamp(bounds['min']!, bounds['max']!);
      list.add(newVal);
    });
    lastUpdated = DateTime.now();
    notifyListeners();
  }

  List<double> getData(String key) => _data[key] ?? [];
  double getLatestValue(String key) => _data[key]?.last ?? 0.0;
}
