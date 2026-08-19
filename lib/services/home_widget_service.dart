import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/control_types.dart';
import 'connectivity_service.dart';
import 'feeder_service.dart';
import 'sensor_service.dart';
import 'settings_service.dart';
import 'water_quality_assessment_service.dart';

/// Keeps the Android home-screen widget synchronized with CrayCare's existing
/// realtime services. The native widget reads this compact cached snapshot, so
/// it remains useful even when Android recreates the widget process.
class HomeWidgetService {
  HomeWidgetService._();

  static final HomeWidgetService instance = HomeWidgetService._();
  static const MethodChannel _channel = MethodChannel(
    'com.example.craycare/home_widget',
  );
  static const _manilaOffset = Duration(hours: 8);

  bool _initialized = false;
  Timer? _syncDebounce;
  StreamSubscription<User?>? _authSub;

  void init() {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    SensorService.instance.addListener(_scheduleSync);
    SettingsService.instance.addListener(_scheduleSync);
    WaterQualityAssessmentService.instance.addListener(_scheduleSync);
    FeederService.instance.addListener(_scheduleSync);
    ConnectivityService.instance.addListener(_scheduleSync);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _scheduleSync();
    });
    _scheduleSync();
  }

  void _scheduleSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_writeSnapshot()),
    );
  }

  Future<void> _writeSnapshot() async {
    final user = FirebaseAuth.instance.currentUser;
    final sensors = SensorService.instance;
    final assessment = WaterQualityAssessmentService.instance.result;
    final snapshot = <String, Object>{};

    if (user == null) {
      snapshot.addAll({
        'widget_signed_in': false,
        'widget_online': false,
        'widget_wqa': 'SIGN IN REQUIRED',
        'widget_concern': 'Open CrayCare to sign in',
        'widget_temperature_value': '--',
        'widget_temperature_status': 'UNKNOWN',
        'widget_ph_value': '--',
        'widget_ph_status': 'UNKNOWN',
        'widget_dissolved_oxygen_value': '--',
        'widget_dissolved_oxygen_status': 'UNKNOWN',
        'widget_turbidity_value': '--',
        'widget_turbidity_status': 'UNKNOWN',
        'widget_water_level_value': '--',
        'widget_water_level_status': 'UNKNOWN',
        'widget_next_feed': 'No schedule',
        'widget_updated': '--',
      });
      await _requestNativeUpdate(snapshot);
      return;
    }

    snapshot['widget_signed_in'] = true;
    snapshot['widget_online'] = sensors.isEspOnline;
    snapshot['widget_wqa'] = assessment?.hasData == true
        ? assessment!.level.toUpperCase()
        : 'WAITING';
    snapshot['widget_concern'] = assessment?.hasData == true
        ? _formatConcern(assessment!)
        : 'Collecting assessment history';

    _writeSensor(snapshot, 'temp', 'temperature', '°C', decimals: 1);
    _writeSensor(snapshot, 'ph', 'ph', '', decimals: 2);
    _writeSensor(
      snapshot,
      'do',
      'dissolved_oxygen',
      'mg/L',
      decimals: 1,
    );
    _writeSensor(snapshot, 'turb', 'turbidity', 'NTU', decimals: 1);
    _writeSensor(
      snapshot,
      'waterlevel',
      'water_level',
      'cm',
      decimals: 1,
    );

    final now = DateTime.now().toUtc().add(_manilaOffset);
    final next = nextEnabledFeeding(FeederService.instance.schedules, now);
    snapshot['widget_next_feed'] = next == null
        ? 'No schedule'
        : _formatFeedOccurrence(next.at, now);
    final lastSensorUpdate = sensors.lastUpdated;
    snapshot['widget_updated'] =
        lastSensorUpdate.millisecondsSinceEpoch <= 0
        ? '--'
        : _formatClock(_toManila(lastSensorUpdate), includeSeconds: true);
    await _requestNativeUpdate(snapshot);
  }

  void _writeSensor(
    Map<String, Object> snapshot,
    String sensorKey,
    String storageKey,
    String unit, {
    required int decimals,
  }) {
    final service = SensorService.instance;
    final hasData = service.hasSensorData(sensorKey);
    final value = hasData
        ? service.getLatestValue(sensorKey).toStringAsFixed(decimals)
        : '--';
    snapshot['widget_${storageKey}_value'] = unit.isEmpty || !hasData
        ? value
        : '$value $unit';
    final zone = hasData ? service.getZone(sensorKey) : 'UNKNOWN';
    snapshot['widget_${storageKey}_status'] = zone == 'OPTIMAL'
        ? 'NORMAL'
        : zone;
  }

  String _formatConcern(WaterQualityAssessmentResult assessment) {
    if (assessment.driver == 'overall') return 'All parameters stable';
    const sensorKey = {
      'temp': 'temp',
      'pH': 'ph',
      'DO': 'do',
      'turbidity': 'turb',
      'waterLevel': 'waterlevel',
    };
    final key = sensorKey[assessment.driver];
    if (key == null) return assessment.driverLabel;
    final trend = SensorService.instance.getTrendRate(key);
    final threshold = switch (key) {
      'ph' => 0.01,
      'turb' => 0.10,
      _ => 0.03,
    };
    if (trend.abs() < threshold) return assessment.driverLabel;
    return '${assessment.driverLabel} ${trend < 0 ? 'decreasing' : 'increasing'}';
  }

  String _formatFeedOccurrence(DateTime value, DateTime now) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final valueDate = DateTime(value.year, value.month, value.day);
    final today = DateTime(now.year, now.month, now.day);
    final dayOffset = valueDate.difference(today).inDays;
    final dayLabel = switch (dayOffset) {
      0 => 'Today',
      1 => 'Tomorrow',
      _ => weekdays[value.weekday - 1],
    };
    return '$dayLabel, ${_formatClock(value)}';
  }

  DateTime _toManila(DateTime value) {
    return value.toUtc().add(_manilaOffset);
  }

  String _formatClock(DateTime value, {bool includeSeconds = false}) {
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    final secondsText = includeSeconds ? ':$second' : '';
    return '$hour:$minute$secondsText ${value.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _requestNativeUpdate(Map<String, Object> snapshot) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('updateWidget', snapshot);
    } on MissingPluginException {
      // Expected on hot reload after adding native code; a full restart loads
      // the channel and widget provider.
    } on PlatformException catch (e) {
      debugPrint('[HomeWidgetService] Widget update failed: ${e.message}');
    }
  }

  @visibleForTesting
  void dispose() {
    _syncDebounce?.cancel();
    _authSub?.cancel();
    SensorService.instance.removeListener(_scheduleSync);
    SettingsService.instance.removeListener(_scheduleSync);
    WaterQualityAssessmentService.instance.removeListener(_scheduleSync);
    FeederService.instance.removeListener(_scheduleSync);
    ConnectivityService.instance.removeListener(_scheduleSync);
    _initialized = false;
  }
}
