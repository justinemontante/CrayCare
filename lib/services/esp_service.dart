import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EspService extends ChangeNotifier {
  static final EspService instance = EspService._();
  EspService._();

  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _espSub;

  bool get isEspOnline =>
      DateTime.now().difference(_lastSeen).inSeconds < 30;

  void init() {
    _espSub?.cancel();
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
