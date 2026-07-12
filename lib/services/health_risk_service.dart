import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HealthRiskResult {
  final double score;
  final String level;
  final int confidence;
  final String driver;
  final String problem;
  final String action;
  final String source;
  final DateTime timestamp;

  HealthRiskResult({
    required this.score,
    required this.level,
    required this.confidence,
    required this.driver,
    required this.problem,
    required this.action,
    required this.source,
    required this.timestamp,
  });

  factory HealthRiskResult.fromMap(Map<String, dynamic> data) {
    return HealthRiskResult(
      score: (data['score'] as num?)?.toDouble() ?? 0,
      level: data['level'] as String? ?? 'Insufficient',
      confidence: (data['confidence'] as num?)?.toInt() ?? 0,
      driver: data['driver'] as String? ?? 'N/A',
      problem: data['problem'] as String? ?? '',
      action: data['action'] as String? ?? '',
      source: data['source'] as String? ?? '',
      timestamp: data['timestamp'] != null
          ? DateTime.tryParse(data['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
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

  HealthRiskResult? get result => _result;
  bool get loading => _loading;
  bool get hasData => _result != null && _result!.hasData;

  void init() {
    _sub?.cancel();
    _loading = true;
    notifyListeners();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    FirebaseFirestore.instance
        .collection('healthRisk')
        .doc('latest')
        .snapshots()
        .listen((snap) {
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        if (data['uid'] == null || data['uid'] == uid) {
          _result = HealthRiskResult.fromMap(data);
        }
      }
      _loading = false;
      notifyListeners();
    }, onError: (e) {
      debugPrint('[HealthRiskService] Stream error: $e');
      _loading = false;
      notifyListeners();
    });

    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        init();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
