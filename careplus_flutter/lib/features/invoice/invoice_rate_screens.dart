import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

// ============================================================ INVOICE
class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({super.key, required this.bookingId});
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(repositoryProvider).bookingById(bookingId);
    // GST-inclusive total is all a Booking actually carries — back out the
    // base/tax split from it rather than inventing part-level line items
    // (filters, kits, discount codes) that never happened on this booking.
    final total = booking?.totalPaise ?? 0;
    final base = (total / 1.18).round();
    final gst = total - base;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: const Text('Invoice'),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.download))],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  CareCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Eyebrow('Care+ tax invoice'),
                                const SizedBox(height: 6),
                                Mono(bookingId, size: 12, weight: FontWeight.w600),
                                const SizedBox(height: 5),
                                Text(booking?.whenLabel ?? '', style: context.type.bodySmall),
                              ],
                            ),
                            if (booking?.status == BookingStatus.completed) _PaidStamp(),
                          ],
                        ),
                        const Divider(height: 24),
                        _line(context, booking?.title ?? 'Service', Money.rupees(base)),
                        _line(context, 'GST 18%', Money.rupees(gst)),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total paid',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            Text(Money.rupees(total),
                                style: CareType.mono(context.scheme.onSurface,
                                    size: 18, w: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  CareCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow('Work log'),
                        const SizedBox(height: 12),
                        if (booking?.suctionBefore == null &&
                            booking?.suctionAfter == null &&
                            booking?.timeOnSiteMin == null)
                          Text('Not recorded for this visit.',
                              style: context.type.bodySmall)
                        else ...[
                          if (booking?.suctionBefore != null)
                            _line(context, 'Suction before', '${booking!.suctionBefore} m³/hr'),
                          if (booking?.suctionAfter != null)
                            _line(context, 'Suction after', '${booking!.suctionAfter} m³/hr',
                                color: context.care.success),
                          if (booking?.timeOnSiteMin != null)
                            _line(context, 'Time on site',
                                _formatMinutes(booking!.timeOnSiteMin!)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Dock(
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(onPressed: () {}, child: const Text('Share')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                      onPressed: () => context.push('/booking/$bookingId/rate'),
                      child: const Text('Rate the visit')),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(label,
                  style: context.type.bodySmall!
                      .copyWith(color: color ?? context.scheme.onSurface)),
            ),
            Text(value, style: CareType.mono(color ?? context.scheme.onSurface, size: 11)),
          ],
        ),
      );
}

String _formatMinutes(int minutes) {
  final hrs = minutes ~/ 60;
  final mins = minutes % 60;
  if (hrs == 0) return '$mins min';
  return '$hrs hr${mins == 0 ? '' : ' $mins min'}';
}

class _PaidStamp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: -0.12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: context.care.success, width: 2),
            borderRadius: Radii.rSm,
          ),
          child: Text('PAID',
              style: CareType.mono(context.care.success, size: 11, w: FontWeight.w600)
                  .copyWith(letterSpacing: 3)),
        ),
      );
}

// ============================================================ RATE
class RateScreen extends ConsumerStatefulWidget {
  const RateScreen({super.key, required this.bookingId});
  final String bookingId;
  @override
  ConsumerState<RateScreen> createState() => _RateScreenState();
}

class _RateScreenState extends ConsumerState<RateScreen> {
  int _rating = 5;
  final _tags = {'On time', 'Left it spotless', 'Fair pricing'};
  int _tip = 50;

  static const _words = ['', 'Not good', 'Below par', 'Fine', 'Good', 'Excellent'];
  static const _allTags = [
    'On time', 'Left it spotless', 'Explained clearly',
    'Fair pricing', 'Polite', 'Fixed first time',
  ];

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(repositoryProvider).bookingById(widget.bookingId);
    final tech = booking?.technician ?? ref.watch(repositoryProvider).preferredTechnician;
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(onPressed: context.pop),
          title: const Text('How did it go?')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  CareCard(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 18),
                    child: Column(
                      children: [
                        Blob(tech.initials,
                            size: 62,
                            bg: context.scheme.primary,
                            fg: context.scheme.onPrimary),
                        const SizedBox(height: 12),
                        Text(tech.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                            booking != null
                                ? '${booking.title} · ${booking.whenLabel}'
                                : '',
                            style: context.type.bodySmall),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            5,
                            (i) => Pressable(
                              onTap: () => setState(() => _rating = i + 1),
                              scale: 0.8,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(
                                  i < _rating ? Icons.star : Icons.star_border,
                                  size: 34,
                                  color: i < _rating
                                      ? context.scheme.secondary
                                      : context.care.hairline,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(_words[_rating], style: context.type.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Eyebrow('What stood out?'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in _allTags)
                        ChoiceTag(t,
                            selected: _tags.contains(t),
                            onTap: () => setState(() =>
                                _tags.contains(t) ? _tags.remove(t) : _tags.add(t))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'Write a review (optional)'),
                  ),
                  const SizedBox(height: 16),
                  CareCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow('Add a tip — 100% goes to ${tech.name.split(' ').first}'),
                        const SizedBox(height: 11),
                        Row(
                          children: [
                            for (final t in const [0, 50, 100, 200]) ...[
                              ChoiceTag('₹$t',
                                  selected: _tip == t,
                                  onTap: () => setState(() => _tip = t)),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Dock(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Thanks — 60 Care Coins added')));
                    context.go('/');
                  },
                  child: const Text('Submit rating'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
