// Mirrors Urban Company's "Financial details" screen — GST, PAN, payout
// bank account and personal details (DOB, Aadhaar, email, name, phone), all
// read straight from the technician's own KYC record (the same fields
// collected in TechApplyScreen / PATCH /api/technician/me). Phone comes
// live from the signed-in Firebase user, not the backend record, since
// that's the actual source of truth for it.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../state/auth_providers.dart';

class TechFinancialScreen extends ConsumerWidget {
  const TechFinancialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(technicianMeProvider);
    final t = context.l10n;
    String val(String key) {
      final v = me?[key] as String?;
      return (v?.isNotEmpty ?? false) ? v! : '—';
    }

    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: Text(t.financialTitle),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Eyebrow(t.financialGst),
            const SizedBox(height: 8),
            CareCard(
              child: _row(context, t.financialGstNumber, val('gstNumber'), last: true),
            ),
            const SizedBox(height: 18),
            Eyebrow(t.financialPan),
            const SizedBox(height: 8),
            CareCard(
              child: _row(context, t.financialPanNumber, val('panNumber'), last: true),
            ),
            const SizedBox(height: 18),
            Eyebrow(t.financialPayoutBank),
            const SizedBox(height: 8),
            CareCard(
              child: Column(
                children: [
                  _row(context, t.financialAccountHolder, val('bankAccountName')),
                  _row(context, t.financialAccountNumber, val('bankAccountNumber')),
                  _row(context, t.financialIfsc, val('bankIfsc')),
                  _row(context, t.financialUpiId, val('upiId'), last: true),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Eyebrow(t.financialPersonalDetails),
            const SizedBox(height: 8),
            CareCard(
              child: Column(
                children: [
                  _row(context, t.financialDob, val('dateOfBirth')),
                  _row(context, t.financialAadhaarNumber, val('aadharNumber')),
                  _row(context, t.financialEmail, val('email')),
                  _row(context, t.financialName, (me?['name'] as String?)?.isNotEmpty == true
                      ? me!['name'] as String
                      : '—'),
                  _row(context, t.financialPhone, phone ?? '—', last: true),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Eyebrow(t.financialAddress),
            const SizedBox(height: 8),
            CareCard(
              child: Text(val('address'), style: context.type.bodyMedium),
            ),
            const SizedBox(height: 18),
            Eyebrow(t.financialEmergencyContact),
            const SizedBox(height: 8),
            CareCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row(context, t.financialEmergencyName, val('emergencyContactName')),
                        _row(context, t.financialEmergencyPhone, val('emergencyContactPhone'),
                            last: true),
                      ],
                    ),
                  ),
                  if ((me?['emergencyContactPhone'] as String?)?.isNotEmpty ?? false) ...[
                    const SizedBox(width: 12),
                    IconButton.filled(
                      onPressed: () =>
                          launchUrl(Uri(scheme: 'tel', path: me!['emergencyContactPhone'] as String)),
                      icon: const Icon(Icons.call, size: 18),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Eyebrow(t.financialAadhaarCard),
            const SizedBox(height: 8),
            _docThumb(context, t, me?['aadharDocumentUrl'] as String?),
            const SizedBox(height: 18),
            Eyebrow(t.financialPanCard),
            const SizedBox(height: 8),
            _docThumb(context, t, me?['panDocumentUrl'] as String?),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => context.push('/tech/apply', extra: me),
                child: Text(t.financialEditDetails),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docThumb(BuildContext context, AppLocalizations t, String? url) => url == null
      ? Text(t.financialNotUploaded, style: context.type.bodySmall)
      : ClipRRect(
          borderRadius: Radii.rMd,
          child: Image.network(url, height: 160, fit: BoxFit.cover),
        );

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
