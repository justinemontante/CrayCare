import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  static Map<String, dynamic> convertMap(dynamic value) {
    if (value is Map) {
      return value.map<String, dynamic>((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  // ─── User Profile ──────────────────────────────────────────────────

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

    final data = <String, dynamic>{
      'fullName': name,
      'email': email,
    };
    if (role != null) data['role'] = role;
    if (status != null) data['status'] = status;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        data,
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[DatabaseService] Error saving user profile: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      return doc.data()!;
    }
    return null;
  }

  // ─── Tank ──────────────────────────────────────────────────────────

  Future<void> createTank(String userId) async {
    await FirebaseFirestore.instance.collection('tanks').doc(userId).set({
      'userId': userId,
      'currentBatchId': '',
      'lifetimeMortality': 0,
      'lifetimeHarvested': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getTank(String tankId) async {
    final doc = await FirebaseFirestore.instance.collection('tanks').doc(tankId).get();
    if (doc.exists && doc.data() != null) return doc.data()!;
    return null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> tankStream(String tankId) =>
      FirebaseFirestore.instance.collection('tanks').doc(tankId).snapshots();

  // ─── Device Assignment (system_config) ─────────────────────────────

  Future<Map<String, dynamic>?> getDeviceAssignment() async {
    final doc = await FirebaseFirestore.instance
        .collection('system_config')
        .doc('device_assignment')
        .get();
    if (doc.exists && doc.data() != null) return doc.data();
    return null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> get deviceAssignmentStream =>
      FirebaseFirestore.instance.collection('system_config').doc('device_assignment').snapshots();

  Future<void> setDeviceAssignment(String tankId) async {
    final admin = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection('system_config').doc('device_assignment').set({
      'assignedTankId': tankId,
      'assignedBy': admin?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> canViewDeviceReadings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final profile = await getUserProfile(user.uid);
    final role = profile?['role'] as String?;
    if (role == 'admin') return true;

    final assignment = await getDeviceAssignment();
    final assignedTankId = assignment?['assignedTankId'] as String?;
    return assignedTankId != null && user.uid == assignedTankId;
  }

  // ─── Sensor Thresholds (stored in tanks/{tankId}) ──────────────────

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

    final data = <String, dynamic>{
      'ranges': {
        for (final e in currentRanges.entries)
          e.key: {'min': e.value['min'], 'max': e.value['max']},
      },
    };
    if (changedKey != null) data['lastChangedSensor'] = changedKey;

    // Write to config/{uid} — same path SettingsService reads from, so the
    // UI immediately reflects the saved values on the next sync.
    await FirebaseFirestore.instance.collection('config').doc(user.uid).set(
      data,
      SetOptions(merge: true),
    );
  }

  // ─── Device Mode (hardware_status) ────────────────────────────────

  Future<void> saveDeviceMode({
    required String deviceId,
    required String mode,
    required String deviceName,
    required String modeLabel,
    required String time,
    required String date,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final tankId = user.uid;

    // Write to deviceModes/{deviceId} — matches the path the ESP32 firmware
    // reads: Firebase.Firestore.getDocument(..., "deviceModes/{devId}", "mode")
    await FirebaseFirestore.instance.collection('deviceModes').doc(deviceId).set(
      {
        'mode': mode,
        'tankId': tankId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await FirebaseFirestore.instance.collection('deviceLogs').add({
      'tankId': tankId,
      'device': deviceId,
      'action': mode == 'auto' || mode == 'manual' ? 'turned_on' : 'turned_off',
      'performedBy': mode == 'auto' ? 'auto' : 'user',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> deviceLogsStream(String deviceId) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream.empty();
    }
    return FirebaseFirestore.instance
        .collection('deviceLogs')
        .where('tankId', isEqualTo: user.uid)
        .where('device', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  // ─── Notification Prefs ────────────────────────────────────────────

  Future<void> saveNotificationPrefs({
    required String uid,
    required bool sound,
    required bool vibration,
    required bool critical,
    required bool feeding,
    required bool sampling,
    bool warning = true,
  }) async {
    await FirebaseFirestore.instance.collection('notifPrefs').doc(uid).set({
      'sound': sound,
      'vibration': vibration,
      'critical': critical,
      'warning': warning,
      'feeding': feeding,
      'sampling': sampling,
    });
  }

  Future<Map<String, dynamic>?> getNotificationPrefs(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('notifPrefs').doc(uid).get();
    if (doc.exists && doc.data() != null) return doc.data()!;
    return null;
  }

  // ─── Hardware Owner (admin) ─────────────────────────────────────────
  // A single document, hardware_system/currentOwner { uid }, stores the
  // UID of the owner whose account receives all sensor data.
  //
  // The Cloud Function onSensorIngestionWrite reads this document to route
  // ESP32 sensor writes to the correct per-owner sensorReadings path.
  // Re-assigning is instant and works without touching the ESP32 firmware.

  /// Returns the UID of the currently assigned hardware owner, or null.
  Future<String?> getCurrentOwnerUid() async {
    final doc = await FirebaseFirestore.instance
        .collection('hardware_system')
        .doc('currentOwner')
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return doc.data()!['uid'] as String?;
  }

  /// Assigns the hardware to [ownerUid] by writing hardware_system/currentOwner.
  Future<void> setCurrentOwner(String ownerUid) async {
    if (ownerUid.isEmpty) throw ArgumentError('ownerUid cannot be empty');
    final admin = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance
        .collection('hardware_system')
        .doc('currentOwner')
        .set({
      'uid': ownerUid,
      'assignedBy': admin?.uid,
      'assignedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes the current hardware owner (hardware_system/currentOwner deleted).
  Future<void> removeCurrentOwner() async {
    await FirebaseFirestore.instance
        .collection('hardware_system')
        .doc('currentOwner')
        .delete();
  }

  // ─── Admin: user management ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final snap = await FirebaseFirestore.instance.collection('users').get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['uid'] = d.id;
      return data;
    }).toList();
  }

  Future<void> setUserStatus(String uid, String status) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'status': status},
      SetOptions(merge: true),
    );
  }

  Future<void> setUserRole(String uid, String role) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'role': role},
      SetOptions(merge: true),
    );
  }

}
