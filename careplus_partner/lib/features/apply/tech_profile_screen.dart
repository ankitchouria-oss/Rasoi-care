// The technician's own view of who they are — photo, name, verification
// status, and career stats. Account-level actions (job history, financial
// details, help, sign out) live in the separate "More" tab, matching how
// Swiggy/Urban Company Partner apps split identity from the menu instead
// of bundling both into one screen.

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
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow('Technician'),
                        const SizedBox(height: 3),
                        Text('My profile', style: context.type.titleMedium),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _refreshing ? null : _refresh,
                    icon: _refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Expanded(
              child: me == null
                  ? Center(
                      child: Text(
                        'Couldn\'t load your profile — check connection and retry.',
                        style: context.type.bodyMedium,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [
                        Center(
                          child: CircleAvatar(
                            radius: 44,
                            backgroundColor:
                                context.scheme.surfaceContainerHigh,
                            backgroundImage: (me['photoUrl'] as String?) != null
                                ? NetworkImage(me['photoUrl'] as String)
                                : null,
                            child: (me['photoUrl'] as String?) == null
                                ? Icon(
                                    Icons.person_outline,
                                    color: context.care.inkFaint,
                                    size: 34,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            (me['name'] as String?) ?? 'Technician',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: StatusChip(
                            verified ? 'Verified' : 'Awaiting review',
                            tone: verified
                                ? ChipTone.success
                                : ChipTone.warning,
                          ),
                        ),
                        const SizedBox(height: 18),
                        CareCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: _stat(
                                  context,
                                  '★ ${me['rating'] ?? '—'}',
                                  'Rating',
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 30,
                                color: context.care.hairline,
                              ),
                              Expanded(
                                child: _stat(
                                  context,
                                  '${me['jobsCompleted'] ?? 0}',
                                  'Jobs done',
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 30,
                                color: context.care.hairline,
                              ),
                              Expanded(
                                child: _stat(
                                  context,
                                  me['experienceYears'] != null
                                      ? '${me['experienceYears']}y'
                                      : '—',
                                  'Experience',
                                ),
                              ),
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
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 3),
      Text(label, style: context.type.bodySmall),
    ],
  );
}
