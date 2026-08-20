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
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _resetForAccountChange();
      if (user != null) {
        _initFirebaseListener();
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
  StreamSubscription<User?>? _authSubscription;
  String? _tankId;

  final Map<String, List<double>> _history = {};
  final Map<String, List<DateTime>> _historyTimes = {};
  final Map<String, double> _latest = {};
  bool? _turbidityAir;

  bool get turbidityAir => _turbidityAir ?? false;

  bool _initialDataLoaded = false;

  Timer? _staleTimer;
  Timer? _periodicCheckTimer;
  static const _staleTimeout = Duration(seconds: 10);
  static const _trendWindow = Duration(seconds: 60);
  static const _minTrendSpan = Duration(seconds: 15);
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
  int get bufferedEntries => _bufferedEntries;

  void _resetForAccountChange() {
    _subscription?.cancel();
    _subscription = null;
    _staleTimer?.cancel();
    _periodicCheckTimer?.cancel();
    _tankId = null;
    _history.clear();
    _historyTimes.clear();
    _latest.clear();
    _turbidityAir = null;
    _initialDataLoaded = false;
    _hasLiveData = false;
    _lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);
    _lastError = null;
    _bufferedEntries = 0;
    clearHistoryCache();
    notifyListeners();
  }

  void _resetForTankChange(String? newTankId) {
    if (_tankId == null || _tankId == newTankId) return;
    _history.clear();
    _historyTimes.clear();
    _latest.clear();
    _turbidityAir = null;
    _hasLiveData = false;
    _lastUpdated = DateTime.fromMillisecondsSinceEpoch(0);
    _bufferedEntries = 0;
    clearHistoryCache();
  }

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

  double getTrendRate(String key) {
    final values = _history[key];
    final times = _historyTimes[key];
    if (values == null ||
        times == null ||
        values.length < 4 ||
        times.length != values.length) {
      return 0.0;
    }

    final newest = times.last;
    final cutoff = newest.subtract(_trendWindow);
    var start = 0;
    while (start < times.length - 1 && times[start].isBefore(cutoff)) {
      start++;
    }

    final recentValues = values.sublist(start);
    final recentTimes = times.sublist(start);
    if (recentValues.length < 4) return 0.0;

    final span = recentTimes.last.difference(recentTimes.first);
    if (span < _minTrendSpan) return 0.0;

    final origin = recentTimes.first;
    final xs = recentTimes
        .map((t) => t.difference(origin).inMilliseconds / 60000.0)
        .toList();
    final meanX = xs.reduce((a, b) => a + b) / xs.length;
    final meanY = recentValues.reduce((a, b) => a + b) / recentValues.length;

    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < xs.length; i++) {
      final dx = xs[i] - meanX;
      numerator += dx * (recentValues[i] - meanY);
      denominator += dx * dx;
    }
    if (denominator <= 0) return 0.0;
    return numerator / denominator;
  }

  String getTrend(String key) {
    final rate = getTrendRate(key);

    double stableThreshold;
    double fastThreshold;
    switch (key) {
      case 'temp':
        stableThreshold = 0.10;
        fastThreshold = 0.50;
        break;
      case 'ph':
        stableThreshold = 0.03;
        fastThreshold = 0.15;
        break;
      case 'do':
        stableThreshold = 0.10;
        fastThreshold = 0.50;
        break;
      case 'turb':
        stableThreshold = 1.00;
        fastThreshold = 5.00;
        break;
      case 'waterlevel':
        stableThreshold = 0.50;
        fastThreshold = 2.00;
        break;
      default:
        stableThreshold = 0.10;
        fastThreshold = 0.50;
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
      if (_hasLiveData &&
          DateTime.now().difference(_lastUpdated) > _staleTimeout) {
        _markStale();
      }
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    String? resolvedTankId;
    try {
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final profileData = profileDoc.data();
      if (profileData?['role'] == 'admin') {
        _resetForTankChange(null);
        _tankId = null;
        _lastError = 'Admin accounts have no tank.';
        notifyListeners();
        return;
      }
      resolvedTankId = profileData?['tank_id'] as String?;
      if (resolvedTankId == null || resolvedTankId.isEmpty) {
        resolvedTankId = uid;
        try {
          await profileDoc.reference.set({
            'tank_id': uid,
          }, SetOptions(merge: true));
        } catch (e, stack) {
          debugPrint('[Sensor] hardware init error: $e\n$stack');
        }
      }
    } catch (e) {
      debugPrint('[SensorService] Failed to resolve tank_id: $e');
      resolvedTankId = uid;
    }

    _resetForTankChange(resolvedTankId);
    _tankId = resolvedTankId;
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
            if (msg.contains('permission-denied') ||
                msg.contains('PERMISSION_DENIED')) {
              _lastError =
                  'Sensor access not configured. Waiting for hardware assignment...';
            } else {
              _lastError = msg;
            }
            debugPrint('[SensorService] Firestore stream error: $error');
            notifyListeners();
          },
        );
  }

  DateTime? _extractTimestamp(Map<String, dynamic> data) {
    final rawTs =
        data['recorded_at'] ??
        data['timestamp'] ??
        data['updatedAt'] ??
        data['time'];
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
        '[SensorService] Data in Firestore is stale (${age.inSeconds}s old). ESP is offline.',
      );
      _markStale(lastSeen: readingTime);
      return;
    }

    _lastUpdated = readingTime;
    _hasLiveData = true;
    _bufferedEntries = (data['buffered_entries'] as num?)?.toInt() ?? 0;

    final tempRaw = _toDouble(data['temperature']);
    final turbRaw = _toDouble(data['turbidity']);
    final doRaw = _toDouble(
      data['dissolved_oxygen'] ?? data['dissolvedOxygen'],
    );
    final phRaw = _toDouble(data['ph_level'] ?? data['phLevel']);
    final wlRaw = _toDouble(data['water_level'] ?? data['waterLevel']);
    final turbAirRaw = data['turbidity_air'] ?? data['turbidityAir'];
    _turbidityAir = turbAirRaw is bool ? turbAirRaw : (turbAirRaw == true);

    _updateSensor('temp', tempRaw, readingTime);
    if (_turbidityAir != true) {
      _updateSensor('turb', turbRaw, readingTime);
    } else {
      _latest.remove('turb');
    }
    _updateSensor('do', doRaw, readingTime);
    _updateSensor('ph', phRaw, readingTime);
    _updateSensor('waterlevel', wlRaw, readingTime);

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
    _bufferedEntries = 0;
    _staleTimer?.cancel();
    notifyListeners();
    debugPrint(
      '[SensorService] Data stale - ESP32 offline (last seen: $_lastUpdated)',
    );
  }

  void _updateSensor(String key, double? value, DateTime readingTime) {
    if (value == null || value < 0) {
      _latest.remove(key);
      return;
    }
    if (value == 0 && key != 'turb' && !_latest.containsKey(key)) return;
    if (!_isValidReading(key, value)) return;

    _latest[key] = value;
    _history.putIfAbsent(key, () => []);
    _historyTimes.putIfAbsent(key, () => []);

    final times = _historyTimes[key]!;
    final values = _history[key]!;
    if (times.isNotEmpty && !readingTime.isAfter(times.last)) return;

    values.add(value);
    times.add(readingTime);

    final cutoff = readingTime.subtract(const Duration(seconds: 90));
    while (times.length > 1 && times.first.isBefore(cutoff)) {
      times.removeAt(0);
      values.removeAt(0);
    }
    while (values.length > 60) {
      values.removeAt(0);
      times.removeAt(0);
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

  List<DateTime> getDataTimes(String key) => _historyTimes[key] ?? [];

  final Map<String, List<Map<String, dynamic>>> _dayCache = {};
  final Map<String, DateTime> _dayCachedAt = {};
  static const _todayCacheTtl = Duration(seconds: 60);
  static const _historicalCacheTtl = Duration(hours: 12);

  static String _dateStrFor(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isToday(String dateStr) => dateStr == _dateStrFor(DateTime.now());

  List<Map<String, dynamic>>? getCachedDay(String dateStr) {
    final cached = _dayCache[dateStr];
    final cachedAt = _dayCachedAt[dateStr];
    if (cached == null || cachedAt == null) return null;

    final ttl = _isToday(dateStr) ? _todayCacheTtl : _historicalCacheTtl;
    if (DateTime.now().difference(cachedAt) > ttl) {
      _dayCache.remove(dateStr);
      _dayCachedAt.remove(dateStr);
      return null;
    }
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

  DateTime? _dateFromKey(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  bool _hasUsableDailySummary(Map<String, dynamic> data) {
    if (data['summary_version'] != 1 || data['summary_complete'] != true) {
      return false;
    }
    const averageFields = [
      'temp_avg',
      'pH_avg',
      'DO_avg',
      'turbidity_avg',
      'waterLevel_avg',
    ];
    return averageFields.any((field) => data[field] is num);
  }

  Future<List<Map<String, dynamic>>?> _fetchDailySummaryBackedRange({
    required String tankId,
    required DateTime start,
    required DateTime end,
  }) async {
    final firstDay = DateTime(start.year, start.month, start.day);
    final lastDay = DateTime(end.year, end.month, end.day);
    final days = <DateTime>[];
    for (var day = firstDay; !day.isAfter(lastDay); day = day.add(const Duration(days: 1))) {
      days.add(day);
    }
    if (days.length < 14) return null;

    final historyRef = FirebaseFirestore.instance
        .collection('tanks')
        .doc(tankId)
        .collection('sensor_readings_history');
    final isOnline = ConnectivityService.instance.isOnline;
    final source = isOnline ? Source.serverAndCache : Source.cache;

    QuerySnapshot<Map<String, dynamic>> summarySnap;
    try {
      summarySnap = await historyRef
          .orderBy(FieldPath.documentId)
          .startAt([_dateStrFor(firstDay)])
          .endAt([_dateStrFor(lastDay)])
          .get(GetOptions(source: source));
    } catch (e) {
      debugPrint('[SensorService] Daily summary query unavailable: $e');
      if (!isOnline) return null;
      try {
        summarySnap = await historyRef
            .orderBy(FieldPath.documentId)
            .startAt([_dateStrFor(firstDay)])
            .endAt([_dateStrFor(lastDay)])
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        return null;
      }
    }

    final summaries = <String, Map<String, dynamic>>{};
    for (final doc in summarySnap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      if (!_hasUsableDailySummary(data)) continue;
      final date = _dateFromKey(doc.id);
      if (date == null) continue;
      data['id'] = 'summary:${doc.id}';
      // Noon keeps the synthetic daily point safely inside the selected day.
      data['recorded_at'] = DateTime(date.year, date.month, date.day, 12);
      summaries[doc.id] = data;
    }

    if (summaries.isEmpty) return null;

    // Avoid a fragmented fallback when the deployment has only just started
    // producing summaries. Until at least half the requested days are covered,
    // the optimized raw-entry loader is faster and simpler.
    if (summaries.length * 2 < days.length) return null;

    final records = <Map<String, dynamic>>[...summaries.values];
    final missingDays = days
        .where((day) => !summaries.containsKey(_dateStrFor(day)))
        .toList();

    // Missing days are normally only today or legacy gaps. Load them in small
    // bounded groups, preserving full backward compatibility with old history.
    const missingChunkSize = 12;
    for (var i = 0; i < missingDays.length; i += missingChunkSize) {
      final endIndex = i + missingChunkSize > missingDays.length
          ? missingDays.length
          : i + missingChunkSize;
      final chunk = missingDays.sublist(i, endIndex);
      final futures = chunk.map((day) {
        final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
        return _fetchEntryHistoryRange(
          tankId: tankId,
          start: day,
          end: dayEnd,
        );
      });
      final fallbackResults = await Future.wait(futures);
      records.addAll(fallbackResults.expand((result) => result));
    }

    records.sort((a, b) {
      final at = _extractTimestamp(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = _extractTimestamp(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });
    return records;
  }

  Future<List<Map<String, dynamic>>> _fetchEntryHistoryRange({
    required String tankId,
    required DateTime start,
    required DateTime end,
  }) async {
    final days = <String>[];
    for (
      var d = DateTime(start.year, start.month, start.day);
      !d.isAfter(end);
      d = d.add(const Duration(days: 1))
    ) {
      days.add(_dateStrFor(d));
    }

    final uncachedDays = <String>[];
    final records = <Map<String, dynamic>>[];
    for (final dateStr in days) {
      final cached = getCachedDay(dateStr);
      if (cached != null) {
        records.addAll(cached);
      } else {
        uncachedDays.add(dateStr);
      }
    }

    if (uncachedDays.isNotEmpty) {
      final isOnline = ConnectivityService.instance.isOnline;
      final source = isOnline ? Source.serverAndCache : Source.cache;

      const maxConcurrentDays = 24;
      for (var i = 0; i < uncachedDays.length; i += maxConcurrentDays) {
        final endIndex = i + maxConcurrentDays > uncachedDays.length
            ? uncachedDays.length
            : i + maxConcurrentDays;
        final chunk = uncachedDays.sublist(i, endIndex);

        final futures = chunk.map((dateStr) async {
          try {
            final snap = await FirebaseFirestore.instance
                .collection('tanks')
                .doc(tankId)
                .collection('sensor_readings_history')
                .doc(dateStr)
                .collection('entries')
                .get(GetOptions(source: source));

            final docs = snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList();
            cacheDay(dateStr, docs);
            return docs;
          } catch (e) {
            debugPrint(
              '[SensorService] fetchHistoryRange error for $dateStr: $e',
            );

            if (isOnline) {
              try {
                final cachedSnap = await FirebaseFirestore.instance
                    .collection('tanks')
                    .doc(tankId)
                    .collection('sensor_readings_history')
                    .doc(dateStr)
                    .collection('entries')
                    .get(const GetOptions(source: Source.cache));
                return cachedSnap.docs.map((doc) {
                  final data = doc.data();
                  data['id'] = doc.id;
                  return data;
                }).toList();
              } catch (_) {}
            }
            return <Map<String, dynamic>>[];
          }
        });

        final results = await Future.wait(futures);
        records.addAll(results.expand((result) => result));
      }
    }

    records.sort((a, b) {
      final at = _extractTimestamp(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = _extractTimestamp(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });
    return records;
  }

  Future<List<Map<String, dynamic>>> fetchHistoryRange({
    required DateTime start,
    required DateTime end,
  }) async {
    var tankId = _tankId;
    if (tankId == null) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final profileDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final data = profileDoc.data();
        if (data?['role'] != 'admin') {
          tankId = data?['tank_id'] as String? ?? uid;
          _resetForTankChange(tankId);
          _tankId = tankId;
        }
      }
    }

    if (tankId == null || tankId.isEmpty) return [];

    final firstDay = DateTime(start.year, start.month, start.day);
    final lastDay = DateTime(end.year, end.month, end.day);
    final dayCount = lastDay.difference(firstDay).inDays + 1;

    // 30-day and long custom ranges can use one parent-document summary query
    // instead of dozens/hundreds of 10-minute entry subcollection reads.
    if (dayCount >= 14) {
      final summaryBacked = await _fetchDailySummaryBackedRange(
        tankId: tankId,
        start: start,
        end: end,
      );
      if (summaryBacked != null) return summaryBacked;
    }

    return _fetchEntryHistoryRange(tankId: tankId, start: start, end: end);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _authSubscription?.cancel();
    _staleTimer?.cancel();
    _periodicCheckTimer?.cancel();
    super.dispose();
  }
}
