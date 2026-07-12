import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EspService extends ChangeNotifier {
  static final EspService instance = EspService._();
  EspService._();

  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _espSub;

  bool get isEspOnline =>
      DateTime.now().difference(_lastSeen).inSeconds < 30;

  void init() {
    _espSub?.cancel();
    if (FirebaseAuth.instance.currentUser != null) {
      _startListening();
    }
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _espSub?.cancel();
      if (user != null) {
        _startListening();
      } else {
        _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
        notifyListeners();
      }
    });
  }

  void _startListening() {
    _espSub = FirebaseFirestore.instance
        .collection('sensorReadings')
        .doc('latest')
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            _lastSeen = DateTime.now();
            notifyListeners();
          }
        });
  }

  @override
  void dispose() {
    _espSub?.cancel();
    super.dispose();
  }
}
