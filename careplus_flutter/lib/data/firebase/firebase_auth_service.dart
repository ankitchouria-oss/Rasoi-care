import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';

/// Real phone-OTP auth via Firebase. Only ever constructed after
/// `Firebase.initializeApp()` has succeeded — see main.dart.
class FirebaseAuthService implements AuthService {
  final _auth = FirebaseAuth.instance;

  @override
  bool get isLive => true;

  @override
  bool get isSignedIn => _auth.currentUser != null;

  @override
  Future<OtpSent> sendOtp(String e164Phone) {
    final completer = Completer<OtpSent>();
    _auth.verifyPhoneNumber(
      phoneNumber: e164Phone,
      timeout: const Duration(seconds: 60),
      // Some Android devices can verify without the user typing anything
      // (SMS Retriever / instant verification). When that happens we sign
      // in immediately and hand back a synthetic "already done" id so the
      // OTP screen can skip straight past.
      verificationCompleted: (credential) async {
        try {
          await _auth.signInWithCredential(credential);
          if (!completer.isCompleted) completer.complete(const OtpSent('auto-verified'));
        } catch (e) {
          if (!completer.isCompleted) {
            completer.completeError(AuthException(_friendly(e)));
          }
        }
      },
      verificationFailed: (e) {
        if (!completer.isCompleted) {
          completer.completeError(AuthException(_friendly(e)));
        }
      },
      codeSent: (verificationId, _) {
        if (!completer.isCompleted) completer.complete(OtpSent(verificationId));
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return completer.future;
  }

  @override
  Future<void> verifyOtp({required String verificationId, required String smsCode}) async {
    if (verificationId == 'auto-verified') return; // already signed in above
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendly(e));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  String _friendly(Object e) {
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-verification-code' => 'That code doesn\'t match. Check and try again.',
        'invalid-phone-number' => 'That doesn\'t look like a valid phone number.',
        'too-many-requests' => 'Too many attempts — wait a bit before retrying.',
        'session-expired' => 'That code expired. Request a new one.',
        _ => e.message ?? 'Something went wrong verifying that number.',
      };
    }
    return 'Something went wrong verifying that number.';
  }
}
