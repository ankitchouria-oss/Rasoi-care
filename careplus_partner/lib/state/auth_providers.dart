import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/api/api_config.dart';
import '../data/auth/auth_service.dart';
import '../data/auth/firebase_auth_service.dart';
import '../data/auth/mock_auth_service.dart';
import '../data/firestore/technician_profile_service.dart';

/// Picks the real service if `Firebase.initializeApp()` succeeded in
/// main.dart, otherwise the mock.
final authServiceProvider = Provider<AuthService>(
  (ref) => Firebase.apps.isEmpty ? MockAuthService() : FirebaseAuthService(),
);

final technicianProfileServiceProvider =
    Provider<TechnicianProfileService>((ref) => TechnicianProfileService());

/// Best-effort call to the real backend right after a successful sign-in,
/// mirroring [TechnicianProfileService.touchProfile]'s "never block getting
/// into the job feed" spirit: in mock mode, or if the request fails for any
/// reason (backend not deployed yet, timeout, network error), this is a
/// silent no-op. A self-bootstrapped technician starts unverified/offline
/// server-side until an admin verifies them — real jobs won't route to them
/// until then, which is expected.
Future<void> _bootstrapTechnicianBackend() async {
  if (Firebase.apps.isEmpty) return; // mock mode — no backend to bootstrap
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  try {
    final token = await user.getIdToken();
    if (token == null) return;
    final name = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? user.phoneNumber ?? 'Technician');
    await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/technician/bootstrap'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          // The registration screens here don't collect a trade category or
          // service area today (see auth_screens.dart) — default both, same
          // as the backend does when they're omitted.
          body: jsonEncode({'name': name, 'category': 'RasoiSpark', 'area': ''}),
        )
        .timeout(const Duration(seconds: 8));
  } catch (_) {
    // Backend unreachable or not deployed yet — never blocks sign-in.
  }
}

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
  /// [verifying], which are phone-OTP-specific.
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
  /// whether to show the simulated SMS auto-fill (mock only).
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
      state = state.copyWith(verifying: false);
      unawaited(ref.read(technicianProfileServiceProvider).touchProfile());
      unawaited(_bootstrapTechnicianBackend());
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(verifying: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(verifying: false, error: 'Verification failed. Try again.');
      return false;
    }
  }

  Future<bool> registerWithEmail(String email, String password) => _submit(
      () => ref.read(authServiceProvider).registerWithEmail(email: email, password: password));

  Future<bool> signInWithEmail(String email, String password) => _submit(
      () => ref.read(authServiceProvider).signInWithEmail(email: email, password: password));

  Future<bool> signInWithGoogle() =>
      _submit(() => ref.read(authServiceProvider).signInWithGoogle());

  Future<bool> _submit(Future<void> Function() action) async {
    state = state.copyWith(submitting: true, clearError: true);
    try {
      await action();
      state = state.copyWith(submitting: false);
      unawaited(ref.read(technicianProfileServiceProvider).touchProfile());
      unawaited(_bootstrapTechnicianBackend());
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
}
