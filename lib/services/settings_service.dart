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
  // 'waterlevel','feedlevel'), but Firestore stores thresholds under
  // tanks/{tank_id}/sensors/{longName}.
  static const Map<String, String> _longKeyFor = {
    'temp': 'temperature',
    'ph': 'ph_level',
    'do': 'dissolved_oxygen',
    'turb': 'turbidity',
    'waterlevel': 'water_level',
    'feedlevel': 'feed_level',
  };

  String? _tankId;

  void _resetRangesToDefaults() {
    _ranges = {};
    for (final e in defaultRanges.entries) {
      _ranges[e.key] = Map<String, double>.from(e.value);
    }
  }

  String _cacheKeyForTank(String tankId) => 'sensorRanges_$tankId';

  Future<void> _loadTankCache(String tankId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_cacheKeyForTank(tankId));
    if (json == null) return;
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      for (final sensorEntry in decoded.entries) {
        final range = sensorEntry.value as Map<String, dynamic>;
        final min = range['min'];
        final max = range['max'];
        if (min is num && max is num && _ranges.containsKey(sensorEntry.key)) {
          _ranges[sensorEntry.key] = {
            'min': min.toDouble(),
            'max': max.toDouble(),
            if (range['critical'] is num)
              'critical': (range['critical'] as num).toDouble(),
            if (range['capacity_grams'] is num)
              'capacity_grams': (range['capacity_grams'] as num).toDouble(),
          };
        }
      }
    } catch (e, stack) {
      debugPrint('[Settings] tank cache load error: $e\n$stack');
    }
  }

  Future<String?> _resolveTankId(String uid) async {
    if (_tankId != null) return _tankId;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data();
    // Admins do NOT own a tank — never resolve (or create) a tank for them.
    if (data?['role'] == 'admin') return null;
    _tankId = data?['tank_id'] as String? ?? uid;
    return _tankId;
  }

  Future<void> init() async {
    if (_initialized) return;
    _resetRangesToDefaults();

    // Remove the old global cache key. Threshold cache is now tank-scoped so
    // values from one owner can never seed another owner's tank.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sensorRanges');

    await _syncFromFirebase();
    _initialized = true;
    _listenRealtime();

    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _sensorsSub?.cancel();
      _sensorsSub = null;
      _tankId = null;
      _resetRangesToDefaults();
      notifyListeners();
      if (user == null) return;
      await _syncFromFirebase();
      _listenRealtime();
    });
  }

  // Real-time sync: when thresholds change on another device or in Firebase,
  // update this device and persist only to the current tank's local cache.
  void _listenRealtime() {
    _sensorsSub?.cancel();
    _sensorsSub = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final tankId = _tankId;
    if (tankId == null || tankId.isEmpty) return;
    try {
      _sensorsSub = FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .collection('sensors')
          .snapshots()
          .listen(
            (snap) {
              if (snap.docs.isEmpty) return;
              bool changed = false;
              for (final doc in snap.docs) {
                final longKey = doc.id;
                final shortKey = _longKeyFor.entries
                    .firstWhere(
                      (e) => e.value == longKey,
                      orElse: () => const MapEntry('', ''),
                    )
                    .key;
                if (shortKey.isEmpty || !_ranges.containsKey(shortKey))
                  continue;
                final data = doc.data();
                final min = (data['min_value'] as num?)?.toDouble();
                final max = (data['max_value'] as num?)?.toDouble();
                final critical = (data['critical_value'] as num?)?.toDouble();
                final capacity = (data['hopper_capacity_grams'] as num?)
                    ?.toDouble();
                if (min != null &&
                    max != null &&
                    (_ranges[shortKey]?['min'] != min ||
                        _ranges[shortKey]?['max'] != max)) {
                  _ranges[shortKey] = {
                    'min': min,
                    'max': max,
                    if (critical != null) 'critical': critical,
                    if (capacity != null) 'capacity_grams': capacity,
                  };
                  changed = true;
                }
              }
              if (changed) {
                notifyListeners();
                SharedPreferences.getInstance().then((prefs) {
                  prefs.setString(
                    _cacheKeyForTank(tankId),
                    jsonEncode(_ranges),
                  );
                });
              }
            },
            onError: (e) {
              debugPrint('[SettingsService] Realtime sync error: $e');
            },
          );
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

      // Start only from defaults + this tank's own local cache.
      _resetRangesToDefaults();
      await _loadTankCache(tankId);

      final sensorsSnap = await FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .collection('sensors')
          .get();

      if (sensorsSnap.docs.isEmpty) {
        await _syncToFirebase();
        notifyListeners();
        return;
      }

      bool anyApplied = false;
      final foundSensorDocs = <String>{};
      for (final doc in sensorsSnap.docs) {
        final longKey = doc.id;
        foundSensorDocs.add(longKey);
        final shortKey = _longKeyFor.entries
            .firstWhere(
              (e) => e.value == longKey,
              orElse: () => const MapEntry('', ''),
            )
            .key;
        if (shortKey.isEmpty || !_ranges.containsKey(shortKey)) continue;
        final data = doc.data();
        final min = (data['min_value'] as num?)?.toDouble();
        final max = (data['max_value'] as num?)?.toDouble();
        final critical = (data['critical_value'] as num?)?.toDouble();
        final capacity = (data['hopper_capacity_grams'] as num?)?.toDouble();
        if (min != null && max != null) {
          _ranges[shortKey] = {
            'min': min,
            'max': max,
            if (critical != null) 'critical': critical,
            if (capacity != null) 'capacity_grams': capacity,
          };
          anyApplied = true;
        }
      }
      if (!anyApplied) {
        await _syncToFirebase();
        notifyListeners();
        return;
      }

      // Existing tanks created before a newly supported sensor was added do
      // not have its threshold document. Seed only missing documents; never
      // overwrite an owner's established water-quality thresholds.
      final missingEntries = _longKeyFor.entries.where(
        (entry) => !foundSensorDocs.contains(entry.value),
      );
      if (missingEntries.isNotEmpty) {
        final tankRef = FirebaseFirestore.instance
            .collection('tanks')
            .doc(tankId);
        final batch = FirebaseFirestore.instance.batch();
        for (final entry in missingEntries) {
          final values = defaultRanges[entry.key]!;
          batch.set(tankRef.collection('sensors').doc(entry.value), {
            'min_value': values['min'],
            'max_value': values['max'],
            if (entry.key == 'feedlevel') ...{
              'critical_value': values['critical'],
              'hopper_capacity_grams': values['capacity_grams'],
            },
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyForTank(tankId), jsonEncode(_ranges));
      notifyListeners();
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

      final tankRef = FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId);
      final batch = FirebaseFirestore.instance.batch();
      for (final e in _ranges.entries) {
        final longKey = _longKeyFor[e.key];
        if (longKey == null) continue;
        batch.set(tankRef.collection('sensors').doc(longKey), {
          'min_value': e.value['min'],
          'max_value': e.value['max'],
          if (e.key == 'feedlevel') ...{
            'critical_value': e.value['critical'],
            'hopper_capacity_grams': e.value['capacity_grams'],
          },
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[SettingsService] Firestore syncTo failed: $e');
    }
  }

  Future<void> updateRange(String sensorKey, double min, double max) async {
    if (!_ranges.containsKey(sensorKey)) return;
    _ranges[sensorKey] = {'min': min, 'max': max};
    notifyListeners();
    // SensorThresholdSettings performs the canonical Firestore write; this
    // stores only the current tank's offline copy.
    await _saveRanges();
  }

  Future<void> updateFeedLevelConfig({
    required double critical,
    required double low,
    required double capacityGrams,
  }) async {
    _ranges['feedlevel'] = {
      'min': low,
      'max': 100.0,
      'critical': critical,
      'capacity_grams': capacityGrams,
    };
    notifyListeners();
    await _saveRanges();
  }

  Future<void> resetToDefaults() async {
    _resetRangesToDefaults();
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final tankId = await _resolveTankId(user.uid);
    if (tankId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKeyForTank(tankId));

    try {
      final tankRef = FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId);
      final batch = FirebaseFirestore.instance.batch();
      for (final e in defaultRanges.entries) {
        final longKey = _longKeyFor[e.key];
        if (longKey == null) continue;
        batch.set(tankRef.collection('sensors').doc(longKey), {
          'min_value': e.value['min'],
          'max_value': e.value['max'],
          if (e.key == 'feedlevel') ...{
            'critical_value': e.value['critical'],
            'hopper_capacity_grams': e.value['capacity_grams'],
          },
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('[SettingsService] Firestore resetToDefaults failed: $e');
    }
  }

  Future<void> _saveRanges() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final tankId = await _resolveTankId(user.uid);
    if (tankId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKeyForTank(tankId), jsonEncode(_ranges));
  }

  @override
  void dispose() {
    _sensorsSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
