import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
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

