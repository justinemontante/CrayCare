import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
        // I-save ang Full Name sa Firebase Profile
        await user.updateDisplayName(name);

        // Mag-send ng Verification Email
        if (!user.emailVerified) {
          await user.sendEmailVerification();
        }
        // Save profile to RTDB for a record (preserve existing photoUrl kung mayron)
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

  // SIGN IN
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = result.user;

      if (user != null && !user.emailVerified) {
        await _auth.signOut();
        throw Exception(
          'Please verify your email first. A verification link was sent to your inbox.',
        );
      }
      // Para sa mga existing users — i-save sa RTDB (preserve photoUrl)
      if (user != null && user.emailVerified) {
        final existing = await DatabaseService.instance.getUserProfile(user.uid);
        await DatabaseService.instance.saveUserProfile(
          uid: user.uid,
          name: user.displayName ?? 'CrayCare User',
          email: user.email ?? '',
          photoUrl: existing?['photoUrl'] as String?,
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
        // Kunin muna ang existing profile para hindi mawala ang photoUrl
        final existing = await DatabaseService.instance.getUserProfile(user.uid);
        await DatabaseService.instance.saveUserProfile(
          uid: user.uid,
          name: user.displayName ?? 'Google User',
          email: user.email ?? '',
          photoUrl: existing?['photoUrl'] as String?,
        );
      }

      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // SIGN OUT
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
