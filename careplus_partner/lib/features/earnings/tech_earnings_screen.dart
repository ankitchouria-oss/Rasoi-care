// Real earnings/work-history report, modelled on the delivery-partner
// pattern (Zomato's rider app has the same shape: a period toggle, a total,
// a jobs-completed count, and a chronological list of paid jobs) — built
// entirely from GET /api/technician/earnings (ApiRepository.fetchEarnings()),
// never invented figures. The total shown here is the technician's real
// commission — the invoice's base price, with GST and the flat visit fee
// both excluded, at 10% for a payroll technician or 60% for an outsourced
// one (see compute_commission_paise in app.py) — plus their real
// bonus/incentive and fine ledger, never the customer's full invoice
// amount, which is what this screen showed before employment-type-based
// commissions existed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/api/api_repository.dart';
import '../../data/api/booking_dto.dart';
import '../../data/api/earnings_dto.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../state/providers.dart';

enum _Period { today, week, month, all }

class TechEarningsScreen extends ConsumerStatefulWidget {
  const TechEarningsScreen({super.key});
  @override
  ConsumerState<TechEarningsScreen> createState() => _TechEarningsScreenState();
}

class _TechEarningsScreenState extends ConsumerState<TechEarningsScreen> {
  _Period _period = _Period.week;
  bool _refreshing = false;
  TechEarningsSummary? _summary;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    if (repo is! ApiRepository) return;
    final summary = await repo.fetchEarnings();
    if (!mounted) return;
    setState(() {
      _summary = summary ?? _summary;
      _loadedOnce = true;
    });
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final repo = ref.read(repositoryProvider);
    if (repo is ApiRepository) await repo.refreshBookings();
    await _load();
    if (mounted) ref.read(jobsFeedTickProvider.notifier).bump();
    if (mounted) setState(() => _refreshing = false);
  }

  bool _inPeriod(DateTime? dt) {
    if (dt == null) return _period == _Period.all;
    final now = DateTime.now();
    final d = dt.toLocal();
    return switch (_period) {
      _Period.today =>
        d.year == now.year && d.month == now.month && d.day == now.day,
      _Period.week => now.difference(d).inDays < 7,
      _Period.month => d.year == now.year && d.month == now.month,
      _Period.all => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(jobsFeedTickProvider);
    final repo = ref.watch(repositoryProvider);
    final summary = _summary;
    final jobs = summary?.jobs ?? const <EarningsJob>[];
    final inPeriod = jobs.where((j) => _inPeriod(j.completedAt)).toList();
    final commissionPaise =
        inPeriod.fold<int>(0, (sum, j) => sum + j.commissionPaise);
    final avgPaise = inPeriod.isEmpty ? 0 : commissionPaise ~/ inPeriod.length;
    final cancellationFees = repo is ApiRepository ? repo.cancellationFeeBookings() : const <BookingDto>[];
    final cancellationFeesTotalPaise =
        cancellationFees.fold<int>(0, (sum, b) => sum + (b.cancellationFeePaise ?? 0));

    // Real per-month commission totals for the last 6 months, from the same
    // earnings jobs — never invented, just a different slice of the same data.
    final now = DateTime.now();
    final monthTotals = <int>[];
    final monthLabels = <String>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      monthLabels.add(DateFormat('MMM').format(m));
      final total = jobs
          .where((j) {
            final d = j.completedAt?.toLocal();
            return d != null && d.year == m.year && d.month == m.month;
          })
          .fold<int>(0, (sum, j) => sum + j.commissionPaise);
      monthTotals.add(total);
    }
    final maxMonthTotal = monthTotals.fold<int>(0, (a, b) => a > b ? a : b);
    final t = context.l10n;

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
                        Eyebrow(t.earningsEyebrow),
                        const SizedBox(height: 3),
                        Text(t.earningsTitle, style: context.type.titleMedium),
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Row(
                    children: [
                      for (final p in _Period.values) ...[
                        Expanded(
                          child: ChoiceChip(
                            label: Text(_label(t, p)),
                            selected: _period == p,
                            onSelected: (_) => setState(() => _period = p),
                          ),
                        ),
                        if (p != _Period.values.last) const SizedBox(width: 6),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  CareCard(
                    color: CareColors.pine,
                    borderColor: Colors.transparent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Eyebrow(t.earningsTotalEarned, color: CareColors.brass),
                            if (summary != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: CareColors.porcelain.withValues(alpha: 0.12),
                                  borderRadius: Radii.pill,
                                ),
                                child: Text(
                                  summary.isPayroll
                                      ? t.earningsPayrollBadge(_pct(summary.commissionRate))
                                      : t.earningsOutsourcedBadge(_pct(summary.commissionRate)),
                                  style: CareType.mono(CareColors.porcelain, size: 10.5),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          Money.rupees(commissionPaise),
                          style: CareType.mono(
                            CareColors.porcelain,
                            size: 30,
                            w: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.earningsJobsCompleted(inPeriod.length),
                          style: TextStyle(
                            fontSize: 12,
                            color: CareColors.porcelain.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          label: t.earningsJobs,
                          value: '${inPeriod.length}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Stat(
                          label: t.earningsAvgPerJob,
                          value: Money.rupees(avgPaise),
                        ),
                      ),
                    ],
                  ),
                  SectionHeader(t.earningsByMonth),
                  CareCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 104,
                          child: maxMonthTotal == 0
                              ? Center(
                                  child: Text(
                                    t.earningsNoJobsYet,
                                    style: context.type.bodySmall,
                                  ),
                                )
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < monthTotals.length;
                                      i++
                                    ) ...[
                                      Expanded(
                                        child: _Bar(
                                          heightPct:
                                              monthTotals[i] / maxMonthTotal,
                                          emphasize:
                                              i == monthTotals.length - 1,
                                          delay: Duration(milliseconds: i * 60),
                                        ),
                                      ),
                                      if (i != monthTotals.length - 1)
                                        const SizedBox(width: 9),
                                    ],
                                  ],
                                ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (var i = 0; i < monthLabels.length; i++) ...[
                              Expanded(
                                child: Text(
                                  monthLabels[i],
                                  textAlign: TextAlign.center,
                                  style: CareType.mono(
                                    context.care.inkMuted,
                                    size: 10.5,
                                  ),
                                ),
                              ),
                              if (i != monthLabels.length - 1)
                                const SizedBox(width: 9),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (summary != null) ...[
                    SectionHeader(t.earningsIncentives,
                        trailing: Text(Money.rupees(summary.incentiveTotalPaise),
                            style: context.type.bodySmall!
                                .copyWith(color: context.care.success))),
                    Text(t.earningsIncentivesExplain, style: context.type.bodySmall),
                    const SizedBox(height: 10),
                    _MilestoneCard(
                      label: t.earningsMilestoneLifetimeLabel(summary.jobsPerIncentive),
                      progress: (summary.jobsPerIncentive -
                              summary.jobsUntilNextLifetimeMilestone) /
                          summary.jobsPerIncentive,
                      message: t.earningsMilestoneLifetime(
                        summary.jobsUntilNextLifetimeMilestone,
                        Money.rupees(summary.incentivePaise),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _MilestoneCard(
                      label: t.earningsMilestoneWeeklyLabel(summary.weeklyJobsForBonus),
                      progress: summary.jobsCompletedThisWeek / summary.weeklyJobsForBonus,
                      message: summary.weeklyBonusEarnedThisWeek
                          ? t.earningsMilestoneWeeklyDone(Money.rupees(summary.weeklyBonusPaise))
                          : t.earningsMilestoneWeekly(
                              summary.jobsUntilWeeklyBonus,
                              Money.rupees(summary.weeklyBonusPaise),
                            ),
                      done: summary.weeklyBonusEarnedThisWeek,
                    ),
                    if (summary.incentives.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final e in summary.incentives) ...[
                        _LedgerRow(entry: e, tone: ChipTone.success),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                  if (summary != null) ...[
                    SectionHeader(t.earningsFines,
                        trailing: Text(Money.rupees(summary.fineTotalPaise),
                            style: context.type.bodySmall!
                                .copyWith(color: context.scheme.error))),
                    Text(t.earningsFinesExplain, style: context.type.bodySmall),
                    const SizedBox(height: 8),
                    CareCard(
                      child: Text(
                        t.earningsFinesRule(
                          Money.rupees(summary.lateArrivalFinePaise),
                          summary.lateArrivalGraceMinutes,
                        ),
                        style: context.type.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (summary.fines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(t.earningsNoFinesYet,
                            style: context.type.bodySmall!
                                .copyWith(color: context.care.success)),
                      )
                    else
                      for (final e in summary.fines) ...[
                        _LedgerRow(entry: e, tone: ChipTone.danger),
                        const SizedBox(height: 8),
                      ],
                  ],
                  if (cancellationFees.isNotEmpty) ...[
                    SectionHeader(t.earningsCancellationFees,
                        trailing: Text(Money.rupees(cancellationFeesTotalPaise),
                            style: context.type.bodySmall)),
                    Text(t.earningsCancellationExplain, style: context.type.bodySmall),
                    const SizedBox(height: 8),
                    for (final b in cancellationFees) ...[
                      CareCard(
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.service,
                                    style: const TextStyle(
                                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(
                                    '${b.customerName} · ${_formatDate(b.updatedAt ?? b.createdAt)}',
                                    style: context.type.bodySmall),
                              ],
                            ),
                          ),
                          Text(Money.rupees((b.cancellationFeePaise ?? 0)),
                              style: CareType.mono(context.scheme.onSurface,
                                  size: 13.5, w: FontWeight.w600)),
                        ]),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  SectionHeader(t.earningsExploreMore),
                  CareCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _menuRow(
                          context,
                          Icons.currency_rupee,
                          t.earningsLoans,
                          onTap: () =>
                              context.push('/tech/soon', extra: t.earningsLoans),
                        ),
                        _menuRow(
                          context,
                          Icons.history,
                          t.earningsRecoveries,
                          onTap: () =>
                              context.push('/tech/soon', extra: t.earningsRecoveries),
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  SectionHeader(t.earningsJobHistory),
                  if (!_loadedOnce)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(t.earningsLoading, style: context.type.bodySmall),
                      ),
                    )
                  else if (inPeriod.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          t.earningsNoJobsInPeriod,
                          style: context.type.bodySmall,
                        ),
                      ),
                    )
                  else
                    for (final j in inPeriod) ...[
                      CareCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    j.service,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${j.bookingId} · ${_formatDate(j.completedAt)}',
                                    style: context.type.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  Money.rupees(j.commissionPaise),
                                  style: CareType.mono(
                                    context.scheme.onSurface,
                                    size: 13.5,
                                    w: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  t.earningsInvoiceTotal(Money.rupees(j.totalAmountPaise)),
                                  style: context.type.bodySmall!.copyWith(fontSize: 10.5),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _pct(double rate) => '${(rate * 100).round()}%';

  String _label(AppLocalizations t, _Period p) => switch (p) {
    _Period.today => t.earningsPeriodToday,
    _Period.week => t.earningsPeriod7Days,
    _Period.month => t.earningsPeriodMonth,
    _Period.all => t.earningsPeriodAll,
  };

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    try {
      return DateFormat('d MMM, h:mm a').format(dt.toLocal());
    } catch (_) {
      return '—';
    }
  }

  Widget _menuRow(
    BuildContext context,
    IconData icon,
    String label, {
    required VoidCallback onTap,
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
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
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

/// Live progress toward one achievable milestone bonus — a label ("Every
/// 20 jobs"), a progress bar, and how many more jobs are needed (or that
/// it's already been earned this cycle). Always visible, even at zero
/// progress, and updates automatically since it's built straight from the
/// latest TechEarningsSummary on every refresh.
class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({
    required this.label,
    required this.progress,
    required this.message,
    this.done = false,
  });
  final String label;
  final double progress;
  final String message;
  final bool done;

  @override
  Widget build(BuildContext context) => CareCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Eyebrow(label),
                if (done)
                  Icon(Icons.check_circle, size: 16, color: context.care.success),
              ],
            ),
            const SizedBox(height: 8),
            ProgressBar(progress.clamp(0.0, 1.0)),
            const SizedBox(height: 8),
            Text(
              message,
              style: context.type.bodySmall!.copyWith(
                color: done ? context.care.success : null,
                fontWeight: done ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      );
}

/// One row in the Bonus & Incentives or Fines table.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry, required this.tone});
  final LedgerEntry entry;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) => CareCard(
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.reason,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(_formatDate(entry.createdAt), style: context.type.bodySmall),
              ],
            ),
          ),
          Text(
            '${entry.amountPaise >= 0 ? '+' : ''}${Money.rupees(entry.amountPaise)}',
            style: CareType.mono(
              tone == ChipTone.success ? context.care.success : context.scheme.error,
              size: 13.5,
              w: FontWeight.w600,
            ),
          ),
        ]),
      );

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    try {
      return DateFormat('d MMM, h:mm a').format(dt.toLocal());
    } catch (_) {
      return '—';
    }
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.heightPct,
    required this.emphasize,
    required this.delay,
  });
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
            top: Radius.circular(7),
            bottom: Radius.circular(3),
          ),
        ),
      ),
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => CareCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: 6),
        Text(
          value,
          style: CareType.mono(
            context.scheme.onSurface,
            size: 18,
            w: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
