import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:convert';
import '../models/crayfish_stage.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  bool _initialized = false;
  String _currentStage = 'pre_adult';
  late Map<String, Map<String, Map<String, double>>> _stageRanges;

  final DatabaseReference _thresholdsRef = FirebaseDatabase.instance.ref(
    'sensor_readings/thresholds',
  );

  String get currentStage => _currentStage;
  CrayfishStage get currentStageObj => CrayfishStage.fromName(_currentStage);

  Map<String, Map<String, double>> get currentRanges =>
      _stageRanges[_currentStage] ?? defaultStageRanges['pre_adult']!;

  Map<String, Map<String, Map<String, double>>> get allRanges => _stageRanges;

  Future<void> init() async {
    if (_initialized) return;
    _stageRanges = {};
    for (final s in CrayfishStage.all) {
      _stageRanges[s.name] = {};
      for (final e in defaultStageRanges[s.name]!.entries) {
        _stageRanges[s.name]![e.key] = Map.from(e.value);
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final stage = prefs.getString('currentStage');
    if (stage != null && CrayfishStage.all.any((s) => s.name == stage)) {
      _currentStage = stage;
    }
    final json = prefs.getString('stageRanges');
    if (json != null) {
      try {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        for (final sEntry in decoded.entries) {
          final stageName = sEntry.key;
          if (_stageRanges.containsKey(stageName)) {
            for (final sensorEntry in (sEntry.value as Map<String, dynamic>).entries) {
              final range = sensorEntry.value as Map<String, dynamic>;
              _stageRanges[stageName]![sensorEntry.key] = {
                'min': (range['min'] as num).toDouble(),
                'max': (range['max'] as num).toDouble(),
              };
            }
          }
        }
      } catch (_) {}
    }

    await _syncFromFirebase();
    _initialized = true;
  }

  Future<void> _syncFromFirebase() async {
    try {
      final snapshot = await _thresholdsRef.get();
      if (snapshot.value == null) {
        await _syncToFirebase();
        return;
      }
      final data = snapshot.value as Map<Object?, Object?>;
      for (final entry in data.entries) {
        final key = entry.key.toString();
        if (key == 'selectedStage') {
          final fbStage = entry.value.toString();
          if (CrayfishStage.all.any((s) => s.name == fbStage)) {
            _currentStage = fbStage;
          }
        } else if (_stageRanges.containsKey(key)) {
          final stageData = entry.value as Map<Object?, Object?>;
          for (final sensorEntry in stageData.entries) {
            final sensorKey = sensorEntry.key.toString();
            if (_stageRanges[key]!.containsKey(sensorKey)) {
              final range = sensorEntry.value as Map<Object?, Object?>;
              final min = (range['min'] as num?)?.toDouble();
              final max = (range['max'] as num?)?.toDouble();
              if (min != null && max != null) {
                _stageRanges[key]![sensorKey] = {'min': min, 'max': max};
              }
            }
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('currentStage', _currentStage);
      await prefs.setString('stageRanges', jsonEncode(_stageRanges));
    } catch (e) {
      debugPrint('[SettingsService] Firebase sync failed: $e');
    }
  }

  Future<void> _syncToFirebase() async {
    try {
      await _thresholdsRef.child('selectedStage').set(_currentStage);
      for (final s in CrayfishStage.all) {
        final ranges = _stageRanges[s.name]!;
        for (final sensorEntry in ranges.entries) {
          await _thresholdsRef
              .child(s.name)
              .child(sensorEntry.key)
              .set(sensorEntry.value);
        }
      }
    } catch (e) {
      debugPrint('[SettingsService] Firebase syncTo failed: $e');
    }
  }

  Future<void> setCurrentStage(String name) async {
    _currentStage = name;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentStage', name);
    try {
      await _thresholdsRef.child('selectedStage').set(name);
    } catch (e) {
      debugPrint('[SettingsService] Firebase setCurrentStage failed: $e');
    }
  }

  Future<void> updateRange(
    String stageName,
    String sensorKey,
    double min,
    double max,
  ) async {
    if (_stageRanges[stageName] == null) return;
    _stageRanges[stageName]![sensorKey] = {'min': min, 'max': max};
    notifyListeners();
    await _saveRanges();
    try {
      await _thresholdsRef.child(stageName).child(sensorKey).set({'min': min, 'max': max});
    } catch (e) {
      debugPrint('[SettingsService] Firebase updateRange failed: $e');
    }
  }

  Future<void> resetToDefaults() async {
    _currentStage = 'pre_adult';
    for (final s in CrayfishStage.all) {
      _stageRanges[s.name] = {};
      for (final e in defaultStageRanges[s.name]!.entries) {
        _stageRanges[s.name]![e.key] = Map.from(e.value);
      }
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentStage', 'pre_adult');
    await prefs.remove('stageRanges');
    try {
      await _thresholdsRef.child('selectedStage').set('pre_adult');
      for (final s in CrayfishStage.all) {
        final ranges = defaultStageRanges[s.name]!;
        for (final sensorEntry in ranges.entries) {
          await _thresholdsRef
              .child(s.name)
              .child(sensorEntry.key)
              .set(sensorEntry.value);
        }
      }
    } catch (e) {
      debugPrint('[SettingsService] Firebase resetToDefaults failed: $e');
    }
  }

  Future<void> _saveRanges() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stageRanges', jsonEncode(_stageRanges));
  }
}
