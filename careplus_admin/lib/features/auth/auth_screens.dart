import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_auth/smart_auth.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/auth/mock_auth_service.dart';
import '../../data/models.dart';
import '../../state/auth_providers.dart';

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

// ============================================================ PHONE
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});
  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phoneCtrl = TextEditingController();
  bool _googleBusy = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _continueWithGoogle() async {
    setState(() => _googleBusy = true);
    final ok = await ref.read(authFlowProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    setState(() => _googleBusy = false);
    if (ok) {
      context.go('/dashboard');
    } else {
      final err = ref.read(authFlowProvider).error;
      if (err != null && err != 'Sign-in cancelled.') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }
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
                  "Sign in with your mobile number. We'll text you a one-time code.",
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
              const SizedBox(height: 26),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Mono('OR', color: context.care.inkMuted)),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _googleBusy ? null : _continueWithGoogle,
                  child: _googleBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Continue with Google'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                    onPressed: () => context.push('/login/email'),
                    child: const Text('Continue with email')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================ EMAIL
class EmailAuthScreen extends ConsumerStatefulWidget {
  const EmailAuthScreen({super.key});
  @override
  ConsumerState<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends ConsumerState<EmailAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _creatingAccount = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final vm = ref.read(authFlowProvider.notifier);
    final ok = _creatingAccount
        ? await vm.registerWithEmail(email, password)
        : await vm.signInWithEmail(email, password);
    if (!mounted) return;
    if (ok) {
      context.go('/dashboard');
    } else {
      final err = ref.read(authFlowProvider).error ?? 'Something went wrong.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final submitting = ref.watch(authFlowProvider.select((s) => s.submitting));
    final role = ref.watch(authFlowProvider.select((s) => s.role));
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: context.pop)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          child: Form(
            key: _formKey,
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
                Text(_creatingAccount ? 'Create an account' : 'Rasoi Care Admin',
                    style: context.type.headlineLarge),
                const SizedBox(height: 10),
                Text(
                    _creatingAccount
                        ? 'Set an email and password — signing in as ${role.label}.'
                        : 'Sign in with email — signing in as ${role.label}.',
                    style: context.type.bodyMedium),
                const SizedBox(height: 24),
                Eyebrow('Signing in as'),
                const SizedBox(height: 10),
                _RoleToggle(
                  role: role,
                  onChanged: (r) => ref.read(authFlowProvider.notifier).setRole(r),
                ),
                const SizedBox(height: 24),
                CareField('Email',
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Enter a valid email address'
                        : null),
                const SizedBox(height: 13),
                CareField('Password',
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    suffix: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Password must be at least 6 characters'
                        : null),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: submitting ? null : _submit,
                    child: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_creatingAccount ? 'Create account' : 'Sign in'),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: GestureDetector(
                    onTap: () => setState(() => _creatingAccount = !_creatingAccount),
                    child: Text(
                        _creatingAccount
                            ? 'Already have an account? Sign in'
                            : "New here? Create an account",
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: context.scheme.primary)),
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
  // Firebase's real SMS codes are 6 digits; the mock demo code is 4. Using
  // a hardcoded 4 here meant a real code could never be fully entered — the
  // 4th digit auto-submitted an incomplete code and verification always
  // failed, even when the SMS had genuinely arrived.
  late final int _length = ref.read(authFlowProvider.notifier).isMock ? 4 : 6;
  // Live mode types into one real (invisible) field overlaid on the boxes —
  // not one TextField per box. Separate boxes each juggling their own
  // FocusNode is the usual way this kind of UI silently ends up with no box
  // ever focused (nothing requests focus on open, so the on-screen keyboard
  // has nothing to type into) — a single field sidesteps that whole bug
  // class: autofocus is trivial, backspace works for free, and there's only
  // ever one focus target. Mock mode has no keyboard at all (it's a
  // read-only auto-fill demo), so it just animates a plain string.
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();
  String _mockCode = '';
  int _secs = 24;
  Timer? _t;
  bool _verifying = false;

  String get _code =>
      ref.read(authFlowProvider.notifier).isMock ? _mockCode : _codeCtrl.text;

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
          if (!mounted) return;
          setState(() => _mockCode = code.substring(0, i + 1));
          if (i == _length - 1) _submit();
        });
      }
    } else {
      _listenForSms();
    }
  }

  Future<void> _listenForSms() async {
    // Firebase's codes are always exactly 6 digits — matching that exactly
    // (rather than the package's default 4-8 digit range) avoids grabbing
    // the wrong digit run out of an SMS that happens to contain other
    // numbers (a DLT sender-ID header, a phone number, etc.) before the
    // real code.
    final result = await SmartAuth.instance.getSmsWithUserConsentApi(matcher: r'\d{6}');
    if (!mounted) return;
    final code = result.data?.code;
    if (code == null || code.length != _length) {
      // Not surfaced to the user — the manual code boxes are already
      // focused and usable, so a missed auto-read isn't a dead end, just a
      // convenience that didn't fire this time (e.g. the sender is saved
      // as a contact, which Android's User Consent API deliberately
      // ignores, or the OS-level "Allow?" prompt was dismissed).
      debugPrint('OtpScreen: SMS auto-read found no usable code (result: $result)');
      return;
    }
    setState(() => _codeCtrl.text = code);
    _submit();
  }

  @override
  void dispose() {
    _t?.cancel();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    if (!ref.read(authFlowProvider.notifier).isMock) {
      SmartAuth.instance.removeUserConsentApiListener();
    }
    super.dispose();
  }

  void _onCodeChanged(String v) {
    setState(() {});
    if (v.length == _length) _submit();
  }

  Future<void> _submit() async {
    if (_verifying || _code.length != _length) return;
    setState(() => _verifying = true);
    final ok = await ref.read(authFlowProvider.notifier).verifyOtp(_code);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (ok) {
      context.go('/dashboard');
    } else {
      final err = ref.read(authFlowProvider).error ?? 'Verification failed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      setState(() => _codeCtrl.clear());
    }
  }

  Future<void> _resend() async {
    if (_secs > 0) return;
    final phone = ref.read(authFlowProvider).phone;
    setState(() => _secs = 24);
    await ref.read(authFlowProvider.notifier).sendOtp(phone);
    // getSmsWithUserConsentApi's native listener is one-shot — it already
    // resolved (or timed out) for the first SMS, so a resent code needs its
    // own fresh registration or auto-fill would never see it.
    if (!ref.read(authFlowProvider.notifier).isMock) _listenForSms();
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
                    Stack(
                      children: [
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
                                        color: i < _code.length
                                            ? context.scheme.primary
                                            : context.care.hairline,
                                        width: 1.5),
                                  ),
                                  child: Text(i < _code.length ? _code[i] : '',
                                      style: CareType.mono(context.scheme.onSurface,
                                          size: 24, w: FontWeight.w600)),
                                ),
                              ),
                              if (i != _length - 1) const SizedBox(width: 11),
                            ],
                          ],
                        ),
                        // The actual typing surface — invisible, but sized to
                        // cover the whole box row so tapping anywhere focuses
                        // it. Mock mode has nothing here; the boxes above
                        // just animate _mockCode on a timer.
                        if (!isMock)
                          Positioned.fill(
                            child: Opacity(
                              opacity: 0,
                              child: TextField(
                                controller: _codeCtrl,
                                focusNode: _codeFocus,
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                maxLength: _length,
                                decoration: const InputDecoration(
                                    counterText: '', border: InputBorder.none),
                                onChanged: _onCodeChanged,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                        _verifying
                            ? 'Verifying…'
                            : isMock
                                ? (_mockCode.length < _length ? 'Auto-reading SMS…' : 'Code read from SMS.')
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
