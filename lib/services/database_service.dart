import 'dart:async';
import 'package:flutter/foundation.dart';
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

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// I-save ang profile name, email, at photo URL ng user sa RTDB
  /// [role] — 'monitor' (default for new users) or 'owner' or 'admin'
  /// [status] — 'active' or 'disabled'
  Future<void> saveUserProfile({
    required String uid,
    required String name,
    required String email,
    String? photoUrl, // Optional — kung may profile picture
    String? role, // Optional — only written on first signup
    String? status, // Optional — defaults to 'active' on first signup
  }) async {
    final data = <String, dynamic>{
      'displayName': name,
      'email': email,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (photoUrl != null) data['photoUrl'] = photoUrl;
    if (role != null) data['role'] = role;
    if (status != null) {
      data['status'] = status;
    } else {
      // Kung wala pang profile, default status is 'active'
      final existing = await getUserProfile(uid);
      if (existing == null || existing['status'] == null) {
        data['status'] = 'active';
      }
    }
    // Use update() para hindi ma-overwrite ang existing 'role'/'status' kung hindi naka-pass
    await _db.child('users/$uid/profile').update(data);
  }

  /// Kunin ang naka-save na profile ng user galing RTDB
  /// May laman na 'displayName', 'email', 'photoUrl' (kung meron), 'role', 'status'
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final snapshot = await _db.child('users/$uid/profile').get();
    if (snapshot.exists && snapshot.value != null) {
      return convertMap(snapshot.value as Map);
    }
    return null;
  }

  /// Kumuha ng Stream ng lahat ng users para sa Admin User Management Screen
  Stream<DatabaseEvent> getAllUsersStream() {
    return _db.child('users').onValue;
  }

  /// I-update ang Role at Status ng isang user (Admin function)
  /// If [role] is 'owner', automatically demote any other owner to 'monitor' to enforce single-owner limit.
  Future<void> updateUserRoleAndStatus({
    required String uid,
    required String role,
    required String status,
  }) async {
    final updates = <String, dynamic>{
      'users/$uid/profile/role': role,
      'users/$uid/profile/status': status,
      'users/$uid/profile/updatedAt': DateTime.now().toIso8601String(),
    };

    if (role == 'owner') {
      final usersSnapshot = await _db.child('users').get();
      if (usersSnapshot.exists && usersSnapshot.value != null) {
        final rawUsers = usersSnapshot.value as Map;
        rawUsers.forEach((key, val) {
          final userId = key.toString();
          if (userId != uid && val is Map && val['profile'] != null) {
            final profile = val['profile'] as Map;
            if (profile['role'] == 'owner') {
              updates['users/$userId/profile/role'] = 'monitor';
              updates['users/$userId/profile/updatedAt'] = DateTime.now().toIso8601String();
            }
          }
        });
      }
    }

    await _db.update(updates);
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

    // Safety lock: Verify user is Owner before database updates
    final profile = await getUserProfile(uid);
    final role = profile?['role'] as String?;
    if (role != 'owner') {
      debugPrint('[DatabaseService] Blocked non-owner saveGrowthStageConfig call for role: $role');
      return;
    }

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

    // Safety lock: Verify user is Owner before database updates
    final profile = await getUserProfile(uid);
    final role = profile?['role'] as String?;
    if (role != 'owner') {
      debugPrint('[DatabaseService] Blocked non-owner saveSensorThresholds call for role: $role');
      return;
    }

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
