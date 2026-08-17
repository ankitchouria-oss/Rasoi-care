// Real, app-specific help content — how KYC review, jobs, and payouts
// actually work in this app — rather than a fake ticketing/chat system we
// have no backend for.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';

class TechHelpScreen extends StatelessWidget {
  const TechHelpScreen({super.key});

  static const _faqs = [
    (
      'How long does profile verification take?',
      'Once you submit your details and documents, our team reviews them and verifies your account. You can check your status anytime from "Application under review" — it updates as soon as you\'re approved.',
    ),
    (
      'How do I go online for jobs?',
      'Once verified, open the Jobs tab and toggle yourself online. New job requests in your service category and area will start showing up there.',
    ),
    (
      'How is my earnings total calculated?',
      'The Earnings screen totals the value of every job you\'ve marked Completed, split by today / this week / this month. It reads directly from your completed job history — nothing is estimated.',
    ),
    (
      'How do I get paid?',
      'Payouts are settled to the bank account and IFSC you provided under Financial details. Make sure those stay accurate — you can update them anytime from Edit profile.',
    ),
    (
      'The map or navigation isn\'t working on a job.',
      'Navigate opens the job\'s address in Google Maps. Make sure location permission is granted to the app and you have a network connection — the on-screen map also needs a data connection to load.',
    ),
    (
      'I need to change my category, city, or documents.',
      'Go to My profile → Edit profile. You can update your details and documents there; changes are saved to your account immediately.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: const Text('Help Center'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text('Frequently asked questions', style: context.type.titleMedium),
            const SizedBox(height: 12),
            for (final (q, a) in _faqs) ...[
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
            Text(
              'Need something else? Reach out to your onboarding coordinator directly — a dedicated in-app support line isn\'t available yet.',
              style: context.type.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
