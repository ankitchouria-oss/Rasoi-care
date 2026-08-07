import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_service.dart';
import '../data/auth/mock_auth_service.dart';
import '../data/models.dart';

/// Swap this for a real AuthService once this app is wired to a real staff
/// directory — see lib/data/auth/auth_service.dart.
final authServiceProvider = Provider<AuthService>((ref) => MockAuthService());

class AuthFlowState {
  const AuthFlowState({
    this.phone = '',
    this.role = AdminRole.owner,
    this.verificationId,
    this.sending = false,
    this.verifying = false,
    this.error,
  });
  final String phone;
  final AdminRole role;
  final String? verificationId;
  final bool sending;
  final bool verifying;
  final String? error;

  AuthFlowState copyWith({
    String? phone,
    AdminRole? role,
    String? verificationId,
    bool? sending,
    bool? verifying,
    String? error,
    bool clearError = false,
  }) =>
      AuthFlowState(
        phone: phone ?? this.phone,
        role: role ?? this.role,
        verificationId: verificationId ?? this.verificationId,
        sending: sending ?? this.sending,
        verifying: verifying ?? this.verifying,
        error: clearError ? null : (error ?? this.error),
      );
}

final authFlowProvider =
    NotifierProvider<AuthFlowVM, AuthFlowState>(AuthFlowVM.new);

class AuthFlowVM extends Notifier<AuthFlowState> {
  @override
  AuthFlowState build() => const AuthFlowState();

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
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(verifying: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(verifying: false, error: 'Verification failed. Try again.');
      return false;
    }
  }

  void reset() => state = const AuthFlowState();
}

/// The signed-in role, valid once auth completes. Screens gate owner-only
/// sections on this.
final currentRoleProvider = Provider<AdminRole>((ref) => ref.watch(authFlowProvider).role);
