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
  final String status;
  final bool isAnomaly;
  final double anomalyScore;
  final String source;
  final String modelAlgorithm;
  final String modelVersion;
  final String trainingDataOrigin;
  final String trainingLabelOrigin;
  final int modelFeatureCount;
  final int analysisWindowMinutes;
  final String driver;
  final String driverLabel;
  final double? driverValue;
  final String driverUnit;
  final String insight;
  final String recommendation;
  final List<Map<String, dynamic>> contributors;
  final DateTime timestamp;

  const WaterQualityAnomalyDetectionResult({
    required this.status,
    required this.isAnomaly,
    required this.anomalyScore,
    required this.source,
    required this.modelAlgorithm,
    required this.modelVersion,
    required this.trainingDataOrigin,
    required this.trainingLabelOrigin,
    required this.modelFeatureCount,
    required this.analysisWindowMinutes,
    required this.driver,
    required this.driverLabel,
    required this.driverValue,
    required this.driverUnit,
    required this.insight,
    required this.recommendation,
    required this.contributors,
    required this.timestamp,
  });

  factory WaterQualityAnomalyDetectionResult.fromMap(
    Map<String, dynamic> data,
  ) {
    final rawContributors = data['contributors'];
    return WaterQualityAnomalyDetectionResult(
      status: normalizeWaterQualityAnomalyStatus(data['status']),
      isAnomaly: data['is_anomaly'] as bool? ?? false,
      anomalyScore: (data['anomaly_score'] as num?)?.toDouble() ?? 0,
      source: data['source'] as String? ?? 'WQAD model',
      modelAlgorithm: data['model_algorithm'] as String? ?? 'Unknown',
      modelVersion: data['model_version'] as String? ?? '',
      trainingDataOrigin: data['training_data_origin'] as String? ?? 'unknown',
      trainingLabelOrigin:
          data['training_label_origin'] as String? ?? 'none_unsupervised',
      modelFeatureCount: (data['model_feature_count'] as num?)?.toInt() ?? 0,
      analysisWindowMinutes:
          (data['analysis_window_minutes'] as num?)?.toInt() ?? 120,
      driver: data['driver'] as String? ?? 'N/A',
      driverLabel:
          data['driver_label'] as String? ??
          (data['driver'] as String? ?? 'Combined water pattern'),
      driverValue: (data['driver_value'] as num?)?.toDouble(),
      driverUnit: data['driver_unit'] as String? ?? '',
      insight: data['insight'] as String? ?? '',
      recommendation:
          data['recommendation'] as String? ??
          'Verify the readings and inspect the tank.',
      contributors: rawContributors is List
          ? rawContributors
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : const [],
      timestamp:
          parsePredictionTimestamp(data['timestamp']) ?? DateTime.now().toUtc(),
    );
  }

  bool get hasData => status != 'Insufficient';
  bool get usesPrototypeData => trainingDataOrigin.contains('synthetic');

  String get modelBasis {
    if (!hasData) return 'Insufficient Data';
    if (modelAlgorithm == 'IsolationForest') return 'Isolation Forest ML';
    return 'Unsupervised ML';
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

  WaterQualityAnomalyDetectionResult? get result => _result;
  List<WaterQualityAnomalyDetectionResult> get history =>
      List.unmodifiable(_history);
  bool get loading => _loading;
  bool get hasData => _result?.hasData ?? false;

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
    _currentSub?.cancel();
    _historySub?.cancel();
    _currentSub = null;
    _historySub = null;
    if (user == null) {
      _result = null;
      _history = [];
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
      if (profileData?['role'] == 'admin') {
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
      if (generation != _listenGeneration) return;

      _currentSub = collection.doc('current').snapshots().listen(
        (snapshot) {
          if (generation != _listenGeneration) return;
          _result = snapshot.exists && snapshot.data() != null
              ? WaterQualityAnomalyDetectionResult.fromMap(snapshot.data()!)
              : null;
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

      _historySub = collection
          .orderBy('ts_epoch', descending: true)
          .limit(31)
          .snapshots()
          .listen(
            (snapshot) {
              if (generation != _listenGeneration) return;
              _history = snapshot.docs
                  .where((doc) => doc.id != 'current' && doc.data().isNotEmpty)
                  .take(30)
                  .map(
                    (doc) => WaterQualityAnomalyDetectionResult.fromMap(
                      doc.data(),
                    ),
                  )
                  .toList(growable: false);
              notifyListeners();
            },
            onError: (Object error) =>
                debugPrint('[WQAD] History stream error: $error'),
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
    ConnectivityService.instance.removeOnConnectCallback(_onReconnect);
    _initialized = false;
    super.dispose();
  }
}
