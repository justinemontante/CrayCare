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
}
