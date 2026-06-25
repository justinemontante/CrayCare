import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';

class EspService extends ChangeNotifier {
  static final EspService instance = EspService._();
  EspService._();

  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription? _espSub;

  bool get isEspOnline =>
      DateTime.now().difference(_lastSeen).inSeconds < 30;

  void init() {
    _espSub?.cancel();
    _espSub = FirebaseDatabase.instance
        .ref('sensor_readings/latest')
        .onValue
        .listen((e) {
          if (e.snapshot.value != null) {
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
