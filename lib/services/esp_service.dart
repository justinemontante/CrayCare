import 'package:flutter/foundation.dart';
import 'sensor_service.dart';

class EspService extends ChangeNotifier {
  static final EspService instance = EspService._();
  EspService._();

  DateTime _lastSeen = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isEspOnline =>
      DateTime.now().difference(_lastSeen).inSeconds < 30;

  void init() {
    SensorService.instance.addListener(_onSensorUpdate);
  }

  void _onSensorUpdate() {
    _lastSeen = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    SensorService.instance.removeListener(_onSensorUpdate);
    super.dispose();
  }
}
