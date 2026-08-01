import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/auth_providers.dart';
import '../../data/auth/mock_auth_service.dart';

// ============================================================ SPLASH
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1600), () {
      if (mounted) context.go('/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CareColors.pine,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CareDial(
              value: 0.78,
              size: 110,
              color: CareColors.brass,
              trackColor: const Color(0x33F6F4EF),
              child: const Icon(Icons.insights_outlined, color: CareColors.porcelain, size: 34),
            ),
            const SizedBox(height: 26),
            Text('Rasoi Care', style: CareType.display(CareColors.porcelain, size: 34)),
            Text('ADMIN',
                style: CareType.mono(CareColors.brass, size: 13)
                    .copyWith(letterSpacing: 4, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            Text('OPERATIONS · ANALYTICS · REPORTS',
                textAlign: TextAlign.center,
                style: CareType.mono(CareColors.porcelain.withValues(alpha: 0.6), size: 10)
                    .copyWith(letterSpacing: 2.2, height: 1.6)),
          ],
        ),
      ),
    );
  }
}

// ============================================================ PHONE
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});
  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phoneCtrl = TextEditingController(text: '9822041537');

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a 10-digit mobile number.')));
      return;
    }
    final ok = await ref.read(authFlowProvider.notifier).sendOtp(digits);
    if (!mounted) return;
    if (ok) {
      context.push('/login/otp');
    } else {
      final err = ref.read(authFlowProvider).error ?? 'Could not send a code.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sending = ref.watch(authFlowProvider.select((s) => s.sending));
    final role = ref.watch(authFlowProvider.select((s) => s.role));
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CareDial(
                value: 1,
                size: 54,
                stroke: 5,
                showTicks: false,
                child: Icon(Icons.insights_outlined, color: context.scheme.primary, size: 22),
              ),
              const SizedBox(height: 26),
              Text('Rasoi Care Admin', style: context.type.headlineLarge),
              const SizedBox(height: 10),
              Text(
                  "Sign in with your registered mobile number. We'll text you a one-time code.",
                  style: context.type.bodyMedium),
              const SizedBox(height: 24),
              Eyebrow('Signing in as'),
              const SizedBox(height: 10),
              _RoleToggle(
                role: role,
                onChanged: (r) => ref.read(authFlowProvider.notifier).setRole(r),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  CareCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    child: const Text('🇮🇳 +91',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CareField('Mobile number',
                        controller: _phoneCtrl, keyboardType: TextInputType.phone),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: sending ? null : _send,
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send code'),
                ),
              ),
              const SizedBox(height: 22),
              CareCard(
                color: context.scheme.surfaceContainerHigh,
                borderColor: Colors.transparent,
                child: Row(children: [
                  const Text('🔐', style: TextStyle(fontSize: 17)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        'Owner sees financials and staff access. Staff members get operations and reports without payout detail.',
                        style: context.type.bodySmall),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleToggle extends StatelessWidget {
  const _RoleToggle({required this.role, required this.onChanged});
  final AdminRole role;
  final ValueChanged<AdminRole> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: context.scheme.surfaceContainerHigh, borderRadius: Radii.rSm),
        child: Row(
          children: [
            for (final r in AdminRole.values)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(r),
                  child: AnimatedContainer(
                    duration: Motion.press,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: r == role ? context.scheme.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: r == role
                          ? Shadows.card(Theme.of(context).brightness == Brightness.dark)
                          : null,
                    ),
                    child: Text(r.label,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: r == role
                                ? context.scheme.onSurface
                                : context.care.inkMuted)),
                  ),
                ),
              ),
          ],
        ),
      );
}

// ============================================================ OTP
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _shown = <String>['', '', '', ''];
  int _secs = 24;
  Timer? _t;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secs == 0) return;
      setState(() => _secs--);
    });
    const code = MockAuthService.demoCode;
    for (var i = 0; i < 4; i++) {
      Timer(Duration(milliseconds: 420 + i * 230), () {
        if (mounted) setState(() => _shown[i] = code[i]);
        if (i == 3) _submit();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_verifying || _shown.any((d) => d.isEmpty)) return;
    setState(() => _verifying = true);
    final ok = await ref.read(authFlowProvider.notifier).verifyOtp(_shown.join());
    if (!mounted) return;
    setState(() => _verifying = false);
    if (ok) {
      context.go('/dashboard');
    } else {
      final err = ref.read(authFlowProvider).error ?? 'Verification failed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      setState(() {
        for (var i = 0; i < _shown.length; i++) {
          _shown[i] = '';
        }
      });
    }
  }

  Future<void> _resend() async {
    if (_secs > 0) return;
    final phone = ref.read(authFlowProvider).phone;
    setState(() => _secs = 24);
    await ref.read(authFlowProvider.notifier).sendOtp(phone);
  }

  @override
  Widget build(BuildContext context) {
    final phone = ref.watch(authFlowProvider.select((s) => s.phone));
    final role = ref.watch(authFlowProvider.select((s) => s.role));
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: context.pop)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enter the code', style: context.type.headlineLarge),
                    const SizedBox(height: 10),
                    Text(
                        phone.isEmpty
                            ? 'Enter the 4-digit code we sent.'
                            : 'Sent to +91 $phone · signing in as ${role.label}.',
                        style: context.type.bodyMedium),
                    const SizedBox(height: 34),
                    Row(
                      children: [
                        for (var i = 0; i < 4; i++) ...[
                          Expanded(
                            child: AnimatedContainer(
                              duration: Motion.press,
                              height: 64,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: context.scheme.surface,
                                borderRadius: Radii.rMd,
                                border: Border.all(
                                    color: _shown[i].isEmpty
                                        ? context.care.hairline
                                        : context.scheme.primary,
                                    width: 1.5),
                              ),
                              child: Text(_shown[i],
                                  style: CareType.mono(context.scheme.onSurface,
                                      size: 24, w: FontWeight.w600)),
                            ),
                          ),
                          if (i != 3) const SizedBox(width: 11),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                        _verifying
                            ? 'Verifying…'
                            : (_shown.last.isEmpty
                                ? 'Auto-reading SMS…'
                                : 'Code read from SMS.'),
                        style: context.type.bodySmall),
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Didn't get it?", style: context.type.bodySmall),
                        GestureDetector(
                          onTap: _resend,
                          child: Mono(
                              _secs > 0
                                  ? 'Resend in 0:${_secs.toString().padLeft(2, '0')}'
                                  : 'Resend code',
                              color: context.scheme.secondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    CareCard(
                      color: context.scheme.primaryContainer,
                      borderColor: Colors.transparent,
                      child: Row(children: [
                        const Text('🔒', style: TextStyle(fontSize: 17)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                              'Rasoi Care Admin never asks for your OTP over a call. Share it only inside this app.',
                              style: context.type.bodySmall),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _verifying ? null : _submit,
                  child: _verifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Verify'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
