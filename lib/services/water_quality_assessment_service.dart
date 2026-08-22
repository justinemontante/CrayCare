import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'connectivity_service.dart';
import '../utils/prediction_timestamp.dart';

String normalizeWaterQualityAssessmentLevel(Object? value) {
  switch (value?.toString().trim().toLowerCase()) {
    case 'good':
    case 'low':
      return 'Good';
    case 'moderate':
      return 'Moderate';
    case 'poor':
    case 'high':
      return 'Poor';
    case 'critical':
      return 'Critical';
    default:
      return 'Insufficient';
  }
}

class WaterQualityAssessmentResult {
  final String level;
  final String modelLevel;
  final String ruleLevel;
  final bool safetyOverride;
  final int confidence;
  final String driver;
  final String problem;
  final String insight;
  final String action;
  final String driverLabel;
  final double? driverValue;
  final String driverUnit;
  final double? driverMin;
  final double? driverMax;
  final DateTime timestamp;

  WaterQualityAssessmentResult({
    required this.level,
    required this.modelLevel,
    required this.ruleLevel,
    required this.safetyOverride,
    required this.confidence,
    required this.driver,
    required this.problem,
    required this.insight,
    required this.action,
    required this.driverLabel,
    required this.driverValue,
    required this.driverUnit,
    required this.driverMin,
    required this.driverMax,
    required this.timestamp,
  });

  factory WaterQualityAssessmentResult.fromMap(Map<String, dynamic> data) {
    final level = normalizeWaterQualityAssessmentLevel(data['level']);
    return WaterQualityAssessmentResult(
      level: level,
      modelLevel: normalizeWaterQualityAssessmentLevel(
        data['model_level'] ?? data['level'],
      ),
      ruleLevel: normalizeWaterQualityAssessmentLevel(
        data['rule_level'] ?? data['level'],
      ),
      safetyOverride: data['safety_override'] as bool? ?? false,
      confidence: (data['confidence'] as num?)?.toInt() ?? 0,
      driver: data['driver'] as String? ?? 'N/A',
      problem: data['problem'] as String? ?? '',
      insight: data['insight'] as String? ?? '',
      action: data['action'] as String? ?? '',
      driverLabel:
          data['driver_label'] as String? ??
          (data['driver'] as String? ?? 'N/A'),
      driverValue: (data['driver_value'] as num?)?.toDouble(),
      driverUnit: data['driver_unit'] as String? ?? '',
      driverMin: (data['driver_min'] as num?)?.toDouble(),
      driverMax: (data['driver_max'] as num?)?.toDouble(),
      timestamp:
          parsePredictionTimestamp(data['timestamp']) ?? DateTime.now().toUtc(),
    );
  }

  bool get hasData => level != 'Insufficient';
  String get assessmentBasis => safetyOverride ? 'Safety Rule' : 'ML Model';

  Color get color {
    switch (level) {
      case 'Good':
        return const Color(0xFF166534);
      case 'Moderate':
        return const Color(0xFFf59e0b);
      case 'Poor':
        return const Color(0xFFE63946);
      case 'Critical':
        return const Color(0xFF991b1b);
      default:
        return const Color(0xFF94a3b8);
    }
  }

  Color get lightColor {
    switch (level) {
      case 'Good':
        return const Color(0xFFdcfce7);
      case 'Moderate':
        return const Color(0xFFfef3c7);
      case 'Poor':
        return const Color(0xFFffe4e6);
      case 'Critical':
        return const Color(0xFFfecaca);
      default:
        return const Color(0xFFf1f5f9);
    }
  }
}

class WaterQualityAssessmentService extends ChangeNotifier {
  static final WaterQualityAssessmentService instance =
      WaterQualityAssessmentService._();
  WaterQualityAssessmentService._();

  WaterQualityAssessmentResult? _result;
  bool _loading = true;
  bool _initialized = false;
  int _listenGeneration = 0;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _historySub;
  List<WaterQualityAssessmentResult> _history = [];

  WaterQualityAssessmentResult? get result => _result;
  bool get loading => _loading;
  bool get hasData => _result != null && _result!.hasData;

  /// Hourly Water Quality Assessment history (newest first). The `current`
  /// document is a live alias and is intentionally excluded from this list so
  /// the same assessment is not shown twice.
  List<WaterQualityAssessmentResult> get history => List.unmodifiable(_history);

  void init() {
    if (_initialized) return;
    _initialized = true;
    _loading = true;
    notifyListeners();

    // authStateChanges emits the current state immediately. Keeping one auth
    // startup path avoids racing a direct currentUser start against that first
    // event and accidentally attaching duplicate Firestore listeners.
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_restartForUser);
    ConnectivityService.instance.addOnConnectCallback(_onReconnect);
  }

  void _restartForUser(User? user) {
    final generation = ++_listenGeneration;
    _sub?.cancel();
    _sub = null;
    _historySub?.cancel();
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
    debugPrint(
      '[WaterQualityAssessmentService] Internet reconnected — refreshing listener',
    );
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) _restartForUser(user);
  }

  Future<void> _startListening(String uid, int generation) async {
    try {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      // Ignore setup work that finished after an auth/reconnect generation was
      // replaced. This prevents a stale account/tank from attaching listeners.
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

      final tankId = profileData?['tank_id'] as String? ?? uid;
      final assessments = FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .collection('machine_learning_assessments');

      // A newer restart may have happened while the profile was resolving.
      if (generation != _listenGeneration) return;
      _sub?.cancel();
      _historySub?.cancel();

      _sub = assessments
          .doc('current')
          .snapshots()
          .listen(
            (snap) {
              if (generation != _listenGeneration) return;
              if (snap.exists && snap.data() != null) {
                _result = WaterQualityAssessmentResult.fromMap(snap.data()!);
              } else {
                _result = null;
              }
              _loading = false;
              notifyListeners();
            },
            onError: (e) {
              if (generation != _listenGeneration) return;
              debugPrint('[WaterQualityAssessmentService] Stream error: $e');
              _loading = false;
              notifyListeners();
            },
          );

      _historySub = assessments
          .orderBy('ts_epoch', descending: true)
          .limit(31)
          .snapshots()
          .listen(
            (snap) {
              if (generation != _listenGeneration) return;
              final list = <WaterQualityAssessmentResult>[];
              for (final doc in snap.docs) {
                if (doc.id == 'current') continue;
                final data = doc.data();
                if (data.isEmpty) continue;
                list.add(WaterQualityAssessmentResult.fromMap(data));
                if (list.length == 30) break;
              }
              _history = list;
              notifyListeners();
            },
            onError: (e) {
              if (generation != _listenGeneration) return;
              debugPrint(
                '[WaterQualityAssessmentService] history stream error: $e',
              );
            },
          );
    } catch (e) {
      if (generation != _listenGeneration) return;
      debugPrint('[WaterQualityAssessmentService] Listener setup error: $e');
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _listenGeneration++;
    _authSub?.cancel();
    _authSub = null;
    _sub?.cancel();
    _historySub?.cancel();
    ConnectivityService.instance.removeOnConnectCallback(_onReconnect);
    _initialized = false;
    super.dispose();
  }
}
