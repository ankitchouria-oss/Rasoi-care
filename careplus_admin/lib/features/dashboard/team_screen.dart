import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'dashboard_header.dart';

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  String _dutyLabel(DutyStatus d) => switch (d) {
        DutyStatus.onJob => 'On job',
        DutyStatus.idle => 'Idle',
        DutyStatus.offDuty => 'Off duty',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(repositoryProvider).team();
    final onDuty = team.where((t) => t.duty != DutyStatus.offDuty).length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const DashboardHeader(eyebrow: 'Rasoi Care operations', title: 'Technician team'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  Row(children: [
                    Expanded(
                        child: _Kpi(label: 'On duty', value: '$onDuty / ${team.length}')),
                    const SizedBox(width: 10),
                    Expanded(child: _Kpi(label: 'Avg jobs/tech', value: '6.2')),
                  ]),
                  const SizedBox(height: 12),
                  Stagger(children: [
                    for (final t in team)
                      CareCard(
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${t.name} — roster and payouts'))),
                        child: Row(children: [
                          Blob(t.initials, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.name,
                                    style: const TextStyle(
                                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text('${t.specialties} · ${t.statsLabel}',
                                    style: context.type.bodySmall),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('★ ${t.rating}',
                                  style: CareType.mono(context.scheme.secondary,
                                      size: 12.5, w: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(_dutyLabel(t.duty),
                                  style: TextStyle(fontSize: 11, color: context.care.inkMuted)),
                            ],
                          ),
                        ]),
                      ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => CareCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(label),
            const SizedBox(height: 6),
            Text(value,
                style: CareType.mono(context.scheme.onSurface, size: 21, w: FontWeight.w600)),
          ],
        ),
      );
}
