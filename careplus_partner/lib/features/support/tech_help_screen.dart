// Real, app-specific help content — how KYC review, jobs, and payouts
// actually work in this app — rather than a fake ticketing/chat system we
// have no backend for.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../l10n/l10n_extensions.dart';

class TechHelpScreen extends StatelessWidget {
  const TechHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final faqs = [
      (t.helpFaq1Q, t.helpFaq1A),
      (t.helpFaq2Q, t.helpFaq2A),
      (t.helpFaq3Q, t.helpFaq3A),
      (t.helpFaq4Q, t.helpFaq4A),
      (t.helpFaq5Q, t.helpFaq5A),
      (t.helpFaq6Q, t.helpFaq6A),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: Text(t.helpTitle),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text(t.helpFaqHeading, style: context.type.titleMedium),
            const SizedBox(height: 12),
            for (final (q, a) in faqs) ...[
              CareCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(a, style: context.type.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            Text(t.helpContactFooter, style: context.type.bodySmall),
          ],
        ),
      ),
    );
  }
}
