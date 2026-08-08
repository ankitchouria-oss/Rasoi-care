import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_service.dart';
import '../data/auth/firebase_auth_service.dart';
import '../data/auth/mock_auth_service.dart';
import '../data/firestore/staff_profile_service.dart';
import '../data/models.dart';

/// Picks the real service if `Firebase.initializeApp()` succeeded in
/// main.dart, otherwise the mock.
final authServiceProvider = Provider<AuthService>(
  (ref) => Firebase.apps.isEmpty ? MockAuthService() : FirebaseAuthService(),
);

final staffProfileServiceProvider =
    Provider<StaffProfileService>((ref) => StaffProfileService());

class AuthFlowState {
  const AuthFlowState({
    this.phone = '',
    this.role = AdminRole.owner,
    this.verificationId,
    this.sending = false,
    this.verifying = false,
    this.submitting = false,
    this.error,
  });
  final String phone;
  final AdminRole role;
  final String? verificationId;
  final bool sending;
  final bool verifying;
  /// Covers email/password and Google sign-in — separate from [sending]/
  /// [verifying], which are phone-OTP-specific.
  final bool submitting;
  final String? error;

  AuthFlowState copyWith({
    String? phone,
    AdminRole? role,
    String? verificationId,
    bool? sending,
    bool? verifying,
    bool? submitting,
    String? error,
    bool clearError = false,
  }) =>
      AuthFlowState(
        phone: phone ?? this.phone,
        role: role ?? this.role,
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

  void setRole(AdminRole role) => state = state.copyWith(role: role);

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
      unawaited(ref.read(staffProfileServiceProvider).touchProfile(role: state.role));
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
      unawaited(ref.read(staffProfileServiceProvider).touchProfile(role: state.role));
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

/// The signed-in role, valid once auth completes. Screens gate owner-only
/// sections on this.
final currentRoleProvider = Provider<AdminRole>((ref) => ref.watch(authFlowProvider).role);
