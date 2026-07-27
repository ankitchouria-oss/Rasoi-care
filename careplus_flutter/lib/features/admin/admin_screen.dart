import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});
  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  int _tab = 0;
  int _bookingFilter = 0; // All · Unassigned · In progress · Closed

  static const _bookingChips = ['All 318', 'Unassigned 4', 'In progress 26', 'Closed 288'];

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow('Care+ operations'),
                        const SizedBox(height: 3),
                        Text('Nashik cluster', style: context.type.titleMedium),
                      ],
                    ),
                  ),
                  const StatusChip('Today ▾', height: 32),
                  const SizedBox(width: 9),
                  _RoundIcon(
                      icon: Icons.arrow_back,
                      onTap: () =>
                          context.canPop() ? context.pop() : context.go('/account')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _Segmented(
                tabs: const ['Overview', 'Bookings', 'Team', 'Stock'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: switch (_tab) {
                0 => _OverviewTab(overview: repo.adminOverview()),
                1 => _BookingsTab(
                    bookings: repo.adminBookings(),
                    filter: _bookingFilter,
                    chips: _bookingChips,
                    onFilter: (i) => setState(() => _bookingFilter = i),
                  ),
                2 => _TeamTab(team: repo.adminTeam()),
                _ => _StockTab(stock: repo.adminStock()),
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================ OVERVIEW
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.overview});
  final AdminOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    return ListView(
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
            trailing: StatusChip('${o.attention.length} open', tone: ChipTone.danger, height: 26)),
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
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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

// ============================================================ BOOKINGS
class _BookingsTab extends StatelessWidget {
  const _BookingsTab({
    required this.bookings,
    required this.filter,
    required this.chips,
    required this.onFilter,
  });
  final List<AdminBooking> bookings;
  final int filter;
  final List<String> chips;
  final ValueChanged<int> onFilter;

  BookingCategory? _categoryFor(int i) => switch (i) {
        1 => BookingCategory.unassigned,
        2 => BookingCategory.inProgress,
        3 => BookingCategory.closed,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final want = _categoryFor(filter);
    final shown = want == null ? bookings : bookings.where((b) => b.category == want).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) =>
                ChoiceTag(chips[i], selected: filter == i, onTap: () => onFilter(i)),
          ),
        ),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          const EmptyState(
              glyph: '◌', title: 'Nothing here', body: 'No bookings match this filter right now.')
        else
          Stagger(children: [
            for (final b in shown)
              CareCard(
                onTap: () => ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Opening ${b.jobId}'))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        StatusChip(b.statusLabel, tone: _tone(b.category), height: 24),
                        Mono(b.jobId, color: context.care.inkMuted),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(b.title,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(b.meta, style: context.type.bodySmall),
                  ],
                ),
              ),
          ]),
      ],
    );
  }

  ChipTone _tone(BookingCategory c) => switch (c) {
        BookingCategory.unassigned => ChipTone.danger,
        BookingCategory.inProgress => ChipTone.warning,
        BookingCategory.closed => ChipTone.success,
        BookingCategory.scheduled => ChipTone.neutral,
      };
}

// ============================================================ TEAM
class _TeamTab extends StatelessWidget {
  const _TeamTab({required this.team});
  final List<AdminTeamMember> team;

  @override
  Widget build(BuildContext context) {
    final onDuty = team.where((t) => t.duty != DutyStatus.offDuty).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        Row(children: [
          Expanded(child: _Kpi(label: 'On duty', value: '$onDuty / ${team.length}', delta: '', positive: null)),
          const SizedBox(width: 10),
          Expanded(child: _Kpi(label: 'Avg jobs/tech', value: '6.2', delta: '', positive: null)),
        ]),
        const SizedBox(height: 12),
        Stagger(children: [
          for (final t in team)
            CareCard(
              onTap: () => ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('${t.name} — roster and payouts'))),
              child: Row(children: [
                Blob(t.initials, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('${t.specialties} · ${t.statsLabel}', style: context.type.bodySmall),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('★ ${t.rating}',
                        style: CareType.mono(context.scheme.secondary, size: 12.5, w: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_dutyLabel(t.duty),
                        style: TextStyle(fontSize: 11, color: context.care.inkMuted)),
                  ],
                ),
              ]),
            ),
        ]),
      ],
    );
  }

  String _dutyLabel(DutyStatus d) => switch (d) {
        DutyStatus.onJob => 'On job',
        DutyStatus.idle => 'Idle',
        DutyStatus.offDuty => 'Off duty',
      };
}

// ============================================================ STOCK
class _StockTab extends StatelessWidget {
  const _StockTab({required this.stock});
  final List<AdminStockItem> stock;

  @override
  Widget build(BuildContext context) {
    final lowCount = stock.where((s) => s.low).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      children: [
        CareCard(
          color: context.scheme.errorContainer,
          borderColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$lowCount SKUs below reorder level',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: context.scheme.error)),
              const SizedBox(height: 6),
              Text('At the current burn rate the Ashok Nagar hub runs dry in 4 days.',
                  style: context.type.bodySmall),
              const SizedBox(height: 11),
              OutlinedButton(
                onPressed: () => ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Purchase order drafted'))),
                child: const Text('Raise purchase order'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Stagger(children: [
          for (final s in stock)
            CareCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(s.name,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      Mono(s.sku, color: context.care.inkMuted),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${s.inStock} in stock · reorder at ${s.reorderAt}',
                          style: context.type.bodySmall),
                      StatusChip(s.low ? 'Low' : 'Healthy',
                          tone: s.low ? ChipTone.danger : ChipTone.success, height: 24),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: Radii.pill,
                    child: LinearProgressIndicator(
                      value: s.fillFraction,
                      minHeight: 6,
                      backgroundColor: context.care.hairline,
                      valueColor: AlwaysStoppedAnimation(
                          s.low ? context.scheme.error : context.care.success),
                    ),
                  ),
                ],
              ),
            ),
        ]),
      ],
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.tabs, required this.index, required this.onChanged});
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: context.scheme.surfaceContainerHigh, borderRadius: Radii.rSm),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: Motion.press,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? context.scheme.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: i == index
                          ? Shadows.card(Theme.of(context).brightness == Brightness.dark)
                          : null,
                    ),
                    child: Text(tabs[i],
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: i == index
                                ? context.scheme.onSurface
                                : context.care.inkMuted)),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.scheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: context.care.hairline),
          ),
          child: Icon(icon, size: 18),
        ),
      );
}
