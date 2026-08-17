// Real earnings/work-history report, modelled on the delivery-partner
// pattern (Zomato's rider app has the same shape: a period toggle, a total,
// a jobs-completed count, and a chronological list of paid jobs) — built
// entirely from bookings this technician has actually completed
// (ApiRepository.completedBookings()), never invented figures.

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

enum _Period { today, week, month, all }

class TechEarningsScreen extends ConsumerStatefulWidget {
  const TechEarningsScreen({super.key});
  @override
  ConsumerState<TechEarningsScreen> createState() => _TechEarningsScreenState();
}

class _TechEarningsScreenState extends ConsumerState<TechEarningsScreen> {
  _Period _period = _Period.week;
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final repo = ref.read(repositoryProvider);
    if (repo is ApiRepository) await repo.refreshBookings();
    if (mounted) ref.read(jobsFeedTickProvider.notifier).bump();
    if (mounted) setState(() => _refreshing = false);
  }

  bool _inPeriod(DateTime? dt) {
    if (dt == null) return _period == _Period.all;
    final now = DateTime.now();
    final d = dt.toLocal();
    return switch (_period) {
      _Period.today => d.year == now.year && d.month == now.month && d.day == now.day,
      _Period.week => now.difference(d).inDays < 7,
      _Period.month => d.year == now.year && d.month == now.month,
      _Period.all => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(jobsFeedTickProvider);
    final repo = ref.watch(repositoryProvider);
    final completed = repo is ApiRepository ? repo.completedBookings() : const <BookingDto>[];
    final fetched = repo is ApiRepository ? repo.bookingsFetched : false;
    final inPeriod = completed.where((b) => _inPeriod(b.updatedAt ?? b.createdAt)).toList();
    final totalPaise = inPeriod.fold<int>(0, (sum, b) => sum + b.totalAmountPaise);
    final avgPaise = inPeriod.isEmpty ? 0 : totalPaise ~/ inPeriod.length;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: const Text('Earnings'),
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                for (final p in _Period.values) ...[
                  Expanded(
                    child: ChoiceChip(
                      label: Text(_label(p)),
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
                  Eyebrow('Total earned', color: CareColors.brass),
                  const SizedBox(height: 6),
                  Text(Money.rupees(totalPaise),
                      style: CareType.mono(CareColors.porcelain, size: 30, w: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('${inPeriod.length} job${inPeriod.length == 1 ? '' : 's'} completed',
                      style: TextStyle(
                          fontSize: 12, color: CareColors.porcelain.withValues(alpha: 0.65))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Stat(label: 'Jobs', value: '${inPeriod.length}')),
              const SizedBox(width: 10),
              Expanded(child: _Stat(label: 'Avg per job', value: Money.rupees(avgPaise))),
            ]),
            const SectionHeader('Job history'),
            if (!fetched)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('Loading…', style: context.type.bodySmall)),
              )
            else if (inPeriod.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('No completed jobs in this period.',
                      style: context.type.bodySmall),
                ),
              )
            else
              for (final b in inPeriod) ...[
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
                    Text(Money.rupees(b.totalAmountPaise),
                        style: CareType.mono(context.scheme.onSurface,
                            size: 13.5, w: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  String _label(_Period p) => switch (p) {
        _Period.today => 'Today',
        _Period.week => '7 days',
        _Period.month => 'This month',
        _Period.all => 'All time',
      };

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    try {
      return DateFormat('d MMM, h:mm a').format(dt.toLocal());
    } catch (_) {
      return '—';
    }
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
            Text(value,
                style: CareType.mono(context.scheme.onSurface, size: 18, w: FontWeight.w600)),
          ],
        ),
      );
}
