import 'package:flutter/foundation.dart';
import 'sensor_service.dart';

class EspService extends ChangeNotifier {
  static final EspService instance = EspService._();
  EspService._();

  bool _initialized = false;

  bool get isEspOnline => SensorService.instance.isEspOnline;

  void init() {
    if (_initialized) return;
    _initialized = true;
    SensorService.instance.addListener(_onSensorUpdate);
  }

  void _onSensorUpdate() {
    notifyListeners();
  }

  @override
  void dispose() {
    SensorService.instance.removeListener(_onSensorUpdate);
    super.dispose();
  }
}
