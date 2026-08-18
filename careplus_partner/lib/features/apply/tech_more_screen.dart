// The "More" tab — account-level menu, split out of the old combined
// profile+menu screen so Profile can be its own tab (matching Swiggy/Urban
// Company Partner apps, which separate "who you are" from "everything
// else"). Real items (job history, financial details, help center,
// documents) are fully wired to actual data; business features we have no
// backend for (Credits, Loans, a parts shop, formal Training, referrals)
// stay honest "Coming soon" entries rather than fabricated numbers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../state/auth_providers.dart';

class TechMoreScreen extends ConsumerStatefulWidget {
  const TechMoreScreen({super.key});
  @override
  ConsumerState<TechMoreScreen> createState() => _TechMoreScreenState();
}

class _TechMoreScreenState extends ConsumerState<TechMoreScreen> {
  @override
  Widget build(BuildContext context) {
    final me = ref.watch(technicianMeProvider);
    final verified = me?['verified'] == true;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow('Account'),
                        const SizedBox(height: 3),
                        Text('More', style: context.type.titleMedium),
                      ],
                    ),
                  ),
                  StatusChip(
                    verified ? 'Verified' : 'Awaiting review',
                    tone: verified ? ChipTone.success : ChipTone.warning,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  Eyebrow('Work'),
                  const SizedBox(height: 8),
                  CareCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _menuRow(
                          context,
                          Icons.history,
                          'Job history',
                          onTap: () => context.go('/tech/earnings'),
                        ),
                        _menuRow(
                          context,
                          Icons.storefront_outlined,
                          'My Hub',
                          onTap: () => _openComingSoon(context, 'My Hub'),
                        ),
                        _menuRow(
                          context,
                          Icons.account_balance_wallet_outlined,
                          'Credits',
                          onTap: () => _openComingSoon(context, 'Credits'),
                        ),
                        _menuRow(
                          context,
                          Icons.currency_rupee,
                          'Loans',
                          onTap: () => _openComingSoon(context, 'Loans'),
                        ),
                        _menuRow(
                          context,
                          Icons.school_outlined,
                          'Training',
                          onTap: () => _openComingSoon(context, 'Training'),
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Eyebrow('Account'),
                  const SizedBox(height: 8),
                  CareCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _menuRow(
                          context,
                          Icons.badge_outlined,
                          'My documents',
                          onTap: () => context.push('/tech/financial'),
                        ),
                        _menuRow(
                          context,
                          Icons.account_balance_outlined,
                          'Financial details',
                          onTap: () => context.push('/tech/financial'),
                        ),
                        _menuRow(
                          context,
                          Icons.help_outline,
                          'Help Center',
                          onTap: () => context.push('/tech/help'),
                        ),
                        _menuRow(
                          context,
                          Icons.person_add_alt_outlined,
                          'Invite a friend',
                          onTap: () =>
                              _openComingSoon(context, 'Invite a friend'),
                        ),
                        _menuRow(
                          context,
                          Icons.shopping_bag_outlined,
                          'Rasoi Care shop',
                          onTap: () =>
                              _openComingSoon(context, 'Rasoi Care shop'),
                        ),
                        _menuRow(
                          context,
                          Icons.chat_bubble_outline,
                          'Send WhatsApp updates',
                          onTap: () =>
                              _openComingSoon(context, 'WhatsApp updates'),
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () async {
                        await ref.read(authServiceProvider).signOut();
                        ref.read(authFlowProvider.notifier).reset();
                        if (context.mounted) context.go('/login');
                      },
                      child: const Text('Sign out'),
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

  void _openComingSoon(BuildContext context, String title) =>
      context.push('/tech/soon', extra: title);

  Widget _menuRow(
    BuildContext context,
    IconData icon,
    String label, {
    required VoidCallback onTap,
    bool last = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 20, color: context.care.inkFaint),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: context.care.inkFaint,
                ),
              ],
            ),
          ),
          if (!last) Divider(height: 1, color: context.care.hairline),
        ],
      ),
    );
  }
}
