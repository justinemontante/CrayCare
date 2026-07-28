import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../models/sensor_defaults.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  bool _initialized = false;
  late Map<String, Map<String, double>> _ranges;

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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('sensorThresholds')
          .doc(user.uid)
          .get();
      if (!doc.exists || doc.data() == null) {
        await _syncToFirebase();
        return;
      }
      final data = doc.data()!;
      final ranges = data['ranges'] as Map<String, dynamic>?;
      if (ranges == null) {
        await _syncToFirebase();
        return;
      }
      for (final entry in ranges.entries) {
        final sensorKey = entry.key;
        if (_ranges.containsKey(sensorKey)) {
          final range = entry.value as Map<String, dynamic>;
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
      debugPrint('[SettingsService] Firestore sync failed: $e');
    }
  }

  Future<void> _syncToFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final rangesPayload = {
        for (final e in _ranges.entries)
          e.key: {'min': e.value['min'], 'max': e.value['max']},
      };
      // Save per-user sensor thresholds for the app.
      await FirebaseFirestore.instance.collection('sensorThresholds').doc(user.uid).set({
        'ranges': rangesPayload,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Mirror to sensorThresholds/default so the ESP32 firmware picks up the thresholds.
      // ESP reads: Firebase.Firestore.getDocument(..., "sensorThresholds/default", "ranges")
      await FirebaseFirestore.instance.collection('sensorThresholds').doc('default').set({
        'ranges': rangesPayload,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SettingsService] Firestore syncTo failed: $e');
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final update = {
        'ranges.$sensorKey.min': min,
        'ranges.$sensorKey.max': max,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance
          .collection('sensorThresholds')
          .doc(user.uid)
          .update(update);
      // Mirror to sensorThresholds/default so the ESP32 picks up the new threshold.
      await FirebaseFirestore.instance
          .collection('sensorThresholds')
          .doc('default')
          .set(update, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SettingsService] Firestore updateRange failed: $e');
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final defaultPayload = {
        'ranges': {
          for (final e in defaultRanges.entries)
            e.key: {'min': e.value['min'], 'max': e.value['max']},
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await FirebaseFirestore.instance.collection('sensorThresholds').doc(user.uid).set(defaultPayload);
      // Mirror to sensorThresholds/default so the ESP32 picks up the reset thresholds.
      await FirebaseFirestore.instance
          .collection('sensorThresholds')
          .doc('default')
          .set(defaultPayload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[SettingsService] Firestore resetToDefaults failed: $e');
    }
  }

  Future<void> _saveRanges() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sensorRanges', jsonEncode(_ranges));
  }
}
