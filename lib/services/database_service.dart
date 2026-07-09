import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  static Map<String, dynamic> convertMap(Object? value) {
    if (value is Map) {
      return value.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// I-save ang profile name, email, at photo URL ng user sa RTDB
  Future<void> saveUserProfile({
    required String uid,
    required String name,
    required String email,
    String? photoUrl,
  }) async {
    final data = <String, dynamic>{
      'displayName': name,
      'email': email,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (photoUrl != null) data['photoUrl'] = photoUrl;
    await _db.child('users/$uid/profile').update(data);
  }

  /// Kunin ang naka-save na profile ng user galing RTDB
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final snapshot = await _db.child('users/$uid/profile').get();
    if (snapshot.exists && snapshot.value != null) {
      return convertMap(snapshot.value as Map);
    }
    return null;
  }

  // ─── Growth Stage Config (per-user) ────────────────────────────

  DatabaseReference _growthStageRef(String uid) =>
      _db.child('users/$uid/growth_stage');

  Future<Map<String, dynamic>?> getGrowthStageConfig() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final snapshot = await _growthStageRef(uid).get().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Firebase read timed out'),
    );
    if (snapshot.exists && snapshot.value != null) {
      return convertMap(snapshot.value as Map);
    }
    return null;
  }

  Future<void> saveGrowthStageConfig({
    required String currentStage,
    required Map<String, Map<String, Map<String, double>>> allRanges,
    String? changedKey,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) return;

    await _growthStageRef(uid)
        .update({
          'currentStage': currentStage,
          'allRanges': {
            for (final stageEntry in allRanges.entries)
              stageEntry.key: {
                for (final sensorEntry in stageEntry.value.entries)
                  sensorEntry.key: sensorEntry.value,
              },
          },
          'updatedAt': ServerValue.timestamp,
          'updatedBy': user?.uid ?? 'unknown-user',
          'source': 'flutter-app',
          if (changedKey != null) 'lastChangedSensor': changedKey,
        })
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw TimeoutException('Firebase write timed out'),
        );
  }

  // ─── Sensor Readings (per-user) ───────────────────────────────

  DatabaseReference get _sensorLatestRef =>
      _db.child('sensor_readings/latest');

  DatabaseReference get _sensorHistoryRef =>
      _db.child('sensor_readings/history');

  DatabaseReference get _sensorConfigRef =>
      _db.child('sensor_readings/config');

  Future<Map<String, dynamic>?> getLatestReadings() async {
    final snapshot = await _sensorLatestRef.get().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Firebase read timed out'),
    );
    if (snapshot.exists && snapshot.value != null) {
      return convertMap(snapshot.value as Map);
    }
    return null;
  }

  Stream<DatabaseEvent> get latestReadingsStream => _sensorLatestRef.onValue;

  Future<void> saveSensorThresholds({
    required String currentStage,
    required Map<String, Map<String, double>> currentRanges,
    String? changedKey,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) return;

    await _sensorConfigRef.update({
      'currentStage': currentStage,
      'ranges': {
        for (final e in currentRanges.entries)
          e.key: {'min': e.value['min'], 'max': e.value['max']},
      },
      'updatedAt': ServerValue.timestamp,
      'updatedBy': user?.uid ?? 'unknown-user',
      'source': 'flutter-app',
      if (changedKey != null) 'lastChangedSensor': changedKey,
    }).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Firebase write timed out'),
    );
  }

  // ─── Device Modes (Aerator 1, Aerator 2, Water Pump) ───────────

  DatabaseReference get _devicesModesRef =>
      _db.child('devices/modes');

  DatabaseReference get _devicesLogsRef =>
      _db.child('devices/logs');

  Future<void> saveDeviceMode({
    required String deviceId,
    required String mode,
    required String deviceName,
    required String modeLabel,
    required String time,
    required String date,
  }) async {
    await _devicesModesRef.child(deviceId).set(mode);
    await _devicesLogsRef.child(deviceId).push().set({
      'action': '$deviceName: $modeLabel',
      'type': mode,
      'time': time,
      'date': date,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Stream<DatabaseEvent> get deviceModesStream => _devicesModesRef.onValue;

  Stream<DatabaseEvent> deviceLogsStream(String deviceId) =>
      _devicesLogsRef.child(deviceId).onValue;

  // ─── Per-User Notification Preferences ─────────────────────────

  Future<void> saveNotificationPrefs({
    required String uid,
    required bool sound,
    required bool vibration,
    required bool critical,
    required bool feeding,
    required bool sampling,
    bool warning = true,
  }) async {
    // Stored in a dedicated 'notifPrefs' node — separate from notification
    // records in 'notifications/' to avoid them overwriting each other.
    await _db.child('users/$uid/notifPrefs').set({
      'sound': sound,
      'vibration': vibration,
      'critical': critical,
      'warning': warning,
      'feeding': feeding,
      'sampling': sampling,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> getNotificationPrefs(String uid) async {
    final snapshot = await _db.child('users/$uid/notifPrefs').get();
    if (snapshot.exists) {
      return convertMap(snapshot.value as Map);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getSensorHistory({
    int limit = 100,
    String orderBy = 'timestamp',
  }) async {
    final snapshot = await _sensorHistoryRef
        .orderByChild(orderBy)
        .limitToLast(limit)
        .get()
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('Firebase history read timed out'),
        );
    if (!snapshot.exists || snapshot.value == null) return [];
    final raw = convertMap(snapshot.value as Map);
    final list = <Map<String, dynamic>>[];
    raw.forEach((key, value) {
      if (value is Map) {
        list.add(convertMap(value));
      }
    });
    list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
    return list;
  }

}
