import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'database_service.dart';
import '../firebase_options.dart';

String authErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please sign in instead.';
      case 'weak-password':
        return 'Use a stronger password with at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return 'Incorrect email or password.';
      case 'email-not-verified':
        return 'Please verify your email before signing in.';
      case 'user-disabled':
        return 'Your account has been disabled. Please contact the administrator.';
      case 'network-request-failed':
        return 'Unable to connect. Check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment before trying again.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email. Sign in using its original method.';
      case 'operation-not-allowed':
        return 'This sign-in method is currently unavailable.';
    }
    if (error.message?.trim().isNotEmpty == true) return error.message!.trim();
  }
  return error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst(RegExp(r'^\[firebase_auth/[^\]]+\]\s*'), '')
      .trim();
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: DefaultFirebaseOptions.currentPlatform.iosClientId,
  );
  Map<String, dynamic>? _lastAuthenticatedProfile;
  Map<String, dynamic>? _lastAdminBootstrapData;

  Map<String, dynamic>? get lastAuthenticatedProfile =>
      _lastAuthenticatedProfile;
  Map<String, dynamic>? get lastAdminBootstrapData => _lastAdminBootstrapData;

  Stream<User?> get user => _auth.authStateChanges();

  bool _isDisabled(Map<String, dynamic>? profile) =>
      profile?['status']?.toString().trim().toLowerCase() == 'disabled';

  bool _isTransientProvisioningError(Object error) {
    if (error is! FirebaseException) return false;
    return const {
      'aborted',
      'deadline-exceeded',
      'permission-denied',
      'unavailable',
    }.contains(error.code);
  }

  /// Authentication state listeners start as soon as Firebase signs a user
  /// in. Give idempotent profile/tank provisioning a short retry window so a
  /// first-time account is never forced to press Google sign-in twice because
  /// another listener briefly observed the account before setup completed.
  Future<Map<String, dynamic>> _prepareCurrentUserAfterSignIn() async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await prepareCurrentUser();
      } catch (error) {
        lastError = error;
        if (!_isTransientProvisioningError(error) || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    throw lastError!;
  }

  /// Validates status and idempotently repairs the Firestore profile and
  /// notification defaults. Tank resources remain exclusive to Tank Setup.
  /// Used after authentication and after email verification.
  Future<Map<String, dynamic>> prepareCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Your session has expired. Please sign in again.',
      );
    }

    var profile = await DatabaseService.instance.getUserProfile(user.uid);
    if (_isDisabled(profile)) {
      await signOut();
      throw FirebaseAuthException(code: 'user-disabled');
    }

    await DatabaseService.instance.saveUserProfile(
      uid: user.uid,
      name: user.displayName?.trim().isNotEmpty == true
          ? user.displayName!.trim()
          : (profile?['full_name']?.toString().trim().isNotEmpty == true
                ? profile!['full_name'].toString().trim()
                : 'CrayCare User'),
      email: user.email ?? profile?['email']?.toString() ?? '',
      role: profile == null || profile['role'] == null ? 'owner' : null,
      status: profile == null || profile['status'] == null ? 'active' : null,
    );

    profile = await DatabaseService.instance.getUserProfile(user.uid);
    if (_isDisabled(profile)) {
      await signOut();
      throw FirebaseAuthException(code: 'user-disabled');
    }

    _lastAuthenticatedProfile = {
      ...?profile,
      'role': profile?['role'] ?? 'owner',
      'status': profile?['status'] ?? 'active',
    };
    _lastAdminBootstrapData =
        _lastAuthenticatedProfile!['role'] == 'admin'
        ? await DatabaseService.instance.getAdminBootstrapData()
        : null;
    return _lastAuthenticatedProfile!;
  }

  Future<User?> signUp(String name, String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = result.user;

      if (user != null) {
        await user.updateDisplayName(name);
        await _prepareCurrentUserAfterSignIn();
        if (!user.emailVerified) {
          try {
            await user.sendEmailVerification();
          } on FirebaseAuthException catch (e) {
            // Account/profile creation succeeded. VerifyScreen can safely
            // resend, so a temporary email-delivery throttle must not turn a
            // successful signup into a misleading failure.
            debugPrint('[AuthService] Initial verification email: ${e.code}');
          }
        }
      }

      return user;
    } on FirebaseAuthException {
      rethrow;
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
        if (_isDisabled(profile)) {
          await signOut();
          throw FirebaseAuthException(code: 'user-disabled');
        }

        if (!user.emailVerified) {
          // Keep this authenticated session alive so VerifyScreen can reload
          // the user and resend the verification email when needed.
          throw FirebaseAuthException(
            code: 'email-not-verified',
            message: 'Please verify your email before signing in.',
          );
        }
        await _prepareCurrentUserAfterSignIn();
      }
      return user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<User?> signInWithGoogle({VoidCallback? onAccountSelected}) async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      }
      onAccountSelected?.call();

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
        await _prepareCurrentUserAfterSignIn();
      }

      return userCredential.user;
    } on FirebaseAuthException {
      if (_auth.currentUser != null) {
        await _googleSignIn.signOut();
        await _auth.signOut();
      }
      rethrow;
    } catch (e) {
      if (_auth.currentUser != null) {
        await _googleSignIn.signOut();
        await _auth.signOut();
      }
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

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

    if (!hasEmailProvider) {
      throw Exception('Your password is managed through your Google account.');
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw FirebaseAuthException(
          code: e.code,
          message:
              'Your session is too old to change your password. '
              'Please log out and log back in, then try again.',
        );
      }
      rethrow;
    }

    await user.updatePassword(newPassword);
  }

  Future<void> createPasswordForCurrentUser({
    required String email,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No user logged in.');

    final hasEmailProvider = user.providerData.any(
      (info) => info.providerId == 'password',
    );
    if (hasEmailProvider) {
      throw Exception(
        'This account already has a password. Use Change Password instead.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: newPassword,
    );
    await user.linkWithCredential(credential);
  }

  Future<void> signOut() async {
    _lastAuthenticatedProfile = null;
    _lastAdminBootstrapData = null;
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        // Remove only this device's token so other logged-in devices keep
        // receiving push notifications.
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          final userRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid);
          final snap = await userRef.get();
          final updates = <String, dynamic>{
            'fcmTokens': FieldValue.arrayRemove([token]),
          };
          if (snap.data()?['fcmToken'] == token) {
            updates['fcmToken'] = FieldValue.delete();
          }
          await userRef.update(updates);
        }
      } catch (e) {
        debugPrint('[AuthService] Failed to clear FCM token on signout: $e');
      }
    }
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
