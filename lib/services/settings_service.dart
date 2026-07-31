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

  // The app uses short internal sensor keys ('temp','ph','do','turb',
  // 'waterlevel'), but the new Firestore schema stores thresholds under
  // tanks/{tank_id}/sensors/{longName} with long names to match the
  // sensor_readings field names. This maps between the two.
  static const Map<String, String> _longKeyFor = {
    'temp': 'temperature',
    'ph': 'ph_level',
    'do': 'dissolved_oxygen',
    'turb': 'turbidity',
    'waterlevel': 'water_level',
  };

  String? _tankId;

  Future<String?> _resolveTankId(String uid) async {
    if (_tankId != null) return _tankId;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    _tankId = doc.data()?['tank_id'] as String? ?? uid;
    return _tankId;
  }

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
        _tankId = null;
        _syncFromFirebase();
      }
    });
  }

  Future<void> _syncFromFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final tankId = await _resolveTankId(user.uid);
      if (tankId == null) return;

      // tanks/{tank_id}/sensors/{longKey} — one doc per sensor.
      final sensorsSnap = await FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .collection('sensors')
          .get();

      if (sensorsSnap.docs.isEmpty) {
        await _syncToFirebase();
        return;
      }

      bool anyApplied = false;
      for (final doc in sensorsSnap.docs) {
        final longKey = doc.id;
        final shortKey = _longKeyFor.entries
            .firstWhere((e) => e.value == longKey, orElse: () => const MapEntry('', ''))
            .key;
        if (shortKey.isEmpty || !_ranges.containsKey(shortKey)) continue;
        final data = doc.data();
        final min = (data['min_value'] as num?)?.toDouble();
        final max = (data['max_value'] as num?)?.toDouble();
        if (min != null && max != null) {
          _ranges[shortKey] = {'min': min, 'max': max};
          anyApplied = true;
        }
      }
      if (!anyApplied) {
        await _syncToFirebase();
        return;
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
      final tankId = await _resolveTankId(user.uid);
      if (tankId == null) return;

      final tankRef = FirebaseFirestore.instance.collection('tanks').doc(tankId);
      final batch = FirebaseFirestore.instance.batch();
      for (final e in _ranges.entries) {
        final longKey = _longKeyFor[e.key];
        if (longKey == null) continue;
        batch.set(tankRef.collection('sensors').doc(longKey), {
          'min_value': e.value['min'],
          'max_value': e.value['max'],
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
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
      final tankId = await _resolveTankId(user.uid);
      final longKey = _longKeyFor[sensorKey];
      if (tankId == null || longKey == null) return;

      // tanks/{tank_id}/sensors/{longKey} — the ESP32 firmware reads
      // thresholds directly from here (per-tank, not a global default).
      await FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .collection('sensors')
          .doc(longKey)
          .set({
        'min_value': min,
        'max_value': max,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
      final tankId = await _resolveTankId(user.uid);
      if (tankId == null) return;

      final tankRef = FirebaseFirestore.instance.collection('tanks').doc(tankId);
      final batch = FirebaseFirestore.instance.batch();
      for (final e in defaultRanges.entries) {
        final longKey = _longKeyFor[e.key];
        if (longKey == null) continue;
        batch.set(tankRef.collection('sensors').doc(longKey), {
          'min_value': e.value['min'],
          'max_value': e.value['max'],
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[SettingsService] Firestore resetToDefaults failed: $e');
    }
  }

  Future<void> _saveRanges() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sensorRanges', jsonEncode(_ranges));
  }
}
