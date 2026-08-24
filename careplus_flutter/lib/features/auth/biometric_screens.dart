import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/care_plus_theme.dart';
import '../../state/auth_providers.dart';
import '../../state/providers.dart';

/// Shown once, right after sign-up finishes — offers to turn on
/// fingerprint/face unlock for next time. Only reached when the device
/// actually has usable biometric hardware, so there's no "no fingerprint
/// enrolled" dead end here. Marks itself as shown the moment it appears, so
/// it's never offered a second time whether someone enables it or skips it.
class BiometricEnrollScreen extends ConsumerStatefulWidget {
  const BiometricEnrollScreen({this.nextRoute = '/', super.key});

  /// Where to land once this screen is done, either way.
  final String nextRoute;

  @override
  ConsumerState<BiometricEnrollScreen> createState() => _BiometricEnrollScreenState();
}

class _BiometricEnrollScreenState extends ConsumerState<BiometricEnrollScreen> {
  bool _working = false;

  @override
  void initState() {
    super.initState();
    ref.read(biometricServiceProvider).setPrompted(true);
  }

  Future<void> _enable() async {
    setState(() => _working = true);
    final ok = await ref
        .read(biometricServiceProvider)
        .authenticate('Confirm your fingerprint or face to turn on biometric login');
    if (!mounted) return;
    if (ok) {
      await ref.read(biometricEnabledProvider.notifier).set(true);
      if (!mounted) return;
      context.go(widget.nextRoute);
    } else {
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't verify — you can turn this on later in settings.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.fingerprint, size: 64, color: context.scheme.primary),
              const SizedBox(height: 24),
              Text('Unlock with a touch or a glance',
                  style: CareType.display(context.scheme.onSurface, size: 26)),
              const SizedBox(height: 12),
              Text(
                'Turn on biometric login so you can get back into Rasoi Care '
                'with your fingerprint or face instead of an OTP every time.',
                style: context.type.bodyMedium!.copyWith(color: context.care.inkMuted),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _working ? null : _enable,
                  child: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Turn on biometric login'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _working ? null : () => context.go(widget.nextRoute),
                  child: const Text('Not now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gates a returning, already-signed-in session behind a fingerprint/face
/// check when biometric login is turned on — see SplashScreen. Signing out
/// is always offered as an escape hatch so a failed sensor never strands
/// anyone outside their own account.
class BiometricLockScreen extends ConsumerStatefulWidget {
  const BiometricLockScreen({super.key});
  @override
  ConsumerState<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends ConsumerState<BiometricLockScreen> {
  bool _working = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    setState(() {
      _working = true;
      _failed = false;
    });
    final ok = await ref
        .read(biometricServiceProvider)
        .authenticate('Verify it\'s you to open Rasoi Care');
    if (!mounted) return;
    if (ok) {
      context.go('/');
    } else {
      setState(() {
        _working = false;
        _failed = true;
      });
    }
  }

  Future<void> _signOut() async {
    await ref.read(authServiceProvider).signOut();
    ref.read(authFlowProvider.notifier).reset();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CareColors.pine,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fingerprint, size: 72, color: CareColors.porcelain),
            const SizedBox(height: 20),
            Text('Rasoi Care', style: CareType.display(CareColors.porcelain, size: 26)),
            const SizedBox(height: 8),
            Text(
              _failed ? 'Not recognised — try again' : 'Verify to continue',
              style: CareType.mono(CareColors.brass, size: 11).copyWith(letterSpacing: 1.2),
            ),
            const SizedBox(height: 28),
            if (_working)
              const CircularProgressIndicator(color: CareColors.brass)
            else
              FilledButton(
                onPressed: _unlock,
                child: const Text('Try again'),
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _working ? null : _signOut,
              child: const Text('Sign out instead', style: TextStyle(color: CareColors.porcelain)),
            ),
          ],
        ),
      ),
    );
  }
}
