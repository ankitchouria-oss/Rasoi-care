// The seam between the auth screens and whichever phone-auth backend is
// live. Swap MockAuthService for a real implementation (e.g. Firebase phone
// auth, matching careplus_flutter's lib/data/firebase/) when this app needs
// to verify a real technician roster — the screens only ever talk to
// AuthService, never to a backend directly.

/// Outcome of requesting an OTP.
class OtpSent {
  const OtpSent(this.verificationId);
  final String verificationId;
}

abstract interface class AuthService {
  /// Whether a user is currently signed in (checked once at app start).
  bool get isSignedIn;

  /// Sends the OTP. Throws an [AuthException] on failure.
  Future<OtpSent> sendOtp(String e164Phone);

  /// Verifies the code against the most recent [OtpSent.verificationId].
  /// Throws an [AuthException] if it doesn't match.
  Future<void> verifyOtp({required String verificationId, required String smsCode});

  Future<void> signOut();
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
