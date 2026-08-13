import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/backend_client.dart';
import '../data/firebase/auth_service.dart';
import '../data/firebase/firebase_auth_service.dart';
import '../data/firebase/mock_auth_service.dart';

/// Picks the real service if `Firebase.initializeApp()` succeeded in
/// main.dart, otherwise the mock. This is the one line you'd ever need to
/// force a particular mode (e.g. for a demo) — override it in a test harness
/// via `ProviderScope(overrides: [authServiceProvider.overrideWithValue(...)])`.
final authServiceProvider = Provider<AuthService>(
  (ref) => Firebase.apps.isEmpty ? MockAuthService() : FirebaseAuthService(),
);

class AuthFlowState {
  const AuthFlowState({
    this.phone = '',
    this.verificationId,
    this.sending = false,
    this.verifying = false,
    this.submitting = false,
    this.error,
  });
  final String phone;
  final String? verificationId;
  final bool sending;
  final bool verifying;
  /// Covers email/password and Google sign-in — separate from [sending]/
  /// [verifying], which are phone-OTP-specific, so the two flows' spinners
  /// never fight over the same flag.
  final bool submitting;
  final String? error;

  AuthFlowState copyWith({
    String? phone,
    String? verificationId,
    bool? sending,
    bool? verifying,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) =>
      AuthFlowState(
        phone: phone ?? this.phone,
        verificationId: verificationId ?? this.verificationId,
        sending: sending ?? this.sending,
        verifying: verifying ?? this.verifying,
        submitting: submitting ?? this.submitting,
        error: clearError ? null : (error ?? this.error),
      );
}

final authFlowProvider =
    NotifierProvider<AuthFlowVM, AuthFlowState>(AuthFlowVM.new);

class AuthFlowVM extends Notifier<AuthFlowState> {
  @override
  AuthFlowState build() => const AuthFlowState();

  /// True when running against the mock — the OTP screen uses this to decide
  /// whether to show the simulated SMS auto-fill (mock only; real SMS
  /// auto-fill requires platform-level SMS Retriever wiring not included here).
  bool get isMock => !ref.read(authServiceProvider).isLive;

  Future<bool> sendOtp(String tenDigitPhone) async {
    state = state.copyWith(sending: true, clearError: true, phone: tenDigitPhone);
    try {
      final result = await ref.read(authServiceProvider).sendOtp('+91$tenDigitPhone');
      state = state.copyWith(sending: false, verificationId: result.verificationId);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(sending: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
          sending: false, error: 'Could not send a code right now. Try again.');
      return false;
    }
  }

  Future<bool> verifyOtp(String code) async {
    final vid = state.verificationId;
    if (vid == null) {
      state = state.copyWith(error: 'Request a code first.');
      return false;
    }
    state = state.copyWith(verifying: true, clearError: true);
    try {
      await ref.read(authServiceProvider).verifyOtp(verificationId: vid, smsCode: code);
      _bootstrapBackend();
      state = state.copyWith(verifying: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(verifying: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(verifying: false, error: 'Verification failed. Try again.');
      return false;
    }
  }

  Future<bool> registerWithEmail(String email, String password) =>
      _submit(() => ref.read(authServiceProvider).registerWithEmail(email: email, password: password));

  Future<bool> signInWithEmail(String email, String password) =>
      _submit(() => ref.read(authServiceProvider).signInWithEmail(email: email, password: password));

  Future<bool> signInWithGoogle() =>
      _submit(() => ref.read(authServiceProvider).signInWithGoogle());

  Future<bool> _submit(Future<void> Function() action) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      await action();
      _bootstrapBackend();
      state = state.copyWith(submitting: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(submitting: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(submitting: false, error: 'Something went wrong. Try again.');
      return false;
    }
  }

  void reset() => state = const AuthFlowState();

  /// Best-effort POST to the backend right after any successful sign-in
  /// (register, email/password, Google, or phone OTP) so it has a matching
  /// `users` row — see bootstrap_customer in app.py. Fire-and-forget, same
  /// pattern as UserProfileService's Firestore write-through in
  /// firestore_user_profile_service.dart: never blocks getting into the
  /// app, and a no-op in mock mode (no Firebase project configured yet).
  void _bootstrapBackend() {
    if (Firebase.apps.isEmpty) return;
    unawaited(_doBootstrapBackend());
  }

  Future<void> _doBootstrapBackend() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      if (idToken == null) return;
      await BackendClient().bootstrap(
        idToken: idToken,
        name: user.displayName ?? user.email ?? 'Customer',
      );
    } catch (_) {
      // Best-effort — never blocks sign-in.
    }
  }
}
