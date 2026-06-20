import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';

class MlService extends ChangeNotifier {
  static final MlService instance = MlService._();
  MlService._();

  Map<String, dynamic>? _latestPrediction;
  bool _loading = true;
  String? _error;
  StreamSubscription<DatabaseEvent>? _sub;

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
    _sub = FirebaseDatabase.instance
        .ref('ml_predictions/latest')
        .onValue
        .listen(_onPredictionUpdate, onError: (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    });
  }

  void _onPredictionUpdate(DatabaseEvent event) {
    if (!event.snapshot.exists || event.snapshot.value == null) {
      _latestPrediction = null;
      _loading = false;
      _error = null;
      notifyListeners();
      return;
    }
    try {
      final raw = event.snapshot.value as Map<Object?, Object?>;
      _latestPrediction =
          raw.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
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
