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

  Future<void> saveUserProfile({
    required String uid,
    required String name,
    required String email,
    String? photoUrl,
    String? role,
    String? status,
  }) async {
    if (uid.isEmpty) {
      throw ArgumentError('UID cannot be empty');
    }
    if (name.isEmpty) {
      throw ArgumentError('Name cannot be empty');
    }
    if (email.isEmpty) {
      throw ArgumentError('Email cannot be empty');
    }
    final data = <String, dynamic>{
      'displayName': name,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (photoUrl != null) data['photoUrl'] = photoUrl;
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

  Future<Map<String, dynamic>?> getLatestReadings() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('sensorReadings').doc('latest').get();
      if (doc.exists && doc.data() != null) return doc.data()!;
    } catch (_) {}
    return null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> get latestReadingsStream =>
      FirebaseFirestore.instance.collection('sensorReadings').doc('latest').snapshots();

  Future<void> saveSensorThresholds({
    required Map<String, Map<String, double>> currentRanges,
    String? changedKey,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // This writes to config/default, which every user's alerts and the
    // sensor-alert Cloud Function read from — it is shared, global state,
    // not per-user. A "monitor" or "admin" account should never be able to
    // silently overwrite the tank owner's thresholds.
    final profile = await getUserProfile(user.uid);
    final role = profile?['role'] as String?;
    if (role == 'monitor' || role == 'admin') {
      throw Exception('Only the tank owner can change sensor thresholds.');
    }

    final data = <String, dynamic>{
      'ranges': {
        for (final e in currentRanges.entries)
          e.key: {'min': e.value['min'], 'max': e.value['max']},
      },
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
      'source': 'flutter-app',
    };
    if (changedKey != null) data['lastChangedSensor'] = changedKey;

    await FirebaseFirestore.instance.collection('config').doc(user.uid).set(
      data,
      SetOptions(merge: true),
    );

    // Also write to config/default/ranges for the Cloud Function
    // (onSensorUpdate) to read sensor thresholds from Firestore
    await FirebaseFirestore.instance.collection('config').doc('default').set(
      data,
      SetOptions(merge: true),
    ).catchError((_) {});
  }

  Future<void> saveDeviceMode({
    required String deviceId,
    required String mode,
    required String deviceName,
    required String modeLabel,
    required String time,
    required String date,
  }) async {
    await FirebaseFirestore.instance.collection('deviceModes').doc(deviceId).set({
      'mode': mode,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid,
    });

    await FirebaseFirestore.instance.collection('deviceLogs').add({
      'deviceId': deviceId,
      'action': '$deviceName: $modeLabel',
      'type': mode,
      'time': time,
      'date': date,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> deviceModesStream(String deviceId) =>
      FirebaseFirestore.instance.collection('deviceModes').doc(deviceId).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> deviceLogsStream(String deviceId) =>
      FirebaseFirestore.instance
          .collection('deviceLogs')
          .where('deviceId', isEqualTo: deviceId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots();

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
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getNotificationPrefs(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('notifPrefs').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      return doc.data()!;
    }
    return null;
  }

  // ─── Admin: user management ──────────────────────────────────────────
  //
  // Every account created via AuthService.signUp/signInWithGoogle defaults
  // to role 'owner'. There is no in-app way to become 'admin' — that has
  // to be set directly on the users/{uid} document in the Firestore
  // console (data['role'] = 'admin'). This is deliberate: admin can't be
  // self-granted through the app.

  /// Returns all user profiles, for the admin user-management screen.
  /// Requires the caller's own role to be 'admin' (enforced by
  /// firestore.rules — this will simply come back empty/error otherwise).
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final snap = await FirebaseFirestore.instance.collection('users').get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['uid'] = d.id;
      return data;
    }).toList();
  }

  /// Enables or disables a user's account. A disabled account is signed
  /// out immediately and blocked from signing back in (see AuthService).
  Future<void> setUserStatus(String uid, String status) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'status': status, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Changes a user's role: 'admin' | 'owner' | 'monitor'.
  Future<void> setUserRole(String uid, String role) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'role': role, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// Links a 'monitor' account to the owner whose tank it should view.
  Future<void> setMonitorOwner(String monitorUid, String ownerUid) async {
    await FirebaseFirestore.instance.collection('users').doc(monitorUid).set(
      {'ownerUid': ownerUid, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  // ─── Admin: which owner the single physical device belongs to ────────
  //
  // The ESP hardware itself is unaware of any of this — it always writes
  // to sensorReadings/latest exactly as before. This just controls, at
  // the app/rules layer, whose account that live data is currently
  // attributed to, so only that owner (+ their linked monitors) and
  // admins can read it.

  Future<Map<String, dynamic>?> getDeviceOwner() async {
    final doc = await FirebaseFirestore.instance.collection('config').doc('deviceOwner').get();
    if (doc.exists && doc.data() != null) return doc.data();
    return null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> get deviceOwnerStream =>
      FirebaseFirestore.instance.collection('config').doc('deviceOwner').snapshots();

  /// Admin-only (enforced by firestore.rules): assigns which owner the
  /// shared hardware currently belongs to.
  Future<void> setDeviceOwner(String ownerUid) async {
    final admin = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance.collection('config').doc('deviceOwner').set({
      'ownerUid': ownerUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': admin?.uid,
    });
  }

  /// True if the signed-in user is allowed to view the live sensor
  /// readings: they're the assigned owner, a monitor linked to that
  /// owner, or an admin.
  Future<bool> canViewDeviceReadings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final profile = await getUserProfile(user.uid);
    final role = profile?['role'] as String?;
    if (role == 'admin') return true;

    final deviceOwner = await getDeviceOwner();
    final ownerUid = deviceOwner?['ownerUid'] as String?;
    if (ownerUid == null) return false;
    if (role == 'monitor') return profile?['ownerUid'] == ownerUid;
    return user.uid == ownerUid;
  }

  /// Saves a gender detection result to Firestore under the user's
  /// genderScans collection.
  Future<void> saveCrayfishGender({
    required String batchId,
    required String label,
    required double confidence,
    List<double>? bbox,
    String? imageUrl,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('genderScans')
        .add({
      'batchId': batchId,
      'label': label,
      'confidence': confidence,
      'bbox': bbox,
      'imageUrl': imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
