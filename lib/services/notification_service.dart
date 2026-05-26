import 'package:flutter/foundation.dart';
import '../models/notification_item.dart';
import 'sensor_service.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._() {
    _seedDummyData();
    SensorService.instance.addListener(_onSensorUpdate);
  }

  final List<NotificationItem> _notifications = [];
  final Map<String, String> _previousZones = {};

  void _seedDummyData() {
    final now = DateTime.now();
    _notifications.addAll([
      NotificationItem(
        id: 'dummy_critical_1', type: NotificationType.critical,
        title: 'Critical: Low DO Level',
        message: 'Dissolved oxygen dropped to 2.8 mg/L. Aerator activated automatically.',
        timestamp: now.subtract(const Duration(minutes: 15)),
      ),
      NotificationItem(
        id: 'dummy_warning_1', type: NotificationType.warning,
        title: 'Turbidity Warning',
        message: 'Turbidity level at 48 NTU. Filtration may be needed.',
        timestamp: now.subtract(const Duration(hours: 1)),
      ),
      NotificationItem(
        id: 'dummy_operational_1', type: NotificationType.operational,
        title: 'Feeder Dispensed',
        message: 'Auto Feeder dispensed 44.1g feed (scheduled)',
        timestamp: now.subtract(const Duration(hours: 2)),
      ),
      NotificationItem(
        id: 'dummy_reminder_1', type: NotificationType.reminder,
        title: 'Sampling Due',
        message: 'Weekly sampling for weight and length check is due tomorrow.',
        timestamp: now.subtract(const Duration(hours: 5)), unread: false,
      ),
      NotificationItem(
        id: 'dummy_warning_2', type: NotificationType.warning,
        title: 'Temperature Shift',
        message: 'Water temperature rising above 30°C. Monitor closely.',
        timestamp: now.subtract(const Duration(days: 1)), unread: false,
      ),
      NotificationItem(
        id: 'dummy_operational_2', type: NotificationType.operational,
        title: 'Aerator Mode Changed',
        message: 'Aerator 1 set to AUTO mode.',
        timestamp: now.subtract(const Duration(days: 1, hours: 3)), unread: false,
      ),
    ]);
  }

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => n.unread).length;
  int get criticalCount => _notifications.where((n) => n.type == NotificationType.critical).length;

  void _onSensorUpdate() {
    final ss = SensorService.instance;

    for (final key in SensorService.sensorKeys) {
      final zone = ss.getZone(key);
      final prev = _previousZones[key];

      if (prev != null && prev != zone) {
        if (zone == 'DANGER') {
          _add(NotificationItem(
            id: '${key}_danger_${DateTime.now().millisecondsSinceEpoch}',
            type: NotificationType.critical,
            title: _sensorLabel(key),
            message: '$_sensorLabel(key) is in DANGER zone! Current: ${ss.getLatestValue(key).toStringAsFixed(1)}',
            timestamp: DateTime.now(),
          ));
        } else if (zone == 'WARNING') {
          _add(NotificationItem(
            id: '${key}_warning_${DateTime.now().millisecondsSinceEpoch}',
            type: NotificationType.warning,
            title: '$_sensorLabel(key) Warning',
            message: '$_sensorLabel(key) has shifted to WARNING zone. Current: ${ss.getLatestValue(key).toStringAsFixed(1)}',
            timestamp: DateTime.now(),
          ));
        }
      }

      _previousZones[key] = zone;
    }

    if (ss.isEspOnline) {
      _addOnce('esp_online', NotificationItem(
        id: 'esp_online',
        type: NotificationType.operational,
        title: 'ESP32 Reconnected',
        message: 'Sensor unit is back online and transmitting data.',
        timestamp: DateTime.now(),
      ));
    }
  }

  void _add(NotificationItem item) {
    _notifications.insert(0, item);
    if (_notifications.length > 50) _notifications.removeLast();
    notifyListeners();
  }

  void _addOnce(String id, NotificationItem item) {
    final exists = _notifications.any((n) => n.id == id);
    if (!exists) {
      _add(item);
    }
  }

  String _sensorLabel(String key) {
    switch (key) {
      case 'temp': return 'Temperature';
      case 'ph': return 'pH Level';
      case 'do': return 'Dissolved Oxygen';
      case 'turb': return 'Turbidity';
      case 'waterlevel': return 'Water Level';
      default: return key;
    }
  }

  void markAllRead() {
    for (final n in _notifications) { n.unread = false; }
    notifyListeners();
  }

  void markRead(NotificationItem item) {
    item.unread = false;
    notifyListeners();
  }

  @override
  void dispose() {
    SensorService.instance.removeListener(_onSensorUpdate);
    super.dispose();
  }
}
