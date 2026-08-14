import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'settings_service.dart';
import 'connectivity_service.dart';

class SensorService extends ChangeNotifier {
  static final SensorService instance = SensorService._();
  SensorService._() {
    if (FirebaseAuth.instance.currentUser != null) {
      _initFirebaseListener();
    }
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _initFirebaseListener();
      } else {
        _subscription?.cancel();
        _subscription = null;
      }
    });
    ConnectivityService.instance.addOnConnectCallback(_onReconnect);
  }

  void _onReconnect() {
    debugPrint('[SensorService] Internet reconnected — refreshing listeners');
    if (FirebaseAuth.instance.currentUser != null) {
      _initFirebaseListener();
    }
  }

  static const List<String> sensorKeys = [
    'temp',
    'ph',
    'do',
    'turb',
    'waterlevel',
  ];

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  /// Resolved tank_id for the signed-in user (from users/{uid}.tank_id).
  /// Sensor data now lives at tanks/{tank_id}/sensor_readings/latest.
  String? _tankId;

  final Map<String, List<double>> _history = {};
  final Map<String, double> _latest = {};
  bool? _turbidityAir;

  bool get turbidityAir => _turbidityAir ?? false;

  bool _initialDataLoaded = false;

  Timer? _staleTimer;
  Timer? _periodicCheckTimer;
  static const _staleTimeout = Duration(seconds: 10);
  bool _hasLiveData = false;

  DateTime _lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastError;
  int _bufferedEntries = 0;

  bool get initialDataLoaded => _initialDataLoaded;
  bool get hasLiveData => _hasLiveData;
  bool get isEspOnline =>
      _hasLiveData && DateTime.now().difference(_lastUpdated) <= _staleTimeout;
  DateTime get lastUpdated => _lastUpdated;
  String? get lastError => _lastError;
  /// Pending offline readings the ESP32 is flushing (from buffered_entries
  /// advertised in the 5-sec latest payload). >0 => show "Syncing N…".
  int get bufferedEntries => _bufferedEntries;

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

  /// Average per-reading change over the last 5 live readings.
  /// Returns 0.0 when there is insufficient history (< 3 points).
  double getTrendRate(String key) {
    final history = _history[key];
    if (history == null || history.length < 3) return 0.0;
    final recent = history.length >= 5 ? history.sublist(history.length - 5) : history;
    return (recent.last - recent.first) / (recent.length - 1);
  }

  /// Classifies the current trend as one of:
  /// 'stable' | 'rising' | 'rising_fast' | 'falling' | 'falling_fast'
  ///
  /// Thresholds are per-reading deltas that make physical sense for each
  /// sensor's typical live range (readings arrive every few seconds).
  String getTrend(String key) {
    final rate = getTrendRate(key); // single computation, reused below
    if (rate == 0.0) return 'stable';

    double stableThreshold;
    double fastThreshold;
    switch (key) {
      case 'temp':       stableThreshold = 0.02; fastThreshold = 0.15; break;
      case 'ph':         stableThreshold = 0.01; fastThreshold = 0.08; break;
      case 'do':         stableThreshold = 0.03; fastThreshold = 0.20; break;
      case 'turb':       stableThreshold = 0.50; fastThreshold = 2.00; break;
      case 'waterlevel': stableThreshold = 0.50; fastThreshold = 1.50; break;
      default:           stableThreshold = 0.05; fastThreshold = 0.30;
    }

    if (rate.abs() < stableThreshold) return 'stable';
    if (rate > 0) return rate >= fastThreshold ? 'rising_fast' : 'rising';
    return rate <= -fastThreshold ? 'falling_fast' : 'falling';
  }

  void _initFirebaseListener() async {
    _subscription?.cancel();
    _initialDataLoaded = false;
    _staleTimer?.cancel();
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_hasLiveData && DateTime.now().difference(_lastUpdated) > _staleTimeout) {
        _markStale();
      }
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Resolve tank_id from the user's profile — sensor data lives under
    // tanks/{tank_id}/sensor_readings/latest, not tied directly to uid.
    try {
      final profileDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final profileData = profileDoc.data();
      // Admins do NOT own a tank — never assign one to them.
      if (profileData?['role'] == 'admin') {
        _tankId = null;
        _lastError = 'Admin accounts have no tank.';
        notifyListeners();
        return;
      }
      var tankId = profileData?['tank_id'] as String?;
      // CrayCare is 1 user = 1 tank with tank_id == uid. If the profile has
      // no usable tank_id (missing OR empty string — e.g. legacy accounts
      // created before tank provisioning), fall back to the UID and persist
      // the link so every other service sees it too. This prevents a wrong
      // "No tank assigned" message when the tank doc actually exists.
      if (tankId == null || tankId.isEmpty) {
        tankId = uid;
        try {
          await profileDoc.reference
              .set({'tank_id': uid}, SetOptions(merge: true));
        } catch (e, stack) { debugPrint('[Sensor] hardware init error: $e\n$stack'); }
      }
      _tankId = tankId;
    } catch (e) {
      debugPrint('[SensorService] Failed to resolve tank_id: $e');
      // If the profile read failed, still fall back to uid so the dashboard
      // keeps listening to the expected tank path instead of erroring out.
      _tankId = uid;
    }
    final tankId = _tankId;
    if (tankId == null || tankId.isEmpty) {
      _lastError = 'No tank assigned to this account yet.';
      notifyListeners();
      return;
    }

    _subscription = FirebaseFirestore.instance
        .collection('tanks')
        .doc(tankId)
        .collection('sensor_readings')
        .doc('latest')
        .snapshots()
        .listen(
      (snapshot) {
        _lastError = null;
        if (!snapshot.exists || snapshot.data() == null) return;
        _parseAndUpdate(snapshot.data()!);
      },
      onError: (error) {
        final msg = error.toString();
        // Surface a friendlier message for Firestore permission errors.
        if (msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED')) {
          _lastError = 'Sensor access not configured. Waiting for hardware assignment...';
        } else {
          _lastError = msg;
        }
        debugPrint('[SensorService] Firestore stream error: $error');
        notifyListeners();
      },
    );
  }

  DateTime? _extractTimestamp(Map<String, dynamic> data) {
    final rawTs = data['recorded_at'] ?? data['timestamp'] ?? data['updatedAt'] ?? data['time'];
    if (rawTs == null) return null;
    if (rawTs is Timestamp) return rawTs.toDate();
    if (rawTs is int) {
      if (rawTs < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(rawTs * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(rawTs);
    }
    if (rawTs is double) {
      final intVal = rawTs.toInt();
      if (intVal < 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(intVal * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(intVal);
    }
    if (rawTs is String) {
      return DateTime.tryParse(rawTs);
    }
    return null;
  }

  void _parseAndUpdate(Map<String, dynamic> data) {
    if (!_initialDataLoaded) {
      _initialDataLoaded = true;
    }

    final docTime = _extractTimestamp(data);
    final now = DateTime.now();
    final readingTime = docTime ?? now;
    final age = now.difference(readingTime);

    if (age > _staleTimeout) {
      debugPrint(
          '[SensorService] Data in Firestore is stale (${age.inSeconds}s old). ESP is offline.');
      _markStale(lastSeen: readingTime);
      return;
    }

    _lastUpdated = readingTime;
    _hasLiveData = true;

    // ESP32 advertises how many offline readings are still queued in its
    // LittleFS buffer (store-and-forward backlog) via buffered_entries.
    _bufferedEntries =
        (data['buffered_entries'] as num?)?.toInt() ?? 0;

    // New schema field names (tanks/{tank_id}/sensor_readings/latest):
    // temperature, ph_level, dissolved_oxygen, turbidity, water_level.
    // Legacy camelCase keys kept as a fallback during migration.
    final tempRaw = _toDouble(data['temperature']);
    final turbRaw = _toDouble(data['turbidity']);
    final doRaw = _toDouble(data['dissolved_oxygen'] ?? data['dissolvedOxygen']);
    final phRaw = _toDouble(data['ph_level'] ?? data['phLevel']);
    final wlRaw = _toDouble(data['water_level'] ?? data['waterLevel']);
    final turbAirRaw = data['turbidity_air'] ?? data['turbidityAir'];
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

    _staleTimer?.cancel();
    final remaining = _staleTimeout - age;
    if (remaining.isNegative) {
      _markStale(lastSeen: readingTime);
    } else {
      _staleTimer = Timer(remaining, () => _markStale(lastSeen: readingTime));
      notifyListeners();
    }
  }

  void _markStale({DateTime? lastSeen}) {
    _latest.clear();
    if (lastSeen != null) {
      _lastUpdated = lastSeen;
    }
    _hasLiveData = false;
    // While stale we can't trust the backlog count — the offline banner is
    // the accurate signal. Reset so "Syncing N…" never masks "Offline".
    _bufferedEntries = 0;
    _staleTimer?.cancel();
    notifyListeners();
    debugPrint('[SensorService] Data stale - ESP32 offline (last seen: $_lastUpdated)');
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

  bool hasSensorData(String key) => _latest.containsKey(key);

  bool hasFreshData(String key) =>
      _latest.containsKey(key) &&
      DateTime.now().difference(_lastUpdated) < _staleTimeout;

  double getLatestValue(String key) => _latest[key] ?? 0.0;

  List<double> getData(String key) => _history[key] ?? [];

  final Map<String, List<Map<String, dynamic>>> _dayCache = {};
  final Map<String, DateTime> _dayCachedAt = {};

  // The ESP32 writes a new history entry roughly every 10 minutes
  // (HISTORY_INTERVAL in the firmware). Today's subcollection is still
  // being appended to, so we only trust its cache for a short window -
  // long enough to avoid re-fetching on every rapid filter switch, short
  // enough that a newly-saved reading shows up quickly.
  static const _todayCacheTtl = Duration(seconds: 60);

  static String _dateStrFor(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isToday(String dateStr) => dateStr == _dateStrFor(DateTime.now());

  List<Map<String, dynamic>>? getCachedDay(String dateStr) {
    final cached = _dayCache[dateStr];
    if (cached == null) return null;

    if (_isToday(dateStr)) {
      final cachedAt = _dayCachedAt[dateStr];
      if (cachedAt == null ||
          DateTime.now().difference(cachedAt) > _todayCacheTtl) {
        return null;
      }
    }

    // Past/closed days never change once written, so they can be
    // cached indefinitely (until the app restarts or the cache is
    // explicitly cleared).
    return cached;
  }

  void cacheDay(String dateStr, List<Map<String, dynamic>> records) {
    _dayCache[dateStr] = records;
    _dayCachedAt[dateStr] = DateTime.now();
  }

  void clearHistoryCache() {
    _dayCache.clear();
    _dayCachedAt.clear();
  }

  Future<List<Map<String, dynamic>>> fetchHistoryRange({
    required DateTime start,
    required DateTime end,
  }) async {
    // History now lives under the tank, not the uid directly:
    // tanks/{tank_id}/sensor_readings_history/{dateStr}/{autoId}
    var tankId = _tankId;
    if (tankId == null) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final profileDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        tankId = profileDoc.data()?['tank_id'] as String?;
        _tankId = tankId;
      }
    }

    final days = <String>[];
    for (var d = DateTime(start.year, start.month, start.day);
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      days.add(
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );
    }

    final uncachedDays = <String>[];
    final cachedRecords = <Map<String, dynamic>>[];
    for (final dateStr in days) {
      final cached = getCachedDay(dateStr);
      if (cached != null) {
        cachedRecords.addAll(cached);
      } else {
        uncachedDays.add(dateStr);
      }
    }

    if (uncachedDays.isNotEmpty) {
      // Pass 1: Try reading from local Firestore disk cache (lightning fast, 0ms latency)
      // Path: tanks/{tank_id}/sensor_readings_history/{dateStr}
      final remainingUncached = <String>[];
      final cacheFutures = uncachedDays.map((dateStr) async {
        if (tankId == null) {
          remainingUncached.add(dateStr);
          return <Map<String, dynamic>>[];
        }
        try {
          final snap = await FirebaseFirestore.instance
              .collection('tanks')
              .doc(tankId)
              .collection('sensor_readings_history')
              .doc(dateStr)
              .collection('entries')
              .get(const GetOptions(source: Source.cache));
          if (snap.docs.isNotEmpty) {
            final docs = snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList();
            cacheDay(dateStr, docs);
            return docs;
          }
        } catch (e, stack) { debugPrint('[Sensor] history load error: $e\n$stack'); }
        remainingUncached.add(dateStr);
        return <Map<String, dynamic>>[];
      });

      final cacheResults = await Future.wait(cacheFutures);
      cachedRecords.addAll(cacheResults.expand((r) => r));

      // Pass 2: If online, fetch remaining missing days from server in parallel chunks.
      // Path is scoped to this tank — tanks/{tank_id}/sensor_readings_history/{dateStr}.
      // No extra ownerUid filter needed; the path itself is the ownership scope.
      if (remainingUncached.isNotEmpty && ConnectivityService.instance.isOnline && tankId != null) {
        const chunkSize = 6;
        for (var i = 0; i < remainingUncached.length; i += chunkSize) {
          final chunk = remainingUncached.sublist(
            i,
            i + chunkSize > remainingUncached.length
                ? remainingUncached.length
                : i + chunkSize,
          );
          final serverFutures = chunk.map((dateStr) async {
            try {
              final snap = await FirebaseFirestore.instance
                  .collection('tanks')
                  .doc(tankId)
                  .collection('sensor_readings_history')
                  .doc(dateStr)
                  .collection('entries')
                  .get(const GetOptions(source: Source.serverAndCache));
              final docs = snap.docs.map((doc) {
                final data = doc.data();
                data['id'] = doc.id;
                return data;
              }).toList();
              cacheDay(dateStr, docs);
              return docs;
            } catch (e) {
              debugPrint('[SensorService] fetchHistoryRange error for $dateStr: $e');
              cacheDay(dateStr, []);
              return <Map<String, dynamic>>[];
            }
          });
          final serverResults = await Future.wait(serverFutures);
          cachedRecords.addAll(serverResults.expand((r) => r));
        }
      }
    }

    // Canonical history documents use `recorded_at` (Firestore Timestamp).
    // Keep legacy timestamp aliases readable while sorting all records by the
    // actual capture time rather than treating missing numeric timestamps as 0.
    cachedRecords.sort((a, b) {
      final at = _extractTimestamp(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = _extractTimestamp(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });
    return cachedRecords;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _staleTimer?.cancel();
    super.dispose();
  }
}
