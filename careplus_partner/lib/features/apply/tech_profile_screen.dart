// The technician's own view of what they submitted at signup, laid out as
// an Urban Company-style profile menu. Real items (job history, service
// details, financial details, help center) are fully wired to actual data;
// Urban Company business features we have no backend for (Credits, Loans,
// a parts shop, formal Training, referrals) are honest "Coming soon"
// entries rather than fabricated numbers or flows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../state/auth_providers.dart';

class TechProfileScreen extends ConsumerStatefulWidget {
  const TechProfileScreen({super.key});
  @override
  ConsumerState<TechProfileScreen> createState() => _TechProfileScreenState();
}

class _TechProfileScreenState extends ConsumerState<TechProfileScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final me = await fetchTechnicianMe();
    if (!mounted) return;
    if (me != null) ref.read(technicianMeProvider.notifier).state = me;
    setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(technicianMeProvider);
    final verified = me?['verified'] == true;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: const Text('My profile'),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: me == null
            ? Center(
                child: Text('Couldn\'t load your profile — check connection and retry.',
                    style: context.type.bodyMedium))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: context.scheme.surfaceContainerHigh,
                      backgroundImage: (me['photoUrl'] as String?) != null
                          ? NetworkImage(me['photoUrl'] as String)
                          : null,
                      child: (me['photoUrl'] as String?) == null
                          ? Icon(Icons.person_outline, color: context.care.inkFaint, size: 34)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text((me['name'] as String?) ?? 'Technician',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: StatusChip(
                      verified ? 'Verified' : 'Awaiting review',
                      tone: verified ? ChipTone.success : ChipTone.warning,
                    ),
                  ),
                  const SizedBox(height: 18),
                  CareCard(
                    child: Row(
                      children: [
                        Expanded(child: _stat(context, '★ ${me['rating'] ?? '—'}', 'Rating')),
                        Container(width: 1, height: 30, color: context.care.hairline),
                        Expanded(
                            child: _stat(context, '${me['jobsCompleted'] ?? 0}', 'Jobs done')),
                        Container(width: 1, height: 30, color: context.care.hairline),
                        Expanded(
                            child: _stat(
                                context,
                                me['experienceYears'] != null ? '${me['experienceYears']}y' : '—',
                                'Experience')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        await context.push('/tech/apply', extra: me);
                      },
                      child: const Text('Edit profile'),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Eyebrow('Work'),
                  const SizedBox(height: 8),
                  CareCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _menuRow(context, Icons.history, 'Job history',
                            onTap: () => context.push('/tech/earnings')),
                        _menuRow(context, Icons.storefront_outlined, 'My Hub',
                            onTap: () => _openComingSoon(context, 'My Hub')),
                        _menuRow(context, Icons.account_balance_wallet_outlined, 'Credits',
                            onTap: () => _openComingSoon(context, 'Credits')),
                        _menuRow(context, Icons.currency_rupee, 'Loans',
                            onTap: () => _openComingSoon(context, 'Loans')),
                        _menuRow(context, Icons.school_outlined, 'Training',
                            onTap: () => _openComingSoon(context, 'Training'), last: true),
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
                        _menuRow(context, Icons.account_balance_outlined, 'Financial details',
                            onTap: () => context.push('/tech/financial')),
                        _menuRow(context, Icons.help_outline, 'Help Center',
                            onTap: () => context.push('/tech/help')),
                        _menuRow(context, Icons.person_add_alt_outlined, 'Invite a friend',
                            onTap: () => _openComingSoon(context, 'Invite a friend')),
                        _menuRow(context, Icons.shopping_bag_outlined, 'Rasoi Care shop',
                            onTap: () => _openComingSoon(context, 'Rasoi Care shop')),
                        _menuRow(context, Icons.chat_bubble_outline, 'Send WhatsApp updates',
                            onTap: () => _openComingSoon(context, 'WhatsApp updates'),
                            last: true),
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
    );
  }

  void _openComingSoon(BuildContext context, String title) =>
      context.push('/tech/soon', extra: title);

  Widget _stat(BuildContext context, String value, String label) => Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(label, style: context.type.bodySmall),
        ],
      );

  Widget _menuRow(BuildContext context, IconData icon, String label,
      {required VoidCallback onTap, bool last = false}) {
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
                  child: Text(label,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                Icon(Icons.chevron_right, size: 18, color: context.care.inkFaint),
              ],
            ),
          ),
          if (!last) Divider(height: 1, color: context.care.hairline),
        ],
      ),
    );
  }
}
