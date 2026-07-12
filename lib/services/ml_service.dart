import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MlService extends ChangeNotifier {
  static final MlService instance = MlService._();
  MlService._();

  Map<String, dynamic>? _latestPrediction;
  bool _loading = true;
  String? _error;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  Map<String, dynamic>? get latestPrediction => _latestPrediction;
  bool get loading => _loading;
  String? get error => _error;

  bool get hasData => _latestPrediction != null;

  bool get hasFreshData {
    if (_latestPrediction == null) return false;
    final ts = _latestPrediction!['timestamp'];
    if (ts is! num) return false;
    final age = DateTime.now().millisecondsSinceEpoch - ts.toInt();
    return age < 2 * 60 * 1000;
  }

  void init() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('mlPredictions')
        .doc('latest')
        .snapshots()
        .listen(_onPredictionUpdate, onError: (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    });
  }

  void _onPredictionUpdate(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists || snapshot.data() == null) {
      _latestPrediction = null;
      _loading = false;
      _error = null;
      notifyListeners();
      return;
    }
    try {
      _latestPrediction = snapshot.data()!;
      _error = null;
      _loading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to parse ML prediction: $e';
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
