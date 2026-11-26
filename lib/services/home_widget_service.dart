import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/control_types.dart';
import 'connectivity_service.dart';
import 'feeder_service.dart';
import 'sensor_service.dart';
import 'settings_service.dart';

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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _classificationSub;
  String? _classificationTankId;
  Map<String, dynamic>? _classificationData;

  void init() {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    SensorService.instance.addListener(_scheduleSync);
    SettingsService.instance.addListener(_scheduleSync);
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
    final snapshot = <String, Object>{};

    if (user == null) {
      _clearClassificationListener();
      snapshot.addAll({
        'widget_signed_in': false,
        'widget_online': false,
        'widget_classification_status': 'SIGN IN REQUIRED',
        'widget_classification_insight': 'Open CrayCare to sign in',
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
        'widget_next_feed_at': -1,
        'widget_feeder_status': 'OFFLINE',
        'widget_feed_amount': '--',
        'widget_feed_amount_type': '',
      });
      await _requestNativeUpdate(snapshot);
      return;
    }

    final tankId = sensors.currentTankId ?? user.uid;
    _ensureClassificationListener(tankId);

    snapshot['widget_signed_in'] = true;
    snapshot['widget_online'] = sensors.isEspOnline;
    _writeClassification(snapshot);

    _writeSensor(snapshot, 'temp', 'temperature', '°C', decimals: 1);
    _writeSensor(snapshot, 'ph', 'ph', '', decimals: 2);
    _writeSensor(snapshot, 'do', 'dissolved_oxygen', 'mg/L', decimals: 1);
    _writeSensor(snapshot, 'turb', 'turbidity', 'NTU', decimals: 1);
    _writeSensor(snapshot, 'waterlevel', 'water_level', 'cm', decimals: 1);

    final now = manilaWallClock();
    final feeder = FeederService.instance;
    final activeSchedules = feeder.schedules
        .where((schedule) => schedule.enabled)
        .toList();
    final next = nextEnabledFeeding(activeSchedules, now);
    snapshot['widget_next_feed'] = next == null
        ? 'No schedule'
        : _formatFeedOccurrence(next.at, now);
    snapshot['widget_next_feed_at'] = next == null
        ? -1
        : _manilaWallClockToEpoch(next.at);
    snapshot['widget_feeder_status'] = feeder.isRunning
        ? 'DISPENSING'
        : (feeder.isOnline ? 'READY' : 'OFFLINE');
    snapshot['widget_feed_amount'] = next == null
        ? '--'
        : (next.schedule.grams == null
              ? '${defaultFeederGrams.toStringAsFixed(1)} g'
              : '${next.schedule.grams!.toStringAsFixed(1)} g');
    snapshot['widget_feed_amount_type'] = next == null
        ? ''
        : (next.schedule.grams == null ? 'DEFAULT' : 'CUSTOM');
    await _requestNativeUpdate(snapshot);
  }

  void _ensureClassificationListener(String tankId) {
    if (_classificationTankId == tankId && _classificationSub != null) return;
    _classificationSub?.cancel();
    _classificationTankId = tankId;
    _classificationData = null;

    _classificationSub = FirebaseFirestore.instance
        .collection('tanks')
        .doc(tankId)
        .collection('water_quality_classification')
        .doc('latest')
        .snapshots()
        .listen(
          (snap) {
            if (_classificationTankId != tankId) return;
            _classificationData = snap.data();
            _scheduleSync();
          },
          onError: (Object _) {
            // Keep last known classification or awaiting fallback on transient read error.
          },
        );
  }

  void _clearClassificationListener() {
    _classificationSub?.cancel();
    _classificationSub = null;
    _classificationTankId = null;
    _classificationData = null;
  }

  void _writeClassification(Map<String, Object> snapshot) {
    final data = _classificationData;
    final predictionStatus = data?['prediction_status']?.toString();
    final classLabel = data?['class_label']?.toString().trim();
    final insight = data?['insight']
        ?.toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (predictionStatus == 'classified' &&
        classLabel != null &&
        classLabel.isNotEmpty) {
      snapshot['widget_classification_status'] = classLabel.toUpperCase();
      snapshot['widget_classification_insight'] =
          (insight != null && insight.isNotEmpty)
          ? insight
          : 'Water quality classified as $classLabel.';
    } else if (predictionStatus == 'insufficient_data') {
      snapshot['widget_classification_status'] = 'INCOMPLETE';
      snapshot['widget_classification_insight'] =
          (insight != null && insight.isNotEmpty)
          ? insight
          : 'Waiting for complete sensor readings.';
    } else {
      snapshot['widget_classification_status'] = 'AWAITING DATA';
      snapshot['widget_classification_insight'] =
          'Waiting for next ML classification.';
    }
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

  /// Feeding schedules are evaluated using Manila wall-clock fields. Convert
  /// those fields to an absolute instant so Android can run a live countdown.
  int _manilaWallClockToEpoch(DateTime value) {
    return DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
    ).subtract(_manilaOffset).millisecondsSinceEpoch;
  }

  String _formatClock(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
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
    _clearClassificationListener();
    SensorService.instance.removeListener(_scheduleSync);
    SettingsService.instance.removeListener(_scheduleSync);
    FeederService.instance.removeListener(_scheduleSync);
    ConnectivityService.instance.removeListener(_scheduleSync);
    _initialized = false;
  }
}
