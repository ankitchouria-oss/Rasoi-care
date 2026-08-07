import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_service.dart';
import '../data/auth/mock_auth_service.dart';

/// Swap this for a real AuthService once the partner app is wired to a real
/// technician-auth backend — see lib/data/auth/auth_service.dart.
final authServiceProvider = Provider<AuthService>((ref) => MockAuthService());

class AuthFlowState {
  const AuthFlowState({
    this.phone = '',
    this.verificationId,
    this.sending = false,
    this.verifying = false,
    this.error,
  });
  final String phone;
  final String? verificationId;
  final bool sending;
  final bool verifying;
  final String? error;

  AuthFlowState copyWith({
    String? phone,
    String? verificationId,
    bool? sending,
    bool? verifying,
    String? error,
    bool clearError = false,
  }) =>
      AuthFlowState(
        phone: phone ?? this.phone,
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
