import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fingerprint/face unlock, offered once right after sign-up (see the
/// post-signup prompt in RegisterScreen) and then used to gate reopening the
/// app when enabled (see SplashScreen). Wraps both the OS-level prompt
/// (local_auth) and the persisted "did this person turn it on" flag —
/// nothing here is enabled by default, and a device with no enrolled
/// fingerprint/face just never gets offered the toggle.
class BiometricService {
  static const _enabledKey = 'biometric_login_enabled';
  static const _promptedKey = 'biometric_login_prompted';
  final LocalAuthentication _auth = LocalAuthentication();

  /// Whether this device actually has usable biometric hardware with at
  /// least one fingerprint/face enrolled right now — checked before ever
  /// showing the opt-in prompt or the settings toggle.
  Future<bool> isDeviceSupported() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck && supported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Whether the one-time "turn on biometric login?" prompt has already
  /// been shown on this device — true whether they enabled it or declined,
  /// so it's only ever offered once instead of nagging every sign-in.
  Future<bool> hasPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_promptedKey) ?? false;
  }

  Future<void> setPrompted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptedKey, value);
  }

  /// Shows the OS fingerprint/face prompt. Returns true only on a real
  /// match — any error, user cancel, or lockout returns false so callers
  /// can fall back to the normal OTP sign-in instead.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
