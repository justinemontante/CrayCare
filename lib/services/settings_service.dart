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

  Map<String, double>? _rangeFromSensorDocument(
    String sensorKey,
    Map<String, dynamic> data,
  ) {
    if (sensorKey == 'waterlevel') {
      final oldLow = (data['min_value'] as num?)?.toDouble();
      final low = (data['low_value'] as num?)?.toDouble() ?? oldLow;
      final critical =
          (data['critical_value'] as num?)?.toDouble() ??
          (oldLow == null ? null : (oldLow - 5).clamp(0, oldLow).toDouble());
      if (low == null || critical == null) return null;
      return {'low': low, 'critical': critical};
    }
    if (sensorKey == 'feedlevel') {
      // Read the old min_value as a migration fallback, but all new writes
      // use the same Low/Critical shape as Water Level.
      final low =
          (data['low_value'] as num?)?.toDouble() ??
          (data['min_value'] as num?)?.toDouble();
      final critical = (data['critical_value'] as num?)?.toDouble();
      if (low == null || critical == null) return null;
      return {'low': low, 'critical': critical};
    }
    final min = (data['min_value'] as num?)?.toDouble();
    final max = (data['max_value'] as num?)?.toDouble();
    if (min == null || max == null) return null;
    final critical = (data['critical_value'] as num?)?.toDouble();
    return {'min': min, 'max': max, if (critical != null) 'critical': critical};
  }

  Future<void> _loadTankCache(String tankId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_cacheKeyForTank(tankId));
    if (json == null) return;
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      for (final sensorEntry in decoded.entries) {
        final range = sensorEntry.value as Map<String, dynamic>;
        if (sensorEntry.key == 'waterlevel' || sensorEntry.key == 'feedlevel') {
          final oldLow = range['min'];
          final low = range['low'] ?? oldLow;
          final critical =
              range['critical'] ??
              (oldLow is num ? (oldLow - 5).clamp(0, oldLow) : null);
          if (low is num && critical is num) {
            _ranges[sensorEntry.key] = {
              'low': low.toDouble(),
              'critical': critical.toDouble(),
            };
          }
          continue;
        }
        final min = range['min'];
        final max = range['max'];
        if (min is num && max is num && _ranges.containsKey(sensorEntry.key)) {
          _ranges[sensorEntry.key] = {
            'min': min.toDouble(),
            'max': max.toDouble(),
            if (range['critical'] is num)
              'critical': (range['critical'] as num).toDouble(),
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
    if (data?['role']?.toString().trim().toLowerCase() == 'admin') return null;
    _tankId = uid;
    return _tankId;
  }

  Future<void> init() async {
    if (_initialized) return;
    // Claim initialization before the first await so two callers cannot race
    // and attach duplicate auth/Firestore listeners.
    _initialized = true;
    try {
      _resetRangesToDefaults();

      // Remove the old global cache key. Threshold cache is now tank-scoped so
      // values from one owner can never seed another owner's tank.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sensorRanges');

      await _syncFromFirebase();
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
    } catch (_) {
      // Allow a later caller to retry if initialization itself fails before the
      // service has established its subscriptions.
      _initialized = false;
      rethrow;
    }
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
                if (shortKey.isEmpty || !_ranges.containsKey(shortKey)) {
                  continue;
                }
                final data = doc.data();
                final next = _rangeFromSensorDocument(shortKey, data);
                if (next == null) continue;
                final current = _ranges[shortKey];
                if (!mapEquals(current, next)) {
                  _ranges[shortKey] = next;
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

      final tank = await FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .get();
      if (!tank.exists ||
          tank.data()?['owner_uid'] != user.uid ||
          tank.data()?['is_initialized'] != true) {
        // Registration intentionally has no tank. Keep local defaults and let
        // the realtime listener pick up sensor documents after Tank Setup.
        notifyListeners();
        return;
      }

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
      DocumentReference<Map<String, dynamic>>? legacyWaterDocRef;
      double? migratedWaterLow;
      double? migratedWaterCritical;
      DocumentReference<Map<String, dynamic>>? legacyFeedDocRef;
      double? migratedFeedLow;
      double? migratedFeedCritical;
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
        final next = _rangeFromSensorDocument(shortKey, data);
        if (next != null) {
          _ranges[shortKey] = next;
          anyApplied = true;
          if (shortKey == 'waterlevel' && data['low_value'] == null) {
            legacyWaterDocRef = doc.reference;
            migratedWaterLow = next['low'];
            migratedWaterCritical = next['critical'];
          }
          if (shortKey == 'feedlevel' &&
              (data['low_value'] == null ||
                  data.containsKey('min_value') ||
                  data.containsKey('max_value'))) {
            legacyFeedDocRef = doc.reference;
            migratedFeedLow = next['low'];
            migratedFeedCritical = next['critical'];
          }
        }
      }

      if (legacyWaterDocRef != null &&
          migratedWaterLow != null &&
          migratedWaterCritical != null) {
        try {
          await legacyWaterDocRef.set({
            'low_value': migratedWaterLow,
            'critical_value': migratedWaterCritical,
            'min_value': FieldValue.delete(),
            'max_value': FieldValue.delete(),
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('[SettingsService] Water threshold migration failed: $e');
        }
      }
      if (legacyFeedDocRef != null &&
          migratedFeedLow != null &&
          migratedFeedCritical != null) {
        try {
          await legacyFeedDocRef.set({
            'low_value': migratedFeedLow,
            'critical_value': migratedFeedCritical,
            'min_value': FieldValue.delete(),
            'max_value': FieldValue.delete(),
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('[SettingsService] Feed threshold migration failed: $e');
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
            if (entry.key == 'waterlevel' || entry.key == 'feedlevel') ...{
              'low_value': values['low'],
              'critical_value': values['critical'],
            } else ...{
              'min_value': values['min'],
              'max_value': values['max'],
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

      final tank = await FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .get();
      if (!tank.exists ||
          tank.data()?['owner_uid'] != user.uid ||
          tank.data()?['is_initialized'] != true) {
        return;
      }

      final tankRef = FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId);
      final batch = FirebaseFirestore.instance.batch();
      for (final e in _ranges.entries) {
        final longKey = _longKeyFor[e.key];
        if (longKey == null) continue;
        batch.set(tankRef.collection('sensors').doc(longKey), {
          if (e.key == 'waterlevel' || e.key == 'feedlevel') ...{
            'low_value': e.value['low'],
            'critical_value': e.value['critical'],
            'min_value': FieldValue.delete(),
            'max_value': FieldValue.delete(),
          } else ...{
            'min_value': e.value['min'],
            'max_value': e.value['max'],
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
  }) async {
    _ranges['feedlevel'] = {'low': low, 'critical': critical};
    notifyListeners();
    await _saveRanges();
  }

  Future<void> updateWaterLevelConfig({
    required double critical,
    required double low,
  }) async {
    _ranges['waterlevel'] = {'low': low, 'critical': critical};
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
      final tank = await tankRef.get();
      if (!tank.exists ||
          tank.data()?['owner_uid'] != user.uid ||
          tank.data()?['is_initialized'] != true) {
        return;
      }
      final batch = FirebaseFirestore.instance.batch();
      for (final e in defaultRanges.entries) {
        final longKey = _longKeyFor[e.key];
        if (longKey == null) continue;
        batch.set(tankRef.collection('sensors').doc(longKey), {
          if (e.key == 'waterlevel' || e.key == 'feedlevel') ...{
            'low_value': e.value['low'],
            'critical_value': e.value['critical'],
            'min_value': FieldValue.delete(),
            'max_value': FieldValue.delete(),
          } else ...{
            'min_value': e.value['min'],
            'max_value': e.value['max'],
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
    _sensorsSub = null;
    _authSub?.cancel();
    _authSub = null;
    _initialized = false;
    super.dispose();
  }
}
