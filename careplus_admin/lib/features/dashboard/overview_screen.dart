import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'dashboard_header.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(repositoryProvider).overview();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const DashboardHeader(eyebrow: 'Rasoi Care operations', title: 'Nashik cluster'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  Stagger(gap: 10, children: [
                    Row(children: [
                      Expanded(
                        child: _Kpi(
                            label: 'Revenue',
                            value: '₹${(o.revenuePaise / 100 / 100000).toStringAsFixed(2)}L',
                            delta: '▲ ${o.revenueDeltaPct}% vs last week',
                            positive: true),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Kpi(
                            label: 'Jobs closed',
                            value: '${o.jobsClosed}',
                            delta: '▲ ${o.jobsClosedDeltaPct}%',
                            positive: true),
                      ),
                    ]),
                    Row(children: [
                      Expanded(
                        child: _Kpi(
                            label: 'SLA breach',
                            value: '${o.slaBreaches}',
                            delta: '▲ ${o.slaBreachesToday} today',
                            positive: false,
                            danger: true),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Kpi(
                            label: 'Avg rating',
                            value: '${o.avgRating}',
                            delta: '${o.ratingCount} rated',
                            positive: null),
                      ),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  CareCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Bookings by day',
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                            Mono('7 days', color: context.care.inkMuted),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 104,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var i = 0; i < o.weekBars.length; i++) ...[
                                Expanded(
                                  child: _Bar(
                                      heightPct: o.weekBars[i] / 100,
                                      emphasize: i == 4,
                                      delay: Duration(milliseconds: i * 60)),
                                ),
                                if (i != o.weekBars.length - 1) const SizedBox(width: 9),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (var i = 0; i < o.weekLabels.length; i++) ...[
                              Expanded(
                                child: Text(o.weekLabels[i],
                                    textAlign: TextAlign.center,
                                    style: CareType.mono(context.care.inkMuted, size: 10.5)),
                              ),
                              if (i != o.weekLabels.length - 1) const SizedBox(width: 9),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: _RingStat(
                            pct: o.technicianUtilisationPct, label: 'Technician utilisation')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _RingStat(
                            pct: o.firstTimeFixPct,
                            label: 'First-time fix rate',
                            color: context.scheme.secondary)),
                  ]),
                  SectionHeader('Needs attention',
                      trailing: StatusChip('${o.attention.length} open',
                          tone: ChipTone.danger, height: 26)),
                  Stagger(children: [
                    for (final a in o.attention)
                      CareCard(
                        onTap: () => ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(_attentionAction(a)))),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(a.title,
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w700)),
                                Mono(a.jobId, color: context.care.inkMuted),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(a.detail, style: context.type.bodySmall),
                          ],
                        ),
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

  String _attentionAction(AttentionItem a) => a.title.startsWith('Unassigned')
      ? 'Assigning nearest technician'
      : a.title.startsWith('Complaint')
          ? 'Opening complaint'
          : 'Refund queued';
}

class _Kpi extends StatelessWidget {
  const _Kpi(
      {required this.label,
      required this.value,
      required this.delta,
      required this.positive,
      this.danger = false});
  final String label, value, delta;
  final bool? positive; // null = neutral
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final deltaColor = danger
        ? context.scheme.error
        : positive == true
            ? context.care.success
            : context.care.inkMuted;
    return CareCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(label),
          const SizedBox(height: 6),
          Text(value,
              style: CareType.mono(
                  danger ? context.scheme.error : context.scheme.onSurface,
                  size: 21,
                  w: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(delta, style: TextStyle(fontSize: 11, color: deltaColor)),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.heightPct, required this.emphasize, required this.delay});
  final double heightPct;
  final bool emphasize;
  final Duration delay;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: heightPct),
        duration: const Duration(milliseconds: 600),
        curve: Motion.ease,
        builder: (_, v, __) => FractionallySizedBox(
          alignment: Alignment.bottomCenter,
          heightFactor: v,
          child: Container(
            decoration: BoxDecoration(
              color: emphasize ? context.scheme.secondary : context.scheme.primary,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(7), bottom: Radius.circular(3)),
            ),
          ),
        ),
      );
}

class _RingStat extends StatelessWidget {
  const _RingStat({required this.pct, required this.label, this.color});
  final int pct;
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => CareCard(
        child: Column(
          children: [
            CareDial(
              value: pct / 100,
              size: 82,
              stroke: 8,
              showTicks: false,
              color: color,
              child: Text('$pct%',
                  style: CareType.mono(context.scheme.onSurface, size: 20, w: FontWeight.w600)),
            ),
            const SizedBox(height: 9),
            Text(label, textAlign: TextAlign.center, style: context.type.bodySmall),
          ],
        ),
      );
}
