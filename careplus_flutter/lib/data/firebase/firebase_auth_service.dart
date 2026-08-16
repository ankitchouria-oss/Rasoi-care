import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth_service.dart';
import 'firebase_config.dart';

/// Real phone-OTP auth via Firebase. Only ever constructed after
/// `Firebase.initializeApp()` has succeeded — see main.dart.
class FirebaseAuthService implements AuthService {
  final _auth = FirebaseAuth.instance;

  @override
  bool get isLive => true;

  @override
  bool get isSignedIn => _auth.currentUser != null;

  @override
  String? get currentDisplayName => _auth.currentUser?.displayName;

  @override
  String? get currentEmail => _auth.currentUser?.email;

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
  Future<void> registerWithEmail({required String email, required String password}) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendly(e));
    }
  }

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendly(e));
    }
  }

  // A fresh instance per call rather than a field: GoogleSignIn holds on to
  // session state, and this keeps the sign-out path (below) simple — nothing
  // else in this class needs to reach it between calls.
  @override
  Future<void> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(
        // Only needed if you're also verifying Google identity on a backend
        // server; leave unset for client-only Firebase Auth. See
        // lib/data/firebase/firebase_config.dart.
        serverClientId: FirebaseConfig.googleServerClientId,
      );
      final account = await googleSignIn.signIn();
      if (account == null) {
        // Person closed the account picker — not an error, just cancelled.
        throw const AuthException('Sign-in cancelled.');
      }
      final googleAuth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw AuthException(_friendly(e));
    } on AuthException {
      rethrow;
    } catch (e) {
      // Temporarily surfacing the raw error while diagnosing a real device
      // issue — this used to be a generic, undiagnosable message here.
      // TODO: revert to a friendly generic message once Google sign-in is
      // confirmed working end-to-end.
      throw AuthException('Google sign-in failed: $e');
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    await GoogleSignIn().signOut();
  }

  String _friendly(Object e) {
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-verification-code' => 'That code doesn\'t match. Check and try again.',
        'invalid-phone-number' => 'That doesn\'t look like a valid phone number.',
        'too-many-requests' => 'Too many attempts — wait a bit before retrying.',
        'session-expired' => 'That code expired. Request a new one.',
        'email-already-in-use' => 'An account already exists with that email — try signing in instead.',
        'invalid-email' => 'That doesn\'t look like a valid email address.',
        'weak-password' => 'Choose a password with at least 6 characters.',
        'user-not-found' => 'No account found with that email.',
        'wrong-password' || 'invalid-credential' => 'Incorrect email or password.',
        'account-exists-with-different-credential' =>
          'That email is already linked to a different sign-in method.',
        _ => e.message ?? 'Something went wrong. Try again.',
      };
    }
    return 'Something went wrong. Try again.';
  }
}
