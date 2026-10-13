import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/prediction_timestamp.dart';
import 'connectivity_service.dart';

String normalizeWaterQualityAnomalyStatus(Object? value) {
  switch (value?.toString().trim().toLowerCase()) {
    case 'normal':
      return 'Normal';
    case 'unusual':
    case 'anomaly':
      return 'Unusual';
    default:
      return 'Insufficient';
  }
}

class WaterQualityAnomalyDetectionResult {
  static const Map<String, String> _sensorLabels = {
    'temp': 'Temperature',
    'pH': 'pH Level',
    'DO': 'Dissolved Oxygen',
    'turbidity': 'Turbidity',
    'waterLevel': 'Water Level',
  };
  static const Map<String, String> _sensorUnits = {
    'temp': '°C',
    'pH': '',
    'DO': 'mg/L',
    'turbidity': 'NTU',
    'waterLevel': 'cm',
  };

  final String status;
  final bool isAnomaly;
  final double anomalyScore;
  final String source;
  final String insight;
  final String recommendation;
  final List<Map<String, dynamic>> contributors;
  final DateTime timestamp;
  final DateTime? sourceRecordedAt;

  const WaterQualityAnomalyDetectionResult({
    required this.status,
    required this.isAnomaly,
    required this.anomalyScore,
    required this.source,
    required this.insight,
    required this.recommendation,
    required this.contributors,
    required this.timestamp,
    this.sourceRecordedAt,
  });

  factory WaterQualityAnomalyDetectionResult.fromMap(
    Map<String, dynamic> data,
  ) {
    final rawContributors = data['contributors'];
    final rawPrimaryDriver = data['primary_driver'];
    final contributors = rawContributors is List
        ? rawContributors
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    if (contributors.isEmpty && rawPrimaryDriver is Map) {
      contributors.add(Map<String, dynamic>.from(rawPrimaryDriver));
    }
    // Read old flat-only records during the schema transition. New Cloud
    // Function writes persist only the compact contributors array.
    if (contributors.isEmpty && data['driver'] is String) {
      final oldCode = data['driver'] as String;
      if (oldCode != 'N/A') {
        contributors.add({
          'sensor': oldCode,
          'value': data['driver_value'],
          'direction': 'stable',
          'contribution_score': 0,
        });
      }
    }
    final parsedTimestamp =
        parsePredictionTimestamp(data['processed_at']) ??
        parsePredictionTimestamp(data['timestamp']) ??
        parsePredictionTimestamp(data['ts_epoch']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return WaterQualityAnomalyDetectionResult(
      status: normalizeWaterQualityAnomalyStatus(data['status']),
      isAnomaly: data['is_anomaly'] as bool? ?? false,
      anomalyScore: (data['anomaly_score'] as num?)?.toDouble() ?? 0,
      source: data['source'] as String? ?? 'WQAD model',
      insight: data['insight'] as String? ?? '',
      recommendation:
          data['recommendation'] as String? ??
          'Verify the readings and inspect the tank.',
      contributors: List.unmodifiable(contributors),
      timestamp: parsedTimestamp,
      sourceRecordedAt: parsePredictionTimestamp(data['source_recorded_at']),
    );
  }

  static String sensorLabelFor(Object? sensor) =>
      _sensorLabels[sensor?.toString()] ?? sensor?.toString() ?? 'Sensor';

  static String sensorUnitFor(Object? sensor) =>
      _sensorUnits[sensor?.toString()] ?? '';

  Map<String, dynamic>? get primaryContributor =>
      contributors.isEmpty ? null : contributors.first;

  String get driver => primaryContributor?['sensor']?.toString() ?? 'overall';
  String get driverLabel =>
      driver == 'overall' ? 'Combined water pattern' : sensorLabelFor(driver);
  double? get driverValue => (primaryContributor?['value'] as num?)?.toDouble();
  String get driverUnit => sensorUnitFor(driver);

  bool get hasData => status != 'Insufficient';
  // An event-triggered result cannot remain live after its source goes stale.
  DateTime get freshnessAnchor => sourceRecordedAt ?? timestamp;

  bool isFreshAt(DateTime now) {
    if (!hasData) return false;
    final age = now.toUtc().difference(freshnessAnchor.toUtc());
    return age >= const Duration(minutes: -5) &&
        age < const Duration(minutes: 20);
  }

  bool get isCurrent => isFreshAt(DateTime.now());

  String get modelBasis {
    if (!hasData) return 'Insufficient Data';
    return 'Isolation Forest ML';
  }

  Color get color {
    if (!hasData) return const Color(0xFF94A3B8);
    if (!isAnomaly) return const Color(0xFF15847B);
    return anomalyScore >= 99
        ? const Color(0xFFB42318)
        : const Color(0xFFF59E0B);
  }

  Color get lightColor {
    if (!hasData) return const Color(0xFFF1F5F9);
    if (!isAnomaly) return const Color(0xFFE7F7F5);
    return anomalyScore >= 99
        ? const Color(0xFFFFE7E5)
        : const Color(0xFFFFF5D9);
  }
}

List<WaterQualityAnomalyDetectionResult> mergeWaterQualityAnomalyHistory(
  Iterable<WaterQualityAnomalyDetectionResult> newHistory,
  Iterable<WaterQualityAnomalyDetectionResult> legacyHistory, {
  int limit = 30,
}) {
  final byTimestamp = <int, WaterQualityAnomalyDetectionResult>{};
  for (final item in legacyHistory) {
    byTimestamp[item.timestamp.millisecondsSinceEpoch] = item;
  }
  // Prefer the dedicated history collection if a legacy copy has the same
  // processing timestamp.
  for (final item in newHistory) {
    byTimestamp[item.timestamp.millisecondsSinceEpoch] = item;
  }
  final combined = byTimestamp.values.toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return combined.take(limit).toList(growable: false);
}

class WaterQualityAnomalyDetectionService extends ChangeNotifier {
  static final WaterQualityAnomalyDetectionService instance =
      WaterQualityAnomalyDetectionService._();
  WaterQualityAnomalyDetectionService._();

  WaterQualityAnomalyDetectionResult? _result;
  List<WaterQualityAnomalyDetectionResult> _history = [];
  bool _loading = true;
  bool _initialized = false;
  int _listenGeneration = 0;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _historySub;
  Timer? _freshnessTimer;

  WaterQualityAnomalyDetectionResult? get result => _result;
  List<WaterQualityAnomalyDetectionResult> get history =>
      List.unmodifiable(_history);
  bool get loading => _loading;
  bool get hasData => _result?.isCurrent ?? false;

  void _refreshWhenStale() {
    _freshnessTimer?.cancel();
    final result = _result;
    if (result == null || !result.isCurrent) return;
    final delay = result.freshnessAnchor
        .toUtc()
        .add(const Duration(minutes: 20))
        .difference(DateTime.now().toUtc());
    if (delay > Duration.zero) {
      _freshnessTimer = Timer(
        delay + const Duration(seconds: 1),
        notifyListeners,
      );
    }
  }

  void init() {
    if (_initialized) return;
    _initialized = true;
    _loading = true;
    notifyListeners();
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_restartForUser);
    ConnectivityService.instance.addOnConnectCallback(_onReconnect);
  }

  void _restartForUser(User? user) {
    final generation = ++_listenGeneration;
    _freshnessTimer?.cancel();
    _historySub?.cancel();
    _historySub = null;
    _result = null;
    _history = [];
    if (user == null) {
      _loading = true;
      notifyListeners();
      return;
    }
    _loading = true;
    notifyListeners();
    unawaited(_startListening(user.uid, generation));
  }

  void _onReconnect() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) _restartForUser(user);
  }

  Future<void> _startListening(String uid, int generation) async {
    try {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (generation != _listenGeneration ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      final profileData = profile.data();
      if (profileData?['role']?.toString().trim().toLowerCase() == 'admin') {
        _result = null;
        _history = [];
        _loading = false;
        notifyListeners();
        return;
      }
      final tankId = uid;
      final collection = FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .collection('water_quality_anomaly_detections');
      final historyCollection = FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .collection('water_quality_anomaly_detection_history');
      if (generation != _listenGeneration) return;

      var newHistory = <WaterQualityAnomalyDetectionResult>[];
      var legacyHistory = <WaterQualityAnomalyDetectionResult>[];
      void publishHistory() {
        _history = mergeWaterQualityAnomalyHistory(newHistory, legacyHistory);
        _result = _history.isEmpty ? null : _history.first;
        _refreshWhenStale();
        _loading = false;
        notifyListeners();
      }

      _historySub = historyCollection
          .orderBy('processed_at', descending: true)
          .limit(30)
          .snapshots()
          .listen(
            (snapshot) {
              if (generation != _listenGeneration) return;
              newHistory = snapshot.docs
                  .where((doc) => doc.data().isNotEmpty)
                  .map(
                    (doc) =>
                        WaterQualityAnomalyDetectionResult.fromMap(doc.data()),
                  )
                  .toList(growable: false);
              publishHistory();
            },
            onError: (Object error) {
              if (generation != _listenGeneration) return;
              debugPrint('[WQAD] History stream error: $error');
              _loading = false;
              notifyListeners();
            },
          );
      // Keep already-written timestamped records from the former collection
      // visible during transition. That collection is legacy-only, so read it
      // once rather than maintaining a second live listener. Its old `current`
      // document is deliberately ignored.
      final legacySnapshot = await collection
          .orderBy('processed_at', descending: true)
          .limit(31)
          .get();
      if (generation != _listenGeneration) return;
      legacyHistory = legacySnapshot.docs
          .where((doc) => doc.id != 'current')
          .map((doc) => WaterQualityAnomalyDetectionResult.fromMap(doc.data()))
          .toList(growable: false);
      publishHistory();
    } catch (error) {
      if (generation != _listenGeneration) return;
      debugPrint('[WQAD] Listener setup error: $error');
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _listenGeneration++;
    _authSub?.cancel();
    _historySub?.cancel();
    _freshnessTimer?.cancel();
    ConnectivityService.instance.removeOnConnectCallback(_onReconnect);
    _initialized = false;
    super.dispose();
  }
}
