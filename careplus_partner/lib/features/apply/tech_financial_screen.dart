// Mirrors Urban Company's "Financial details" screen — payout bank account
// and PAN, read straight from the technician's own KYC record (the same
// fields collected in TechApplyScreen / PATCH /api/technician/me).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../state/auth_providers.dart';

class TechFinancialScreen extends ConsumerWidget {
  const TechFinancialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(technicianMeProvider);
    String val(String key) {
      final v = me?[key] as String?;
      return (v?.isNotEmpty ?? false) ? v! : '—';
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: const Text('Financial details'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Eyebrow('Payout bank account'),
            const SizedBox(height: 8),
            CareCard(
              child: Column(
                children: [
                  _row(context, 'Account holder', val('bankAccountName')),
                  _row(context, 'Account number', val('bankAccountNumber')),
                  _row(context, 'IFSC', val('bankIfsc'), last: true),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Eyebrow('PAN'),
            const SizedBox(height: 8),
            CareCard(
              child: _row(context, 'PAN number', val('panNumber'), last: true),
            ),
            const SizedBox(height: 18),
            Eyebrow('ID document'),
            const SizedBox(height: 8),
            (me?['idDocumentUrl'] as String?) == null
                ? Text('Not uploaded', style: context.type.bodySmall)
                : ClipRRect(
                    borderRadius: Radii.rMd,
                    child: Image.network(me!['idDocumentUrl'] as String,
                        height: 160, fit: BoxFit.cover),
                  ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.push('/tech/apply', extra: me),
                child: const Text('Edit details'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool last = false}) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: context.type.bodySmall),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
