import 'dart:async';
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
    final data = <String, dynamic>{
      'displayName': name,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (photoUrl != null) data['photoUrl'] = photoUrl;
    if (role != null) data['role'] = role;
    if (status != null) data['status'] = status;
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      data,
      SetOptions(merge: true),
    );
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

  Future<List<Map<String, dynamic>>> getSensorHistory({
    int limit = 100,
    String orderBy = 'timestamp',
  }) async {
    try {
      final query = await FirebaseFirestore.instance
          .collectionGroup('sensorHistory')
          .orderBy(orderBy, descending: true)
          .limit(limit)
          .get();
      return query.docs.map((doc) => doc.data()).toList();
    } catch (_) {
      return [];
    }
  }
}
