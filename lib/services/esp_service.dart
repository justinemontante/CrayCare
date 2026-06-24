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
        .ref('sensor_readings/latest/timestamp')
        .onValue
        .listen((e) {
          final val = e.snapshot.value;
          if (val != null) {
            final raw = (val as num).toDouble();
            final ms = raw < 100000000000 ? raw * 1000 : raw;
            _lastSeen = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
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
