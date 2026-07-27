import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../state/auth_providers.dart';
import '../../data/firebase/mock_auth_service.dart';

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
    Timer(const Duration(milliseconds: 2100), () {
      if (mounted) context.go('/onboarding');
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
              child: const Icon(Icons.add, color: CareColors.porcelain, size: 34),
            ),
            const SizedBox(height: 26),
            Text('Care+', style: CareType.display(CareColors.porcelain, size: 46)),
            const SizedBox(height: 14),
            Text('EXPERT CARE FOR THE\nHEART OF YOUR HOME',
                textAlign: TextAlign.center,
                style: CareType.mono(CareColors.brass, size: 10)
                    .copyWith(letterSpacing: 2.2, height: 1.6)),
          ],
        ),
      ),
    );
  }
}

// ============================================================ ONBOARDING
class _Slide {
  const _Slide(this.title, this.body, this.icon);
  final String title, body;
  final IconData icon;
}

const _slides = [
  _Slide(
    'Your kitchen has eight machines. We look after all of them.',
    'Chimneys, hobs, cooktops, built-in ovens, dishwashers, refrigerators, OTGs and water purifiers — one app, one set of trained technicians.',
    Icons.kitchen_outlined,
  ),
  _Slide(
    'A fixed price before a single screw comes out.',
    'You see the visit fee upfront, and every part is quoted in the app for your approval. Nothing gets fitted until you tap yes.',
    Icons.receipt_long_outlined,
  ),
  _Slide(
    'Watch them arrive. Keep the warranty.',
    'Live location on the way, photos of the work when it is done, a GST invoice in seconds and 90 days of cover on every repair.',
    Icons.verified_user_outlined,
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pager = PageController();
  int _i = 0;

  void _next() {
    if (_i < _slides.length - 1) {
      _pager.nextPage(duration: Motion.screen, curve: Motion.ease);
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Eyebrow('0${_i + 1} / 03'),
                  TextButton(
                      onPressed: () => context.go('/login'), child: const Text('Skip')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                onPageChanged: (i) => setState(() => _i = i),
                itemCount: _slides.length,
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 280,
                          child: Center(
                            child: CareDial(
                              value: 0.62 + i * 0.12,
                              size: 220,
                              stroke: 10,
                              child: Icon(s.icon,
                                  size: 78, color: context.scheme.primary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(s.title, style: context.type.headlineMedium),
                        const SizedBox(height: 12),
                        Text(s.body,
                            style: context.type.bodyMedium!.copyWith(fontSize: 14)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 34),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: List.generate(
                          _slides.length,
                          (d) => AnimatedContainer(
                            duration: Motion.screen,
                            width: d == _i ? 18 : 5,
                            height: 5,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              color: d == _i
                                  ? context.scheme.primary
                                  : context.care.hairline,
                              borderRadius: Radii.pill,
                            ),
                          ),
                        ),
                      ),
                      Mono(_i == 2 ? 'Free to browse' : 'Swipe or tap next',
                          color: context.care.inkMuted),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(_i == 2 ? 'Get started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
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
                child: Icon(Icons.add, color: context.scheme.primary, size: 22),
              ),
              const SizedBox(height: 26),
              Text('Welcome back', style: context.type.headlineLarge),
              const SizedBox(height: 10),
              Text(
                  "Sign in with your mobile number. We'll text you a one-time code.",
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
                    onPressed: () {}, child: const Text('Continue with Google')),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                    onPressed: () {}, child: const Text('Continue with Apple')),
              ),
              const SizedBox(height: 22),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('New to Care+? ', style: context.type.bodySmall),
                    GestureDetector(
                      onTap: () => context.push('/register'),
                      child: Text('Create an account',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: context.scheme.primary)),
                    ),
                  ],
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
    // Only simulate SMS auto-read when there's no real backend to wait for.
    if (ref.read(authFlowProvider.notifier).isMock) {
      const code = MockAuthService.demoCode;
      for (var i = 0; i < 4; i++) {
        Timer(Duration(milliseconds: 420 + i * 230), () {
          if (mounted) setState(() => _shown[i] = code[i]);
          if (i == 3) _submit();
        });
      }
    }
  }

  @override
  void dispose() {
    _t?.cancel();
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
      context.go('/register');
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
                            ? 'Enter the 4-digit code we sent.'
                            : 'Sent to +91 $phone.',
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
                          if (i != 3) const SizedBox(width: 11),
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
                              'Care+ never asks for your OTP over a call. Share it only inside this app.',
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

// ============================================================ REGISTER
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final owned = {'Chimney', 'Hob', 'Refrigerator', 'Water purifier'};
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: const Text('Set up your profile'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ProgressBar(0.66),
                    const SizedBox(height: 7),
                    Mono('Step 2 of 3 — about you', color: context.care.inkMuted),
                    const SizedBox(height: 22),
                    const CareField('Full name', initial: 'Rohan Deshpande'),
                    const SizedBox(height: 13),
                    const CareField('Email',
                        initial: 'rohan.d@gmail.com',
                        keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 13),
                    const CareField('Referral code (optional)'),
                    const SizedBox(height: 20),
                    Eyebrow('Which appliances do you own?'),
                    const SizedBox(height: 10),
                    _OwnedChips(owned: owned),
                  ],
                ),
              ),
            ),
            Dock(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Save and continue')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnedChips extends StatefulWidget {
  const _OwnedChips({required this.owned});
  final Set<String> owned;
  @override
  State<_OwnedChips> createState() => _OwnedChipsState();
}

class _OwnedChipsState extends State<_OwnedChips> {
  late final Set<String> _sel = {...widget.owned};
  static const _all = [
    'Chimney', 'Hob', 'Dishwasher', 'Refrigerator',
    'Built-in oven', 'OTG', 'Water purifier', 'Cooktop',
  ];
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in _all)
            ChoiceTag(a,
                selected: _sel.contains(a),
                onTap: () => setState(
                    () => _sel.contains(a) ? _sel.remove(a) : _sel.add(a))),
        ],
      );
}
