import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/widgets/charts.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../state/auth_providers.dart';
import 'dashboard_header.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportRangeProvider);
    final report = ref.watch(repositoryProvider).report(range);
    final role = ref.watch(currentRoleProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            DashboardHeader(
              eyebrow: 'Analysis & reports',
              title: 'Nashik cluster',
              trailing: GestureDetector(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report exported as PDF (demo)'))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.scheme.surface,
                    borderRadius: Radii.pill,
                    border: Border.all(color: context.care.hairline),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.ios_share, size: 14, color: context.scheme.primary),
                    const SizedBox(width: 5),
                    Text('Export',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: context.scheme.primary)),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _RangeSeg(
                range: range,
                onChanged: (r) => ref.read(reportRangeProvider.notifier).set(r),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                children: [
                  _RevenueTrendCard(report: report),
                  const SizedBox(height: 12),
                  _RatingTrendCard(report: report),
                  SectionHeader('Revenue by category',
                      trailing: Mono(range.label, color: context.care.inkMuted)),
                  _CategoryRevenueCard(report: report),
                  SectionHeader('Technician leaderboard'),
                  _LeaderboardCard(report: report),
                  SectionHeader('Customer segments'),
                  _CustomerSegmentsCard(report: report),
                  SectionHeader('SLA & complaints'),
                  _ComplaintsCard(report: report),
                  SectionHeader('Payment mix'),
                  _PaymentMixCard(report: report),
                  SectionHeader('Coupons & discounts'),
                  _CouponsCard(report: report),
                  SectionHeader('Financial P&L',
                      trailing: role == AdminRole.owner
                          ? null
                          : const StatusChip('Owner only', tone: ChipTone.neutral, height: 24)),
                  if (role == AdminRole.owner)
                    _FinancialsCard(report: report)
                  else
                    const _OwnerOnlyLock(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeSeg extends StatelessWidget {
  const _RangeSeg({required this.range, required this.onChanged});
  final ReportRange range;
  final ValueChanged<ReportRange> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration:
            BoxDecoration(color: context.scheme.surfaceContainerHigh, borderRadius: Radii.rSm),
        child: Row(
          children: [
            for (final r in ReportRange.values)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(r),
                  child: AnimatedContainer(
                    duration: Motion.press,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: r == range ? context.scheme.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: r == range
                          ? Shadows.card(Theme.of(context).brightness == Brightness.dark)
                          : null,
                    ),
                    child: Text(r.label,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color:
                                r == range ? context.scheme.onSurface : context.care.inkMuted)),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _RevenueTrendCard extends StatelessWidget {
  const _RevenueTrendCard({required this.report});
  final ReportBundle report;
  @override
  Widget build(BuildContext context) {
    final total = report.categoryRevenue.fold<int>(0, (s, c) => s + c.revenuePaise);
    return CareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Revenue trend',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text(Money.rupees(total),
                  style: CareType.mono(context.scheme.primary, size: 15, w: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          SparkLineChart(values: [for (final p in report.revenueTrend) p.value]),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final p in report.revenueTrend)
                Expanded(
                  child: Text(p.label,
                      textAlign: TextAlign.center,
                      style: CareType.mono(context.care.inkMuted, size: 10)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatingTrendCard extends StatelessWidget {
  const _RatingTrendCard({required this.report});
  final ReportBundle report;
  @override
  Widget build(BuildContext context) {
    final last = report.ratingTrend.last.value * 5;
    return CareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Average rating trend',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text('★ ${last.toStringAsFixed(2)}',
                  style: CareType.mono(context.scheme.secondary, size: 15, w: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          SparkLineChart(
              values: [for (final p in report.ratingTrend) p.value],
              color: context.scheme.secondary,
              height: 90),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final p in report.ratingTrend)
                Expanded(
                  child: Text(p.label,
                      textAlign: TextAlign.center,
                      style: CareType.mono(context.care.inkMuted, size: 10)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryRevenueCard extends StatelessWidget {
  const _CategoryRevenueCard({required this.report});
  final ReportBundle report;
  @override
  Widget build(BuildContext context) {
    final list = [...report.categoryRevenue]..sort((a, b) => b.revenuePaise.compareTo(a.revenuePaise));
    final max = list.first.revenuePaise;
    return CareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in list)
            HBarRow(
              label: '${c.glyph}  ${c.label}',
              value: '${Money.rupees(c.revenuePaise)} · ${c.jobs} jobs',
              fraction: c.revenuePaise / max,
            ),
        ],
      ),
    );
  }
}

class _LeaderboardCard extends StatelessWidget {
  const _LeaderboardCard({required this.report});
  final ReportBundle report;
  @override
  Widget build(BuildContext context) {
    final list = [...report.technicianLeaderboard]
      ..sort((a, b) => b.revenuePaise.compareTo(a.revenuePaise));
    final max = list.first.revenuePaise;
    return CareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < list.length; i++)
            HBarRow(
              rank: i + 1,
              label: list[i].name,
              value:
                  '${Money.rupees(list[i].revenuePaise)} · ★${list[i].rating} · ${list[i].firstTimeFixPct}% FTF',
              fraction: list[i].revenuePaise / max,
              color: i == 0 ? context.scheme.secondary : null,
            ),
        ],
      ),
    );
  }
}

class _CustomerSegmentsCard extends StatelessWidget {
  const _CustomerSegmentsCard({required this.report});
  final ReportBundle report;
  @override
  Widget build(BuildContext context) {
    final colors = [
      context.scheme.primary,
      context.scheme.secondary,
      context.care.success,
      context.scheme.error,
    ];
    final total = report.customerSegments.fold<int>(0, (s, e) => s + e.count);
    return CareCard(
      child: Row(
        children: [
          DonutChart(
            slices: [
              for (var i = 0; i < report.customerSegments.length; i++)
                (report.customerSegments[i].count.toDouble(), colors[i % colors.length]),
            ],
            size: 96,
            stroke: 15,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$total', style: CareType.mono(context.scheme.onSurface, size: 17, w: FontWeight.w600)),
              Text('customers', style: CareType.mono(context.care.inkMuted, size: 9)),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < report.customerSegments.length; i++)
                  LegendRow(
                    color: colors[i % colors.length],
                    label: report.customerSegments[i].label,
                    value: '${report.customerSegments[i].count} · ${report.customerSegments[i].pct.toStringAsFixed(0)}%',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComplaintsCard extends StatelessWidget {
  const _ComplaintsCard({required this.report});
  final ReportBundle report;
  @override
  Widget build(BuildContext context) {
    final totalComplaints = report.complaintReasons.fold<int>(0, (s, e) => s + e.count);
    final avgHrs = report.complaintReasons.isEmpty
        ? 0.0
        : report.complaintReasons.fold<double>(0, (s, e) => s + e.avgResolutionHrs * e.count) /
            totalComplaints;
    return CareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatusChip('$totalComplaints complaints', tone: ChipTone.danger, height: 26),
              Text('Avg resolution ${avgHrs.toStringAsFixed(0)}h', style: context.type.bodySmall),
            ],
          ),
          const Divider(height: 24),
          for (final c in report.complaintReasons)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                      child: Text(c.label,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                  Text('${c.count} · ${c.avgResolutionHrs.toStringAsFixed(0)}h',
                      style: CareType.mono(context.care.inkMuted, size: 11.5)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentMixCard extends StatelessWidget {
  const _PaymentMixCard({required this.report});
  final ReportBundle report;
  @override
  Widget build(BuildContext context) {
    final colors = [
      context.scheme.primary,
      context.scheme.secondary,
      context.care.success,
      context.care.inkMuted,
    ];
    final total = report.paymentMix.fold<int>(0, (s, e) => s + e.amountPaise);
    return CareCard(
      child: Row(
        children: [
          DonutChart(
            slices: [
              for (var i = 0; i < report.paymentMix.length; i++)
                (report.paymentMix[i].amountPaise.toDouble(), colors[i % colors.length]),
            ],
            size: 96,
            stroke: 15,
            child: Text(Money.rupees(total),
                textAlign: TextAlign.center,
                style: CareType.mono(context.scheme.onSurface, size: 13, w: FontWeight.w600)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < report.paymentMix.length; i++)
                  LegendRow(
                    color: colors[i % colors.length],
                    label: report.paymentMix[i].method,
                    value: '${report.paymentMix[i].pct.toStringAsFixed(0)}%',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CouponsCard extends StatelessWidget {
  const _CouponsCard({required this.report});
  final ReportBundle report;
  @override
  Widget build(BuildContext context) => CareCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < report.coupons.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: i == report.coupons.length - 1
                      ? null
                      : Border(bottom: BorderSide(color: context.care.hairline)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Mono(report.coupons[i].code, size: 12.5, weight: FontWeight.w700),
                    Text('${report.coupons[i].redemptions} redemptions',
                        style: context.type.bodySmall),
                    Text('-${Money.rupees(report.coupons[i].discountGivenPaise)}',
                        style: CareType.mono(context.scheme.error, size: 12, w: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _FinancialsCard extends StatelessWidget {
  const _FinancialsCard({required this.report});
  final ReportBundle report;
  @override
  Widget build(BuildContext context) {
    final f = report.financials;
    return CareCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line(context, 'Gross revenue', f.grossRevenuePaise, positive: true),
          _line(context, 'Technician payouts', -f.technicianPayoutsPaise),
          _line(context, 'Parts cost', -f.partsCostPaise),
          _line(context, 'Discounts given', -f.discountsGivenPaise),
          _line(context, 'Refunds', -f.refundsPaise),
          const Divider(height: 24),
          _line(context, 'Net margin', f.netMarginPaise, positive: true, bold: true),
          const SizedBox(height: 4),
          Text('${f.netMarginPct.toStringAsFixed(1)}% of gross revenue',
              style: context.type.bodySmall),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('GST collected (pass-through)', style: context.type.bodySmall),
              Text(Money.rupees(f.taxCollectedPaise),
                  style: CareType.mono(context.care.inkMuted, size: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, int amountPaise,
      {bool positive = false, bool bold = false}) {
    final color = amountPaise < 0
        ? context.scheme.error
        : positive
            ? context.care.success
            : context.scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 14 : 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
          Text(
              amountPaise < 0
                  ? '-${Money.rupees(amountPaise.abs())}'
                  : Money.rupees(amountPaise),
              style: CareType.mono(color, size: bold ? 15 : 12.5, w: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _OwnerOnlyLock extends StatelessWidget {
  const _OwnerOnlyLock();
  @override
  Widget build(BuildContext context) => CareCard(
        color: context.scheme.surfaceContainerHigh,
        borderColor: Colors.transparent,
        child: Row(children: [
          Icon(Icons.lock_outline, size: 20, color: context.care.inkFaint),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                'Payouts, parts cost and margin are visible to the Owner account only.',
                style: context.type.bodySmall),
          ),
        ]),
      );
}
