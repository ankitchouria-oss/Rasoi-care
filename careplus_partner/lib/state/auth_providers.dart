import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../data/api/api_config.dart';
import '../data/auth/auth_service.dart';
import '../data/auth/firebase_auth_service.dart';
import '../data/auth/mock_auth_service.dart';
import '../data/firestore/technician_profile_service.dart';
import '../data/firebase/technician_upload_service.dart';

/// Picks the real service if `Firebase.initializeApp()` succeeded in
/// main.dart, otherwise the mock.
final authServiceProvider = Provider<AuthService>(
  (ref) => Firebase.apps.isEmpty ? MockAuthService() : FirebaseAuthService(),
);

final technicianProfileServiceProvider =
    Provider<TechnicianProfileService>((ref) => TechnicianProfileService());

final technicianUploadServiceProvider =
    Provider<TechnicianUploadService>((ref) => TechnicianUploadService());

/// Where the signed-in technician should land — decided from the real
/// backend record (`applicationSubmitted`/`verified`, see app.py's
/// technician_row_to_dict), modelled on Urban Company's partner flow: fill
/// in your profile/documents/bank details, then wait for verification
/// before you can go online for jobs.
enum TechnicianStage { apply, pending, jobs }

/// Best-effort call to the real backend right after a successful sign-in
/// (or app resume, from SplashScreen), mirroring
/// [TechnicianProfileService.touchProfile]'s "never block" spirit: in mock
/// mode, or if the request fails for any reason (backend not deployed yet,
/// timeout, network error), this returns null and callers fall back to
/// [TechnicianStage.jobs] — the original single-step mock flow.
Future<Map<String, dynamic>?> bootstrapTechnicianBackend() async {
  if (Firebase.apps.isEmpty) return null; // mock mode — no backend to bootstrap
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  try {
    final token = await user.getIdToken();
    if (token == null) return null;
    final name = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? user.phoneNumber ?? 'Technician');
    final res = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/api/technician/bootstrap'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'name': name}),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null; // Backend unreachable or not deployed yet — never blocks sign-in.
  }
}

/// Re-checks status without re-bootstrapping — used by SplashScreen for a
/// returning technician, and by the "pending review" screen's refresh
/// action, via the technician's own already-issued Firebase token.
Future<Map<String, dynamic>?> fetchTechnicianMe() async {
  if (Firebase.apps.isEmpty) return null;
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  try {
    final token = await user.getIdToken();
    if (token == null) return null;
    final res = await http
        .get(
          Uri.parse('${ApiConfig.baseUrl}/api/technician/me'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Submits (or partially updates) the technician's KYC application —
/// called by TechApplyScreen. Unlike [bootstrapTechnicianBackend]/
/// [fetchTechnicianMe], this is a primary action the person is actively
/// waiting on, so it throws a real [AuthException] instead of silently
/// swallowing failures.
Future<Map<String, dynamic>> submitTechnicianApplication(
  Map<String, dynamic> fields,
) async {
  if (Firebase.apps.isEmpty) {
    throw const AuthException('Not available in demo mode.');
  }
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw const AuthException('Not signed in.');
  final token = await user.getIdToken();
  if (token == null) throw const AuthException('Not signed in.');
  try {
    final res = await http
        .patch(
          Uri.parse('${ApiConfig.baseUrl}/api/technician/me'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(fields),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw const AuthException('Could not submit — check your connection and try again.');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const AuthException('Unexpected response — try again.');
    }
    return decoded;
  } on AuthException {
    rethrow;
  } catch (_) {
    throw const AuthException('Could not submit — check your connection and try again.');
  }
}

TechnicianStage stageFromTechnicianJson(Map<String, dynamic>? json) {
  if (json == null) return TechnicianStage.jobs; // mock mode / unreachable backend
  if (json['applicationSubmitted'] != true) return TechnicianStage.apply;
  if (json['verified'] != true) return TechnicianStage.pending;
  return TechnicianStage.jobs;
}

/// Routes a just-signed-in (or just-resumed) technician to wherever their
/// real application status says they belong.
void routeToStage(BuildContext context, TechnicianStage stage) {
  switch (stage) {
    case TechnicianStage.apply:
      context.go('/tech/apply');
    case TechnicianStage.pending:
      context.go('/tech/pending');
    case TechnicianStage.jobs:
      context.go('/tech/jobs');
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
    this.stage = TechnicianStage.jobs,
  });
  final String phone;
  final String? verificationId;
  final bool sending;
  final bool verifying;
  /// Covers email/password and Google sign-in — separate from [sending]/
  /// [verifying], which are phone-OTP-specific.
  final bool submitting;
  final String? error;
  /// Where to route after a successful sign-in — set from the bootstrap
  /// response, see [bootstrapTechnicianBackend].
  final TechnicianStage stage;

  AuthFlowState copyWith({
    String? phone,
    String? verificationId,
    bool? sending,
    bool? verifying,
    bool? submitting,
    String? error,
    bool clearError = false,
    TechnicianStage? stage,
  }) =>
      AuthFlowState(
        phone: phone ?? this.phone,
        verificationId: verificationId ?? this.verificationId,
        sending: sending ?? this.sending,
        verifying: verifying ?? this.verifying,
        submitting: submitting ?? this.submitting,
        error: clearError ? null : (error ?? this.error),
        stage: stage ?? this.stage,
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
      unawaited(ref.read(technicianProfileServiceProvider).touchProfile());
      final tech = await bootstrapTechnicianBackend();
      state = state.copyWith(verifying: false, stage: stageFromTechnicianJson(tech));
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
      unawaited(ref.read(technicianProfileServiceProvider).touchProfile());
      final tech = await bootstrapTechnicianBackend();
      state = state.copyWith(submitting: false, stage: stageFromTechnicianJson(tech));
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
