import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:convert';
import '../models/crayfish_stage.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  bool _initialized = false;
  late Map<String, Map<String, double>> _ranges;

  DatabaseReference get _thresholdsRef =>
      FirebaseDatabase.instance.ref('sensor_readings/config');

  Map<String, Map<String, double>> get currentRanges => _ranges;

  Future<void> init() async {
    if (_initialized) return;
    _ranges = {};
    for (final e in defaultRanges.entries) {
      _ranges[e.key] = Map.from(e.value);
    }

    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('sensorRanges');
    if (json != null) {
      try {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        for (final sensorEntry in decoded.entries) {
          final range = sensorEntry.value as Map<String, dynamic>;
          _ranges[sensorEntry.key] = {
            'min': (range['min'] as num).toDouble(),
            'max': (range['max'] as num).toDouble(),
          };
        }
      } catch (_) {}
    }

    await _syncFromFirebase();
    _initialized = true;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _syncFromFirebase();
      }
    });
  }

  Future<void> _syncFromFirebase() async {
    try {
      final snapshot = await _thresholdsRef.child('ranges').get();
      if (snapshot.value == null) {
        await _syncToFirebase();
        return;
      }
      final data = snapshot.value as Map<Object?, Object?>;
      for (final entry in data.entries) {
        final sensorKey = entry.key.toString();
        if (_ranges.containsKey(sensorKey)) {
          final range = entry.value as Map<Object?, Object?>;
          final min = (range['min'] as num?)?.toDouble();
          final max = (range['max'] as num?)?.toDouble();
          if (min != null && max != null) {
            _ranges[sensorKey] = {'min': min, 'max': max};
          }
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sensorRanges', jsonEncode(_ranges));
    } catch (e) {
      debugPrint('[SettingsService] Firebase sync failed: $e');
    }
  }

  Future<void> _syncToFirebase() async {
    try {
      for (final sensorEntry in _ranges.entries) {
        await _thresholdsRef
            .child('ranges')
            .child(sensorEntry.key)
            .set(sensorEntry.value);
      }
    } catch (e) {
      debugPrint('[SettingsService] Firebase syncTo failed: $e');
    }
  }

  Future<void> updateRange(
    String sensorKey,
    double min,
    double max,
  ) async {
    if (!_ranges.containsKey(sensorKey)) return;
    _ranges[sensorKey] = {'min': min, 'max': max};
    notifyListeners();
    await _saveRanges();
    try {
      await _thresholdsRef.child('ranges').child(sensorKey).set({
        'min': min,
        'max': max,
      });
    } catch (e) {
      debugPrint('[SettingsService] Firebase updateRange failed: $e');
    }
  }

  Future<void> resetToDefaults() async {
    _ranges = {};
    for (final e in defaultRanges.entries) {
      _ranges[e.key] = Map.from(e.value);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sensorRanges');
    try {
      for (final sensorEntry in defaultRanges.entries) {
        await _thresholdsRef
            .child('ranges')
            .child(sensorEntry.key)
            .set(sensorEntry.value);
      }
    } catch (e) {
      debugPrint('[SettingsService] Firebase resetToDefaults failed: $e');
    }
  }

  Future<void> _saveRanges() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sensorRanges', jsonEncode(_ranges));
  }
}
