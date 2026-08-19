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
import '../../l10n/l10n_extensions.dart';
import '../../state/auth_providers.dart';
import '../../state/providers.dart';

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
    final whatsappOn = ref.watch(whatsappUpdatesProvider);
    final locale = ref.watch(localeProvider);
    final t = context.l10n;
    final languageLabel = locale.languageCode == 'hi' ? t.languageHindi : t.languageEnglish;

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
                        Eyebrow(t.moreAccountSection),
                        const SizedBox(height: 3),
                        Text(t.navMore, style: context.type.titleMedium),
                      ],
                    ),
                  ),
                  StatusChip(
                    verified ? t.moreVerified : t.moreAwaitingReview,
                    tone: verified ? ChipTone.success : ChipTone.warning,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  Eyebrow(t.moreWork),
                  const SizedBox(height: 8),
                  CareCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _menuRow(
                          context,
                          Icons.history,
                          t.moreJobHistory,
                          onTap: () => context.go('/tech/earnings'),
                        ),
                        _menuRow(
                          context,
                          Icons.storefront_outlined,
                          t.moreMyHub,
                          onTap: () => _openComingSoon(context, t.moreMyHub),
                        ),
                        _menuRow(
                          context,
                          Icons.account_balance_wallet_outlined,
                          t.moreCredits,
                          onTap: () => _openComingSoon(context, t.moreCredits),
                        ),
                        _menuRow(
                          context,
                          Icons.currency_rupee,
                          t.moreLoans,
                          onTap: () => _openComingSoon(context, t.moreLoans),
                        ),
                        _menuRow(
                          context,
                          Icons.school_outlined,
                          t.moreTraining,
                          onTap: () => _openComingSoon(context, t.moreTraining),
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Eyebrow(t.moreAccountSection),
                  const SizedBox(height: 8),
                  CareCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _menuRow(
                          context,
                          Icons.badge_outlined,
                          t.moreMyDocuments,
                          onTap: () => context.push('/tech/financial'),
                        ),
                        _menuRow(
                          context,
                          Icons.account_balance_outlined,
                          t.moreFinancialDetails,
                          onTap: () => context.push('/tech/financial'),
                        ),
                        _menuRow(
                          context,
                          Icons.help_outline,
                          t.moreHelpCenter,
                          onTap: () => context.push('/tech/help'),
                        ),
                        _menuRow(
                          context,
                          Icons.person_add_alt_outlined,
                          t.moreInviteFriend,
                          onTap: () => _openComingSoon(context, t.moreInviteFriend),
                        ),
                        _menuRow(
                          context,
                          Icons.shopping_bag_outlined,
                          t.moreShop,
                          onTap: () => _openComingSoon(context, t.moreShop),
                        ),
                        _menuRow(
                          context,
                          Icons.chat_bubble_outline,
                          t.moreWhatsAppUpdates,
                          subtitle: whatsappOn ? t.moreWhatsAppOn : t.moreWhatsAppOff,
                          onTap: () => _confirmWhatsAppToggle(context, whatsappOn),
                        ),
                        _menuRow(
                          context,
                          Icons.translate,
                          t.moreChangeLanguage,
                          subtitle: languageLabel,
                          onTap: () => context.push('/tech/language'),
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
                      child: Text(t.commonSignOut),
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

  /// Mirrors Urban Company Partner's own confirmation dialog before turning
  /// WhatsApp updates off. This toggle is a real, persisted device
  /// preference — see whatsappUpdatesProvider — but there's no WhatsApp
  /// Business API behind this backend yet to actually send anything, so
  /// the copy stays honest about that rather than promising delivery.
  Future<void> _confirmWhatsAppToggle(BuildContext context, bool currentlyOn) async {
    final t = context.l10n;
    if (!currentlyOn) {
      await ref.read(whatsappUpdatesProvider.notifier).set(true);
      return;
    }
    final turnOff = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.moreWhatsAppDialogTitle),
        content: Text(t.moreWhatsAppDialogBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(t.moreWhatsAppKeepOn)),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
            child: Text(t.moreWhatsAppTurnOff),
          ),
        ],
      ),
    );
    if (turnOff == true) {
      await ref.read(whatsappUpdatesProvider.notifier).set(false);
    }
  }

  Widget _menuRow(
    BuildContext context,
    IconData icon,
    String label, {
    required VoidCallback onTap,
    String? subtitle,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(fontSize: 12, color: context.care.inkFaint)),
                      ],
                    ],
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
