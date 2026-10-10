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

  const WaterQualityAnomalyDetectionResult({
    required this.status,
    required this.isAnomaly,
    required this.anomalyScore,
    required this.source,
    required this.insight,
    required this.recommendation,
    required this.contributors,
    required this.timestamp,
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
  // The scheduled analysis runs every 15 minutes. After three missed runs,
  // the last result must not continue to look like a live assessment.
  bool isFreshAt(DateTime now) {
    if (!hasData) return false;
    final age = now.toUtc().difference(timestamp.toUtc());
    return age >= const Duration(minutes: -5) &&
        age < const Duration(minutes: 45);
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _currentSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _historySub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _legacyHistorySub;
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
    final delay = result.timestamp
        .toUtc()
        .add(const Duration(minutes: 45))
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
    _currentSub?.cancel();
    _historySub?.cancel();
    _legacyHistorySub?.cancel();
    _currentSub = null;
    _historySub = null;
    _legacyHistorySub = null;
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

      _currentSub = collection
          .doc('current')
          .snapshots()
          .listen(
            (snapshot) {
              if (generation != _listenGeneration) return;
              _result = snapshot.exists && snapshot.data() != null
                  ? WaterQualityAnomalyDetectionResult.fromMap(snapshot.data()!)
                  : null;
              _refreshWhenStale();
              _loading = false;
              notifyListeners();
            },
            onError: (Object error) {
              if (generation != _listenGeneration) return;
              debugPrint('[WQAD] Current stream error: $error');
              _loading = false;
              notifyListeners();
            },
          );

      var newHistory = <WaterQualityAnomalyDetectionResult>[];
      var legacyHistory = <WaterQualityAnomalyDetectionResult>[];
      void publishHistory() {
        final byTimestamp = <int, WaterQualityAnomalyDetectionResult>{};
        for (final item in [...newHistory, ...legacyHistory]) {
          byTimestamp[item.timestamp.millisecondsSinceEpoch] = item;
        }
        final combined = byTimestamp.values.toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _history = combined.take(30).toList(growable: false);
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
            onError: (Object error) =>
                debugPrint('[WQAD] History stream error: $error'),
          );
      // Keep already-written hourly records visible during the path transition.
      _legacyHistorySub = collection
          .orderBy('processed_at', descending: true)
          .limit(31)
          .snapshots()
          .listen(
            (snapshot) {
              if (generation != _listenGeneration) return;
              legacyHistory = snapshot.docs
                  .where((doc) => doc.id != 'current')
                  .map(
                    (doc) =>
                        WaterQualityAnomalyDetectionResult.fromMap(doc.data()),
                  )
                  .toList(growable: false);
              publishHistory();
            },
            onError: (Object error) =>
                debugPrint('[WQAD] Legacy history stream error: $error'),
          );
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
    _currentSub?.cancel();
    _historySub?.cancel();
    _legacyHistorySub?.cancel();
    _freshnessTimer?.cancel();
    ConnectivityService.instance.removeOnConnectCallback(_onReconnect);
    _initialized = false;
    super.dispose();
  }
}
