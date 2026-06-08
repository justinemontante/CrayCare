// Firebase Realtime Database — para mag-save at magbasa ng data online
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();
  // Root reference ng Realtime Database natin
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// I-save ang profile name, email, at photo URL ng user sa RTDB
  Future<void> saveUserProfile({
    required String uid,
    required String name,
    required String email,
    String? photoUrl, // Optional — kung may profile picture
  }) async {
    await _db.child('users/$uid/profile').set({
      'displayName': name,
      'email': email,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Kunin ang naka-save na profile ng user galing RTDB
  /// May laman na 'displayName', 'email', 'photoUrl' (kung meron)

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final snapshot = await _db.child('users/$uid/profile').get();
    if (snapshot.exists) {
      return Map<String, dynamic>.from(snapshot.value as Map);
    }
    return null;
  }

  // ─── Growth Stage Config ───────────────────────────────────────

  DatabaseReference get _growthStageRef => _db.child('growth_stage');

  Future<Map<String, dynamic>?> getGrowthStageConfig() async {
    final snapshot = await _growthStageRef.get().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Firebase read timed out'),
    );
    if (snapshot.exists && snapshot.value != null) {
      return Map<String, dynamic>.from(snapshot.value as Map);
    }
    return null;
  }

  Future<void> saveGrowthStageConfig({
    required String currentStage,
    required Map<String, Map<String, Map<String, double>>> allRanges,
    String? changedKey,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    await _growthStageRef
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

  // ─── Sensor Readings ────────────────────────────────────────────

  DatabaseReference get _sensorLatestRef => _db.child('sensor_readings/latest');
  DatabaseReference get _sensorHistoryRef => _db.child('sensor_readings/history');
  DatabaseReference get _sensorConfigRef => _db.child('sensor_readings/config');

  Future<Map<String, dynamic>?> getLatestReadings() async {
    final snapshot = await _sensorLatestRef.get().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Firebase read timed out'),
    );
    if (snapshot.exists && snapshot.value != null) {
      return Map<String, dynamic>.from(snapshot.value as Map);
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

  // ─── Per-User Notification Preferences ─────────────────────────

  Future<void> saveNotificationPrefs({
    required String uid,
    required bool sound,
    required bool vibration,
    required bool critical,
    required bool feeding,
    required bool sampling,
  }) async {
    await _db.child('users/$uid/notifications').set({
      'sound': sound,
      'vibration': vibration,
      'critical': critical,
      'feeding': feeding,
      'sampling': sampling,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> getNotificationPrefs(String uid) async {
    final snapshot = await _db.child('users/$uid/notifications').get();
    if (snapshot.exists) {
      return Map<String, dynamic>.from(snapshot.value as Map);
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
    final raw = Map<String, dynamic>.from(snapshot.value as Map);
    final list = <Map<String, dynamic>>[];
    raw.forEach((key, value) {
      if (value is Map) {
        list.add(Map<String, dynamic>.from(value));
      }
    });
    list.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
    return list;
  }
}
