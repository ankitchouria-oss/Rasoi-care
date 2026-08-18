// "My Shifts" — the technician's schedule view, matching the dedicated
// shifts tab in real gig-partner apps (Swiggy Partner). We have no real
// clock-in/out shift system, so this deliberately shows only what's real:
// today's route stops (from ApiRepository.routeToday()) and a day-by-day
// breakdown of jobs actually completed this week (ApiRepository.
// completedBookings()) — never invented shift start/end times.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/api/api_repository.dart';
import '../../data/api/booking_dto.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

class TechShiftsScreen extends ConsumerStatefulWidget {
  const TechShiftsScreen({super.key});
  @override
  ConsumerState<TechShiftsScreen> createState() => _TechShiftsScreenState();
}

class _TechShiftsScreenState extends ConsumerState<TechShiftsScreen> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final repo = ref.read(repositoryProvider);
    if (repo is ApiRepository) await repo.refreshBookings();
    if (mounted) ref.read(jobsFeedTickProvider.notifier).bump();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(jobsFeedTickProvider);
    final repo = ref.watch(repositoryProvider);
    final route = repo.routeToday();
    final completed = repo is ApiRepository
        ? repo.completedBookings()
        : const <BookingDto>[];

    // Real per-day totals for the last 7 days, from the same completed
    // bookings the Money tab uses — just grouped by day instead of month.
    final now = DateTime.now();
    final days = <DateTime>[];
    for (var i = 6; i >= 0; i--) {
      days.add(
        DateTime(now.year, now.month, now.day).subtract(Duration(days: i)),
      );
    }
    final jobsByDay = <DateTime, List<BookingDto>>{for (final d in days) d: []};
    for (final b in completed) {
      final d = (b.updatedAt ?? b.createdAt)?.toLocal();
      if (d == null) continue;
      final key = DateTime(d.year, d.month, d.day);
      jobsByDay[key]?.add(b);
    }
    final maxCount = jobsByDay.values.fold<int>(
      1,
      (m, l) => l.length > m ? l.length : m,
    );
    final workedDays = jobsByDay.values.where((l) => l.isNotEmpty).length;
    final weekTotalPaise = jobsByDay.values
        .expand((l) => l)
        .fold<int>(0, (sum, b) => sum + b.totalAmountPaise);

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
                        Eyebrow('Schedule'),
                        const SizedBox(height: 3),
                        Text('My Shifts', style: context.type.titleMedium),
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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          label: 'Worked days · 7d',
                          value: '$workedDays',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Stat(
                          label: 'Earned · 7d',
                          value: Money.rupees(weekTotalPaise),
                        ),
                      ),
                    ],
                  ),
                  const SectionHeader('This week'),
                  CareCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final d in days) ...[
                          Expanded(
                            child: _DayBar(
                              label: DateFormat('E').format(d).substring(0, 1),
                              count: jobsByDay[d]?.length ?? 0,
                              maxCount: maxCount,
                              isToday:
                                  d.year == now.year &&
                                  d.month == now.month &&
                                  d.day == now.day,
                            ),
                          ),
                          if (d != days.last) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  SectionHeader(
                    "Today's route",
                    trailing: Text(
                      '${route.length} stop${route.length == 1 ? '' : 's'}',
                      style: context.type.bodySmall,
                    ),
                  ),
                  if (route.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No stops scheduled for today.',
                          style: context.type.bodySmall,
                        ),
                      ),
                    )
                  else
                    Stagger(
                      children: [
                        for (final stop in route)
                          CareCard(
                            onTap: () =>
                                context.push('/tech/job/${stop.jobId}'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    StatusChip(
                                      stop.status == StopStatus.inProgress
                                          ? 'In progress'
                                          : 'Next',
                                      tone: stop.status == StopStatus.inProgress
                                          ? ChipTone.success
                                          : ChipTone.neutral,
                                      height: 24,
                                    ),
                                    Mono(
                                      stop.time,
                                      color: context.care.inkMuted,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${stop.title} · ${stop.customerName}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(stop.meta, style: context.type.bodySmall),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.label,
    required this.count,
    required this.maxCount,
    required this.isToday,
  });
  final String label;
  final int count, maxCount;
  final bool isToday;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$count', style: CareType.mono(context.care.inkMuted, size: 10.5)),
      const SizedBox(height: 4),
      SizedBox(
        height: 64,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: count / maxCount),
          duration: const Duration(milliseconds: 500),
          curve: Motion.ease,
          builder: (_, v, __) => FractionallySizedBox(
            alignment: Alignment.bottomCenter,
            heightFactor: v.clamp(0.04, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: isToday
                    ? context.scheme.secondary
                    : context.scheme.primary,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                  bottom: Radius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
          color: isToday ? context.scheme.primary : context.care.inkMuted,
        ),
      ),
    ],
  );
}
