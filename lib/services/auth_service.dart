import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  Stream<User?> get user => _auth.authStateChanges();

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
        await DatabaseService.instance.saveUserProfile(
          uid: user.uid,
          name: name,
          email: email,
        );
      }

      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = result.user;

      if (user != null) {
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

        await DatabaseService.instance.saveUserProfile(
          uid: user.uid,
          name: user.displayName ?? 'CrayCare User',
          email: user.email ?? '',
          photoUrl: profile?['photoUrl'] as String?,
        );
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      final user = userCredential.user;
      if (user != null) {
        final profile = await DatabaseService.instance.getUserProfile(user.uid);
        if (profile != null && profile['status'] == 'disabled') {
          await signOut();
          throw Exception('Your account has been disabled. Please contact the administrator.');
        }

        await DatabaseService.instance.saveUserProfile(
          uid: user.uid,
          name: user.displayName ?? 'Google User',
          email: user.email ?? '',
          photoUrl: profile?['photoUrl'] as String?,
        );
      }

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user logged in.');

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
