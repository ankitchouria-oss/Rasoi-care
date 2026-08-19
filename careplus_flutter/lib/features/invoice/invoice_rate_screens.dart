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
// Previously showed a fixed mock technician's name/photo (booking.technician
// is never actually populated, so this always fell back to the same
// "preferred technician" persona regardless of who did the job), had a
// pre-checked set of praise tags and a review text box that went nowhere,
// a fake "100% goes to <name>" tip selector with no real payout behind it,
// and "Submit rating" only ever showed a fabricated "60 Care Coins added"
// toast — the star rating itself was never sent to the backend, even
// though a real /api/bookings/<id>/rating endpoint already existed for it.
class RateScreen extends ConsumerStatefulWidget {
  const RateScreen({super.key, required this.bookingId});
  final String bookingId;
  @override
  ConsumerState<RateScreen> createState() => _RateScreenState();
}

class _RateScreenState extends ConsumerState<RateScreen> {
  int _rating = 5;
  bool _submitting = false;

  static const _words = ['', 'Not good', 'Below par', 'Fine', 'Good', 'Excellent'];

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final ok = await ref
        .read(apiRepositoryProvider)
        .rateBooking(bookingId: widget.bookingId, rating: _rating);
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Thanks for rating your visit.'
            : "Couldn't submit your rating — check your connection and try again.")));
    if (ok) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(repositoryProvider).bookingById(widget.bookingId);
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
                ],
              ),
            ),
            Dock(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Submit rating'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
