import 'package:flutter/foundation.dart';
import 'sensor_service.dart';
import '../models/notification_item.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final List<NotificationItem> _notifications = [];
  final Map<String, String> _previousZones = {};
  final Map<String, bool> _previousOnline = {};
  int _idCounter = 0;
  bool _initialized = false;

  static const _sensorLabels = {
    'temp': 'Water Temperature',
    'ph': 'pH Level',
    'do': 'Dissolved Oxygen',
    'turb': 'Turbidity',
    'waterlevel': 'Water Level',
  };

  static const _sensorUnits = {
    'temp': '\u00B0C',
    'ph': '',
    'do': 'mg/L',
    'turb': 'NTU',
    'waterlevel': 'cm',
  };

  List<NotificationItem> get notifications =>
      List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => n.unread).length;
  int get criticalCount =>
      _notifications.where((n) => n.type == 'critical').length;

  List<NotificationItem> get todayNotifications =>
      _notifications.where((n) => _isToday(n.timestamp)).toList();

  int get todayCount => todayNotifications.length;
  int get reminderCount =>
      _notifications.where((n) => n.type == 'reminder').length;

  void init() {
    if (_initialized) return;
    _initialized = true;
    SensorService.instance.addListener(_onSensorUpdate);
    _initPreviousStates();
  }

  void _initPreviousStates() {
    for (final key in SensorService.sensorKeys) {
      final zone = SensorService.instance.getZone(key);
      if (zone == 'CRITICAL') {
        _previousZones[key] = 'CRITICAL';
      }
    }
  }

  void _onSensorUpdate() {
    final now = DateTime.now();

    for (final key in SensorService.sensorKeys) {
      final zone = SensorService.instance.getZone(key);
      final prevZone = _previousZones[key];
      final value = SensorService.instance.getLatestValue(key);
      final label = _sensorLabels[key] ?? key;
      final unit = _sensorUnits[key] ?? '';

      if (prevZone != null && zone == 'CRITICAL' && prevZone != 'CRITICAL') {
        _addNotification(
          type: 'critical',
          title: 'Critical: $label',
          message: unit.isNotEmpty
              ? '$label dropped to ${value.toStringAsFixed(1)} $unit.'
              : '$label is at ${value.toStringAsFixed(1)}.',
          timestamp: now,
        );
      } else if (
        prevZone != null && zone != 'CRITICAL' && prevZone == 'CRITICAL'
      ) {
        _addNotification(
          type: 'operational',
          title: '$label Normalized',
          message: unit.isNotEmpty
              ? '$label returned to optimal range (${value.toStringAsFixed(1)} $unit).'
              : '$label returned to optimal range (${value.toStringAsFixed(1)}).',
          timestamp: now,
        );
      }

      _previousZones[key] = zone;
    }

    final isOnline = SensorService.instance.isEspOnline;
    final wasOnline = _previousOnline['esp'] ?? true;
    if (wasOnline && !isOnline) {
      _addNotification(
        type: 'warning',
        title: 'ESP32 Disconnected',
        message: 'Connection to monitoring device lost. Check device connectivity.',
        timestamp: now,
      );
    } else if (!wasOnline && isOnline) {
      _addNotification(
        type: 'operational',
        title: 'ESP32 Reconnected',
        message: 'Monitoring device is back online.',
        timestamp: now,
      );
    }
    _previousOnline['esp'] = isOnline;
  }

  void _addNotification({
    required String type,
    required String title,
    required String message,
    required DateTime timestamp,
  }) {
    _idCounter++;
    _notifications.insert(
      0,
      NotificationItem(
        id: 'notif_$_idCounter',
        type: type,
        title: title,
        message: message,
        timestamp: timestamp,
        unread: true,
      ),
    );
    notifyListeners();
  }

  void markAllRead() {
    for (final n in _notifications) {
      n.unread = false;
    }
    notifyListeners();
  }

  void markAsRead(String id) {
    for (final n in _notifications) {
      if (n.id == id) {
        n.unread = false;
        notifyListeners();
        return;
      }
    }
  }

  void clearAll() {
    _notifications.clear();
    notifyListeners();
  }

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.day == now.day &&
        dt.month == now.month &&
        dt.year == now.year;
  }

  @override
  void dispose() {
    SensorService.instance.removeListener(_onSensorUpdate);
    super.dispose();
  }
}
