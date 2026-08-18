import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'connectivity_service.dart';
import '../utils/timestamp_parser.dart';

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
    // Current predictions use ISO 8601, while older/admin-written documents
    // can contain Firestore Timestamp or epoch-millisecond values.
    final parsed = parseFirestoreDateTime(ts);
    if (parsed == null) return false;
    final age = DateTime.now().toUtc().difference(parsed.toUtc());
    // A future timestamp (bad device/admin clock) must not remain "fresh"
    // until wall time catches up with it.
    return !age.isNegative && age < const Duration(minutes: 2);
  }

  void init() {
    _sub?.cancel();
    if (FirebaseAuth.instance.currentUser != null) {
      _startListening();
    }
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _sub?.cancel();
      if (user != null) {
        _startListening();
      } else {
        _latestPrediction = null;
        _loading = true;
        _error = null;
        notifyListeners();
      }
    });
    ConnectivityService.instance.addOnConnectCallback(_onReconnect);
  }

  void _onReconnect() {
    debugPrint('[MlService] Internet reconnected — refreshing listener');
    if (FirebaseAuth.instance.currentUser != null) {
      _startListening();
    }
  }

  void _startListening() async {
    _sub?.cancel();
    _loading = true;
    _error = null;
    notifyListeners();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _latestPrediction = null;
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
          .listen(_onPredictionUpdate, onError: (e) {
        _error = e.toString();
        _loading = false;
        notifyListeners();
      });
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
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
