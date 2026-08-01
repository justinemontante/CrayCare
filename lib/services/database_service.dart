import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// DatabaseService — rewritten for the NEW Firestore structure:
///
/// users/{uid}
///   └── notification_settings/preferences
/// hardware_system/currentOwner            (⭐ single hardware assignment doc)
/// tanks/{tank_id}
///   ├── sensor_readings/latest
///   ├── sensors/{sensorName}
///   ├── actuators/{pump|aerator1|aerator2}
///   ├── feeder/status
///   ├── feeder_schedules/{scheduleId}
///   └── pending_commands/{commandId}
/// notifications/{notifId}
///
/// NOTE: FCM device tokens are stored on users/{uid}.fcmTokens (arrayUnion).
/// Each device adds its own token with arrayUnion; the Cloud Function reads
/// the array and pushes to every device of that account.
///
/// NOTE: tank_id is generated once per user at signup and stored on the
/// user's profile (users/{uid}.tank_id). We keep tank_id == uid for
/// simplicity (1 user = 1 tank), but ALWAYS read/write tank_id explicitly
/// instead of assuming uid, so the two can diverge later if needed.
class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Map<String, dynamic> convertMap(dynamic value) {
    if (value is Map) {
      return value.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  // ─── User Profile ──────────────────────────────────────────────────

  /// Creates/updates a user's profile. On first creation (no role/status
  /// passed in as an update-only call) this also provisions the user's
  /// tank, per the "1 User = 1 Tank" rule.
  Future<void> saveUserProfile({
    required String uid,
    required String name,
    required String email,
    String? photoUrl,
    String? role,
    String? status,
  }) async {
    if (uid.isEmpty) throw ArgumentError('UID cannot be empty');
    if (name.isEmpty) throw ArgumentError('Name cannot be empty');
    if (email.isEmpty) throw ArgumentError('Email cannot be empty');

    final userRef = _db.collection('users').doc(uid);

    try {
      final existing = await userRef.get();
      final isNewUser = !existing.exists;
      final effectiveRole = role ?? existing.data()?['role'] as String? ?? 'owner';

      final data = <String, dynamic>{
        'full_name': name,
        'email': email,
        'role': effectiveRole,
      };
      if (photoUrl != null) {
        data['photo_url'] = photoUrl;
        data['photoUrl'] = photoUrl; // legacy key read by main_shell.dart
      }
      if (status != null) data['status'] = status;
      if (isNewUser) {
        data['status'] ??= 'active';
        data['created_at'] = FieldValue.serverTimestamp();
      }

      // Only 'owner' accounts get a tank; admins don't own a tank.
      if (isNewUser && effectiveRole == 'owner') {
        final tankId = uid; // tank_id == uid (1 user = 1 tank)
        data['tank_id'] = tankId;
        await userRef.set(data, SetOptions(merge: true));
        await _createTankIfMissing(tankId, ownerUid: uid);
        await _createDefaultNotificationSettings(uid);
      } else {
        await userRef.set(data, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[DatabaseService] Error saving user profile: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists && doc.data() != null) return doc.data()!;
    return null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> userProfileStream(String uid) =>
      _db.collection('users').doc(uid).snapshots();

  // ─── Notification Settings (users/{uid}/notification_settings) ────

  Future<void> _createDefaultNotificationSettings(String uid) async {
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('notification_settings')
        .doc('preferences');
    final existing = await ref.get();
    if (existing.exists) return;
    await ref.set({
      'sound': true,
      'vibration': true,
      'critical': true,
      'warning': true,
      'feeding': true,
      'sampling': true,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveNotificationPrefs({
    required String uid,
    required bool sound,
    required bool vibration,
    required bool critical,
    required bool feeding,
    required bool sampling,
    bool warning = true,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('notification_settings')
        .doc('preferences')
        .set({
      'sound': sound,
      'vibration': vibration,
      'critical': critical,
      'warning': warning,
      'feeding': feeding,
      'sampling': sampling,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getNotificationPrefs(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('notification_settings')
        .doc('preferences')
        .get();
    if (doc.exists && doc.data() != null) return doc.data()!;
    return null;
  }

  // ─── Tank ──────────────────────────────────────────────────────────

  Future<void> _createTankIfMissing(String tankId, {String? ownerUid}) async {
    final ref = _db.collection('tanks').doc(tankId);
    final existing = await ref.get();
    if (existing.exists) return;

    await ref.set({
      'owner_uid': ownerUid ?? tankId,
      'current_batch_id': '',
      'lifetime_mortality': 0,
      'lifetime_harvested': 0,
      'is_initialized': false,
      'created_at': FieldValue.serverTimestamp(),
    });

    // Seed default sensor thresholds.
    const defaults = {
      'temperature': {'min': 24.0, 'max': 30.0},
      'ph_level': {'min': 7.0, 'max': 8.5},
      'dissolved_oxygen': {'min': 5.0, 'max': 9.0},
      'turbidity': {'min': 0.0, 'max': 25.0},
      'water_level': {'min': 70.0, 'max': 100.0},
    };
    final batch = _db.batch();
    for (final entry in defaults.entries) {
      final sensorRef = ref.collection('sensors').doc(entry.key);
      batch.set(sensorRef, {
        'min_value': entry.value['min'],
        'max_value': entry.value['max'],
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    // Seed default actuators (off, manual-off state).
    for (final type in ['pump', 'aerator1', 'aerator2']) {
      final actuatorRef = ref.collection('actuators').doc(type);
      batch.set(actuatorRef, {
        'control_mode': 'off',
        'current_state': 'off',
        'last_changed': FieldValue.serverTimestamp(),
      });
    }
    // Seed feeder status doc.
    batch.set(ref.collection('feeder').doc('status'), {
      'status': 'idle',
      'last_dispensed_at': null,
      'last_dispensed_grams': 0.0,
    });
    await batch.commit();
  }

  Future<Map<String, dynamic>?> getTank(String tankId) async {
    final doc = await _db.collection('tanks').doc(tankId).get();
    if (doc.exists && doc.data() != null) return doc.data()!;
    return null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> tankStream(String tankId) =>
      _db.collection('tanks').doc(tankId).snapshots();

  /// Convenience: resolves a user's tank_id from their profile.
  Future<String?> getTankIdForUser(String uid) async {
    final profile = await getUserProfile(uid);
    return profile?['tank_id'] as String?;
  }

  // ─── Sensor Thresholds (tanks/{tank_id}/sensors/{sensorName}) ─────

  Future<void> saveSensorThresholds({
    required Map<String, Map<String, double>> currentRanges,
    String? changedKey,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final profile = await getUserProfile(user.uid);
    final role = profile?['role'] as String?;
    if (role == 'admin') {
      throw Exception('Only the tank owner can change sensor thresholds.');
    }

    final tankId = profile?['tank_id'] as String? ?? user.uid;
    final tankRef = _db.collection('tanks').doc(tankId);

    final batch = _db.batch();
    for (final entry in currentRanges.entries) {
      final sensorRef = tankRef.collection('sensors').doc(entry.key);
      batch.set(sensorRef, {
        'min_value': entry.value['min'],
        'max_value': entry.value['max'],
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    if (changedKey != null) {
      debugPrint('[DatabaseService] Threshold changed: $changedKey for tank $tankId');
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> sensorThresholdsStream(String tankId) =>
      _db.collection('tanks').doc(tankId).collection('sensors').snapshots();

  // ─── Actuators (tanks/{tank_id}/actuators/{pump|aerator1|aerator2}) ─────────

  Future<void> saveActuatorMode({
    required String actuatorId, // 'pump', 'aerator1', or 'aerator2'
    required String mode,     // 'on' | 'off' | 'auto'
    required String actuatorName,
    required String modeLabel,
    required String time,
    required String date,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final profile = await getUserProfile(user.uid);
    final tankId = profile?['tank_id'] as String? ?? user.uid;

    final tankRef = _db.collection('tanks').doc(tankId);

    await tankRef.collection('actuators').doc(actuatorId).set({
      'control_mode': mode,
      'current_state': mode == 'off' ? 'off' : 'on',
      'last_changed': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await tankRef.collection('actuator_logs').add({
      'actuator_type': actuatorId,
      'action': 'Switched ${mode.toUpperCase()} — $actuatorName ($modeLabel)',
      'log_level': 'info',
      'message': '$actuatorName set to $modeLabel',
      'type': mode,
      'time': time,
      'date': date,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'logged_at': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> actuatorLogsStream(String tankId, String actuatorId) {
    return _db
        .collection('tanks')
        .doc(tankId)
        .collection('actuator_logs')
        .where('actuator_type', isEqualTo: actuatorId)
        .orderBy('logged_at', descending: true)
        .limit(50)
        .snapshots();
  }

  // ─── Hardware Owner (admin) ─────────────────────────────────────────
  // Single source of truth: hardware_system/currentOwner { uid, tank_id }.
  // The ESP32 reads this doc to know whose tank to write sensor data to.
  // Reassigning is instant; the previous owner's tank data is preserved.

  /// Returns the UID of the currently assigned hardware owner, or null.
  Future<String?> getCurrentOwnerUid() async {
    final doc = await _db.collection('hardware_system').doc('currentOwner').get();
    if (!doc.exists || doc.data() == null) return null;
    return doc.data()!['uid'] as String?;
  }

  /// Returns the tank_id currently receiving hardware data, or null.
  Future<String?> getCurrentOwnerTankId() async {
    final doc = await _db.collection('hardware_system').doc('currentOwner').get();
    if (!doc.exists || doc.data() == null) return null;
    return doc.data()!['tank_id'] as String?;
  }

  /// Real-time stream of the hardware assignment doc.
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamCurrentOwner() =>
      _db.collection('hardware_system').doc('currentOwner').snapshots();

  /// Assigns the hardware to [ownerUid]. Fetches the user's tank_id first,
  /// then writes BOTH uid and tank_id to hardware_system/currentOwner.
  Future<void> setCurrentOwner(String ownerUid) async {
    if (ownerUid.isEmpty) throw ArgumentError('ownerUid cannot be empty');

    final admin = FirebaseAuth.instance.currentUser;

    final profile = await getUserProfile(ownerUid);
    if (profile == null) {
      throw Exception('User $ownerUid does not exist.');
    }
    var tankId = profile['tank_id'] as String?;

    // Edge case: user has no tank yet (e.g. legacy account) — provision one.
    if (tankId == null || tankId.isEmpty) {
      tankId = ownerUid;
      await _createTankIfMissing(tankId, ownerUid: ownerUid);
      await _db.collection('users').doc(ownerUid).set(
        {'tank_id': tankId},
        SetOptions(merge: true),
      );
    }

    try {
      await _db.collection('hardware_system').doc('currentOwner').set({
        'uid': ownerUid,
        'tank_id': tankId,
        'assigned_by': admin?.uid,
        'assigned_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[DatabaseService] Error assigning hardware owner: $e');
      rethrow;
    }
  }

  /// Unassigns the hardware (uid and tank_id set to null, doc preserved
  /// for audit trail of assigned_by/assigned_at of the last assignment).
  Future<void> removeCurrentOwner() async {
    await _db.collection('hardware_system').doc('currentOwner').set({
      'uid': null,
      'tank_id': null,
    }, SetOptions(merge: true));
  }

  // ─── Admin: user management ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final snap = await _db.collection('users').get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['uid'] = d.id;
      return data;
    }).toList();
  }

  Future<void> setUserStatus(String uid, String status) async {
    await _db.collection('users').doc(uid).set(
      {'status': status},
      SetOptions(merge: true),
    );
  }

  Future<void> setUserRole(String uid, String role) async {
    await _db.collection('users').doc(uid).set(
      {'role': role},
      SetOptions(merge: true),
    );
  }
}
