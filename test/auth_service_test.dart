import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:craycare/services/auth_service.dart';

void main() {
  group('authentication error messages', () {
    test('keeps credential failures generic', () {
      expect(
        authErrorMessage(FirebaseAuthException(code: 'invalid-credential')),
        'Incorrect email or password.',
      );
      expect(
        authErrorMessage(FirebaseAuthException(code: 'user-not-found')),
        'Incorrect email or password.',
      );
    });

    test('explains disabled and unverified account states', () {
      expect(
        authErrorMessage(FirebaseAuthException(code: 'user-disabled')),
        contains('disabled'),
      );
      expect(
        authErrorMessage(FirebaseAuthException(code: 'email-not-verified')),
        contains('verify'),
      );
    });

    test('explains a Google provider conflict', () {
      expect(
        authErrorMessage(
          FirebaseAuthException(
            code: 'account-exists-with-different-credential',
          ),
        ),
        contains('original method'),
      );
    });
  });
}
