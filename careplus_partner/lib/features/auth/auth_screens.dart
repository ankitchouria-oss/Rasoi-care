import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_auth/smart_auth.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../state/auth_providers.dart';
import '../../data/auth/mock_auth_service.dart';

// ============================================================ SPLASH
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1600), () async {
      if (!ref.read(authServiceProvider).isSignedIn) {
        if (mounted) context.go('/login');
        return;
      }
      // Already signed in from a previous session — find out where they
      // actually belong (still applying, awaiting verification, or fully
      // onboarded) instead of always dropping them at the job feed.
      final tech = await fetchTechnicianMe();
      if (mounted) routeToStage(context, stageFromTechnicianJson(tech));
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
              child: const Icon(Icons.build_outlined, color: CareColors.porcelain, size: 34),
            ),
            const SizedBox(height: 26),
            Text('Rasoi Care', style: CareType.display(CareColors.porcelain, size: 34)),
            Text('PARTNER',
                style: CareType.mono(CareColors.brass, size: 13)
                    .copyWith(letterSpacing: 4, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            Text('FOR TECHNICIANS ON THE JOB',
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
//
// Single login path: mobile number + OTP is the only way in, and it's also
// the only way to create an account — a new number just gets bootstrapped a
// technician record on OTP verify (see bootstrapTechnicianBackend) and is
// routed to TechApplyScreen. The toggle below only changes the copy/button
// label to make that "new partner? enter your number to create an account"
// path visible on the starting page — both modes do the exact same OTP send.
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});
  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phoneCtrl = TextEditingController();
  bool _creatingAccount = false;

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
                child: Icon(Icons.build_outlined, color: context.scheme.primary, size: 22),
              ),
              const SizedBox(height: 26),
              Text(_creatingAccount ? 'Become a Rasoi Care partner' : 'Rasoi Care Partner',
                  style: context.type.headlineLarge),
              const SizedBox(height: 10),
              Text(
                  _creatingAccount
                      ? "Enter your mobile number to create your account. We'll text you a one-time code, then walk you through your profile."
                      : "Sign in with your mobile number. We'll text you a one-time code.",
                  style: context.type.bodyMedium),
              const SizedBox(height: 30),
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
                      : Text(_creatingAccount ? 'Create account' : 'Send code'),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: GestureDetector(
                  onTap: () => setState(() => _creatingAccount = !_creatingAccount),
                  child: Text(
                      _creatingAccount
                          ? 'Already a partner? Sign in'
                          : 'New here? Create an account',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.scheme.primary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================ OTP
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  // Firebase's real SMS codes are 6 digits; the mock demo code is 4.
  late final int _length = ref.read(authFlowProvider.notifier).isMock ? 4 : 6;
  late final _shown = List<String>.filled(_length, '');
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
    // Mock mode fakes SMS auto-read on a timer; live mode listens for the
    // real SMS via Android's User Consent API (no manifest permission
    // needed — the OS shows its own one-time "allow?" dialog).
    if (ref.read(authFlowProvider.notifier).isMock) {
      const code = MockAuthService.demoCode;
      for (var i = 0; i < _length; i++) {
        Timer(Duration(milliseconds: 420 + i * 230), () {
          if (mounted) setState(() => _shown[i] = code[i]);
          if (i == _length - 1) _submit();
        });
      }
    } else {
      _listenForSms();
    }
  }

  Future<void> _listenForSms() async {
    final result = await SmartAuth.instance.getSmsWithUserConsentApi();
    if (!mounted) return;
    final code = result.data?.code;
    if (code == null || code.length != _length) return;
    setState(() {
      for (var i = 0; i < _length; i++) {
        _shown[i] = code[i];
      }
    });
    _submit();
  }

  @override
  void dispose() {
    _t?.cancel();
    if (!ref.read(authFlowProvider.notifier).isMock) {
      SmartAuth.instance.removeUserConsentApiListener();
    }
    super.dispose();
  }

  void _onDigit(int i, String v) {
    setState(() => _shown[i] = v);
    if (_shown.every((d) => d.isNotEmpty)) _submit();
  }

  Future<void> _submit() async {
    if (_verifying || _shown.any((d) => d.isEmpty)) return;
    setState(() => _verifying = true);
    final ok = await ref.read(authFlowProvider.notifier).verifyOtp(_shown.join());
    if (!mounted) return;
    setState(() => _verifying = false);
    if (ok) {
      routeToStage(context, ref.read(authFlowProvider).stage);
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
    final isMock = ref.watch(authFlowProvider.notifier).isMock;
    final phone = ref.watch(authFlowProvider.select((s) => s.phone));
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
                            ? 'Enter the $_length-digit code we sent.'
                            : 'Sent to +91 $phone.',
                        style: context.type.bodyMedium),
                    const SizedBox(height: 34),
                    Row(
                      children: [
                        for (var i = 0; i < _length; i++) ...[
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
                              // Mock mode keeps the read-only auto-fill demo;
                              // live mode takes a real single-digit tap-type.
                              child: isMock
                                  ? Text(_shown[i],
                                      style: CareType.mono(context.scheme.onSurface,
                                          size: 24, w: FontWeight.w600))
                                  : TextField(
                                      textAlign: TextAlign.center,
                                      keyboardType: TextInputType.number,
                                      maxLength: 1,
                                      showCursor: false,
                                      decoration: const InputDecoration(
                                          counterText: '', border: InputBorder.none),
                                      style: CareType.mono(context.scheme.onSurface,
                                          size: 24, w: FontWeight.w600),
                                      onChanged: (v) => _onDigit(i, v),
                                    ),
                            ),
                          ),
                          if (i != _length - 1) const SizedBox(width: 11),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                        _verifying
                            ? 'Verifying…'
                            : isMock
                                ? (_shown.last.isEmpty ? 'Auto-reading SMS…' : 'Code read from SMS.')
                                : 'Enter the code from the SMS you received.',
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
                              'Rasoi Care never asks for your OTP over a call. Share it only inside this app.',
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

