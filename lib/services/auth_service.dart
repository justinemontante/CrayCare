import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Auth state stream
  Stream<User?> get user => _auth.authStateChanges();

  // SIGN UP (In-update para isama ang Name at Email Verification)
  Future<User?> signUp(String name, String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = result.user;

      if (user != null) {
        await user.updateDisplayName(name);
        if (!user.emailVerified) {
          await user.sendEmailVerification();
        }
        final ownerUid = await DatabaseService.instance.findOwnerUid();
        await DatabaseService.instance.saveUserProfile(
          uid: user.uid,
          name: name,
          email: email,
          role: 'monitor',
          status: 'active',
          ownerUid: ownerUid,
        );
      }

      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  // SIGN IN
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = result.user;

      if (user != null) {
        // Kumuha muna ng profile sa RTDB para ma-verify kung disabled
        final profile = await DatabaseService.instance.getUserProfile(user.uid);
        if (profile != null && profile['status'] == 'disabled') {
          await signOut();
          throw Exception('Your account has been disabled. Please contact the administrator.');
        }

        if (!user.emailVerified) {
          await _auth.signOut();
          throw Exception(
            'Please verify your email first. A verification link was sent to your inbox.',
          );
        }

        // Para sa mga existing users — i-save sa RTDB (preserve photoUrl)
        final String? existingRole = profile?['role'] as String?;
        final String? existingStatus = profile?['status'] as String?;
        await DatabaseService.instance.saveUserProfile(
          uid: user.uid,
          name: user.displayName ?? 'CrayCare User',
          email: user.email ?? '',
          photoUrl: profile?['photoUrl'] as String?,
          role: existingRole ?? 'monitor', // Kung walang role, gawing 'monitor'
          status: existingStatus ?? 'active',
        );
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  // GOOGLE SIGN IN
  Future<User?> signInWithGoogle() async {
    try {
      // Open Google popup
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      // User cancelled
      if (googleUser == null) {
        return null;
      }

      // Get auth details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      // I-save sa RTDB ang Google user profile
      final user = userCredential.user;
      if (user != null) {
        // Kunin muna ang existing profile para hindi mawala ang photoUrl/role/status
        final profile = await DatabaseService.instance.getUserProfile(user.uid);
        if (profile != null && profile['status'] == 'disabled') {
          await signOut();
          throw Exception('Your account has been disabled. Please contact the administrator.');
        }

        final String? existingRole = profile?['role'] as String?;
        final String? existingStatus = profile?['status'] as String?;
        final String? existingOwnerUid = profile?['ownerUid'] as String?;
        String? ownerUid = existingOwnerUid;
        if (ownerUid == null || ownerUid.isEmpty) {
          ownerUid = await DatabaseService.instance.findOwnerUid();
        }
        await DatabaseService.instance.saveUserProfile(
          uid: user.uid,
          name: user.displayName ?? 'Google User',
          email: user.email ?? '',
          photoUrl: profile?['photoUrl'] as String?,
          role: existingRole ?? 'monitor',
          status: existingStatus ?? 'active',
          ownerUid: ownerUid,
        );
      }

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // CHANGE PASSWORD
  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user logged in.');

    // Check if user has email/password provider
    final hasEmailProvider = user.providerData.any(
      (info) => info.providerId == 'password',
    );

    if (hasEmailProvider) {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      try {
        await user.reauthenticateWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          await user.reauthenticateWithCredential(credential);
        } else {
          rethrow;
        }
      }
    }

    await user.updatePassword(newPassword);
  }

  // SIGN OUT
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseDatabase.instance
            .ref('users/$uid/fcmToken')
            .remove();
      } catch (e) {
        debugPrint('[AuthService] Failed to clear FCM token on signout: $e');
      }
    }
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
