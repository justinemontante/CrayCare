import 'dart:async';
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sensorsSub;
  StreamSubscription<User?>? _authSub;
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
    final data = doc.data();
    // Admins do NOT own a tank — never resolve (or create) a tank for them.
    // Without this guard, _syncFromFirebase() would recreate tanks/{adminUid}
    // with its sensors subcollection on every app start (Firestore
    // auto-creates the parent doc when writing to a subcollection).
    if (data?['role'] == 'admin') return null;
    _tankId = data?['tank_id'] as String? ?? uid;
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
      } catch (e, stack) { debugPrint('[Settings] load/save error: $e\n$stack'); }
    }

    await _syncFromFirebase();
    _initialized = true;
    _listenRealtime();

    // Resolve the new user's tank before starting its threshold listener.
    // Previously _listenRealtime() ran immediately after kicking off the
    // async sync, while _tankId was still null, so it returned without ever
    // subscribing after a login/account switch.
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _sensorsSub?.cancel();
      _sensorsSub = null;
      _tankId = null;
      if (user == null) return;
      await _syncFromFirebase();
      _listenRealtime();
    });
  }

  // Real-time sync: kapag may nagbago ng threshold sa isang device (o sa
  // Firebase console), awtomatikong ma-update ang lahat ng devices na may
  // parehong account. Consistent ang sensor thresholds sa buong team.
  void _listenRealtime() {
    _sensorsSub?.cancel();
    _sensorsSub = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Admin has no tank (see _resolveTankId) — skip the listener entirely.
    final tankId = _tankId;
    if (tankId == null || tankId.isEmpty) return;
    try {
      _sensorsSub = FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .collection('sensors')
          .snapshots()
          .listen((snap) {
        if (snap.docs.isEmpty) return;
        bool changed = false;
        for (final doc in snap.docs) {
          final longKey = doc.id;
          final shortKey = _longKeyFor.entries
              .firstWhere((e) => e.value == longKey, orElse: () => const MapEntry('', ''))
              .key;
          if (shortKey.isEmpty || !_ranges.containsKey(shortKey)) continue;
          final data = doc.data();
          final min = (data['min_value'] as num?)?.toDouble();
          final max = (data['max_value'] as num?)?.toDouble();
          if (min != null && max != null &&
              (_ranges[shortKey]?['min'] != min || _ranges[shortKey]?['max'] != max)) {
            _ranges[shortKey] = {'min': min, 'max': max};
            changed = true;
          }
        }
        if (changed) {
          notifyListeners();
          // Persist locally para may cache pa rin offline.
          SharedPreferences.getInstance().then((prefs) {
            prefs.setString('sensorRanges', jsonEncode(_ranges));
          });
        }
      }, onError: (e) {
        debugPrint('[SettingsService] Realtime sync error: $e');
      });
    } catch (e) {
      debugPrint('[SettingsService] Realtime listen error: $e');
    }
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
    // Persist local state once. SensorThresholdSettings performs the canonical
    // long-name Firestore batch write and surfaces any permission/network error.
    await _saveRanges();
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

  @override
  void dispose() {
    _sensorsSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
