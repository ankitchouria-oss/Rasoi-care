import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'dashboard_header.dart';

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});
  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  int _filter = 0; // All · Unassigned · In progress · Closed
  static const _chips = ['All 318', 'Unassigned 4', 'In progress 26', 'Closed 288'];

  BookingCategory? _categoryFor(int i) => switch (i) {
        1 => BookingCategory.unassigned,
        2 => BookingCategory.inProgress,
        3 => BookingCategory.closed,
        _ => null,
      };

  ChipTone _tone(BookingCategory c) => switch (c) {
        BookingCategory.unassigned => ChipTone.danger,
        BookingCategory.inProgress => ChipTone.warning,
        BookingCategory.closed => ChipTone.success,
        BookingCategory.scheduled => ChipTone.neutral,
      };

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(repositoryProvider).bookings();
    final want = _categoryFor(_filter);
    final shown = want == null ? bookings : bookings.where((b) => b.category == want).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const DashboardHeader(eyebrow: 'Rasoi Care operations', title: 'Bookings queue'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _chips.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => ChoiceTag(_chips[i],
                          selected: _filter == i, onTap: () => setState(() => _filter = i)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (shown.isEmpty)
                    const EmptyState(
                        glyph: '◌',
                        title: 'Nothing here',
                        body: 'No bookings match this filter right now.')
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
                                  style: const TextStyle(
                                      fontSize: 13.5, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(b.meta, style: context.type.bodySmall),
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
}
