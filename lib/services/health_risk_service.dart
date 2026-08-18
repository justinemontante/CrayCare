import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'connectivity_service.dart';
import '../utils/timestamp_parser.dart';

class HealthRiskResult {
  final String level;
  final int confidence;
  final String driver;
  final String problem;
  final String insight;
  final String action;
  final String source;
  final String driverLabel;
  final double? driverValue;
  final String driverUnit;
  final double? driverMin;
  final double? driverMax;
  final String analysisMode;
  final int samplesAnalyzed;
  final int requiredSamples;
  final DateTime timestamp;

  HealthRiskResult({
    required this.level,
    required this.confidence,
    required this.driver,
    required this.problem,
    required this.insight,
    required this.action,
    required this.source,
    required this.driverLabel,
    required this.driverValue,
    required this.driverUnit,
    required this.driverMin,
    required this.driverMax,
    required this.analysisMode,
    required this.samplesAnalyzed,
    required this.requiredSamples,
    required this.timestamp,
  });

  factory HealthRiskResult.fromMap(Map<String, dynamic> data) {
    return HealthRiskResult(
      level: data['level'] as String? ?? 'Insufficient',
      confidence: (data['confidence'] as num?)?.toInt() ?? 0,
      driver: data['driver'] as String? ?? 'N/A',
      problem: data['problem'] as String? ?? '',
      insight: data['insight'] as String? ?? '',
      action: data['action'] as String? ?? '',
      source: data['source'] as String? ?? '',
      driverLabel: data['driver_label'] as String? ?? (data['driver'] as String? ?? 'N/A'),
      driverValue: (data['driver_value'] as num?)?.toDouble(),
      driverUnit: data['driver_unit'] as String? ?? '',
      driverMin: (data['driver_min'] as num?)?.toDouble(),
      driverMax: (data['driver_max'] as num?)?.toDouble(),
      analysisMode: data['analysis_mode'] as String? ?? 'Water-quality assessment',
      samplesAnalyzed: (data['samples_analyzed'] as num?)?.toInt() ?? 0,
      requiredSamples: (data['required_samples'] as num?)?.toInt() ?? 6,
      timestamp: parseFirestoreDateTime(data['timestamp']) ?? DateTime.now(),
    );
  }

  bool get hasData => level != 'Insufficient';

  Color get color {
    switch (level) {
      case 'Low':
        return const Color(0xFF166534);
      case 'Moderate':
        return const Color(0xFFf59e0b);
      case 'High':
        return const Color(0xFFE63946);
      case 'Critical':
        return const Color(0xFF991b1b);
      default:
        return const Color(0xFF94a3b8);
    }
  }

  Color get lightColor {
    switch (level) {
      case 'Low':
        return const Color(0xFFdcfce7);
      case 'Moderate':
        return const Color(0xFFfef3c7);
      case 'High':
        return const Color(0xFFffe4e6);
      case 'Critical':
        return const Color(0xFFfecaca);
      default:
        return const Color(0xFFf1f5f9);
    }
  }
}

class HealthRiskService extends ChangeNotifier {
  static final HealthRiskService instance = HealthRiskService._();
  HealthRiskService._();

  HealthRiskResult? _result;
  bool _loading = true;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _historySub;
  List<HealthRiskResult> _history = [];

  HealthRiskResult? get result => _result;
  bool get loading => _loading;
  bool get hasData => _result != null && _result!.hasData;

  /// Hourly assessment history (newest first), including the current one.
  /// The ML function writes one doc per assessment into the same
  /// ml_predictions collection, keyed by a sortable UTC timestamp.
  List<HealthRiskResult> get history => List.unmodifiable(_history);

  void init() {
    _sub?.cancel();
    _historySub?.cancel();
    _loading = true;
    notifyListeners();

    if (FirebaseAuth.instance.currentUser != null) {
      _startListening();
    }

    FirebaseAuth.instance.authStateChanges().listen((user) {
      _sub?.cancel();
      _historySub?.cancel();
      if (user != null) {
        _startListening();
      } else {
        _result = null;
        _history = [];
        _loading = true;
        notifyListeners();
      }
    });
    ConnectivityService.instance.addOnConnectCallback(_onReconnect);
  }

  void _onReconnect() {
    debugPrint('[HealthRiskService] Internet reconnected — refreshing listener');
    if (FirebaseAuth.instance.currentUser != null) {
      _startListening();
    }
  }

  void _startListening() async {
    _sub?.cancel();
    _historySub?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _result = null;
      _history = [];
      _loading = false;
      notifyListeners();
      return;
    }

    try {
      final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final tankId = profile.data()?['tank_id'] as String? ?? uid;
      _sub = FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .collection('ml_predictions')
          .doc('current')
          .snapshots()
          .listen((snap) {
        if (snap.exists && snap.data() != null) {
          final data = snap.data()!;
          _result = HealthRiskResult.fromMap(data);
        } else {
          _result = null;
        }
        _loading = false;
        notifyListeners();
      }, onError: (e) {
        debugPrint('[HealthRiskService] Stream error: $e');
        _loading = false;
        notifyListeners();
      });

      // Hourly assessment history (newest first). The ML function writes one
      // doc per assessment into the same ml_predictions collection, keyed by
      // a sortable UTC timestamp.
      _historySub = FirebaseFirestore.instance
          .collection('tanks')
          .doc(tankId)
          .collection('ml_predictions')
          .orderBy('ts_epoch', descending: true)
          // Fetch one extra because `current` is part of the collection but is
          // removed below; consumers still receive up to 30 history entries.
          .limit(31)
          .snapshots()
          .listen((snap) {
        final list = <HealthRiskResult>[];
        for (final doc in snap.docs) {
          // `current` mirrors the newest timestamped history document. Keeping
          // it in this query duplicates an assessment in charts and exports.
          if (doc.id == 'current') continue;
          final data = doc.data();
          if (data.isEmpty) continue;
          list.add(HealthRiskResult.fromMap(data));
        }
        _history = list;
        notifyListeners();
      }, onError: (e) {
        debugPrint('[HealthRiskService] history stream error: $e');
      });
    } catch (e) {
      debugPrint('[HealthRiskService] Listener setup error: $e');
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _historySub?.cancel();
    super.dispose();
  }
}
