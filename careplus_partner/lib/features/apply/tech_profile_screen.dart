// The technician's own view of what they submitted at signup — Urban
// Company's Partner app has the same "My Profile" surface showing category,
// area, experience, documents and payout details back to the professional,
// not just to ops. Read-only for now; re-submitting through TechApplyScreen
// (PATCH /api/technician/me) is the seam for an "Edit" action later.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
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
                  const SizedBox(height: 22),
                  CareCard(
                    child: Column(
                      children: [
                        _row(context, 'Category', (me['category'] as String?) ?? '—'),
                        _row(context, 'Service area',
                            (me['area'] as String?)?.isNotEmpty == true
                                ? me['area'] as String
                                : '—'),
                        _row(context, 'Experience',
                            me['experienceYears'] != null
                                ? '${me['experienceYears']} years'
                                : '—'),
                        _row(context, 'Rating', '★ ${me['rating'] ?? '—'}'),
                        _row(context, 'Jobs completed', '${me['jobsCompleted'] ?? 0}',
                            last: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Eyebrow('ID document'),
                  const SizedBox(height: 8),
                  (me['idDocumentUrl'] as String?) == null
                      ? Text('Not uploaded', style: context.type.bodySmall)
                      : ClipRRect(
                          borderRadius: Radii.rMd,
                          child: Image.network(me['idDocumentUrl'] as String,
                              height: 160, fit: BoxFit.cover),
                        ),
                  const SizedBox(height: 18),
                  Eyebrow('Payout bank details'),
                  const SizedBox(height: 8),
                  CareCard(
                    child: Column(
                      children: [
                        _row(context, 'Account holder',
                            (me['bankAccountName'] as String?)?.isNotEmpty == true
                                ? me['bankAccountName'] as String
                                : '—'),
                        _row(context, 'Account number',
                            (me['bankAccountNumber'] as String?)?.isNotEmpty == true
                                ? me['bankAccountNumber'] as String
                                : '—'),
                        _row(context, 'IFSC',
                            (me['bankIfsc'] as String?)?.isNotEmpty == true
                                ? me['bankIfsc'] as String
                                : '—',
                            last: true),
                      ],
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
