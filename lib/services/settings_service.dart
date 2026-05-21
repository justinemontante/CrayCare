import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/crayfish_stage.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  bool _initialized = false;
  String _currentStage = 'growout_phase';
  late Map<String, Map<String, Map<String, double>>> _stageRanges;

  String get currentStage => _currentStage;
  CrayfishStage get currentStageObj => CrayfishStage.fromName(_currentStage);

  Map<String, Map<String, double>> get currentRanges =>
      _stageRanges[_currentStage] ?? defaultStageRanges['growout_phase']!;

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
    _initialized = true;
  }

  Future<void> setCurrentStage(String name) async {
    _currentStage = name;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentStage', name);
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
  }

  Future<void> resetToDefaults() async {
    _currentStage = 'growout_phase';
    for (final s in CrayfishStage.all) {
      _stageRanges[s.name] = {};
      for (final e in defaultStageRanges[s.name]!.entries) {
        _stageRanges[s.name]![e.key] = Map.from(e.value);
      }
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentStage', 'growout_phase');
    await prefs.remove('stageRanges');
  }

  Future<void> _saveRanges() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stageRanges', jsonEncode(_stageRanges));
  }
}
