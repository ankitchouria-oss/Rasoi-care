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
                                Eyebrow('Rasoi Care tax invoice'),
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
                  if (booking != null && booking.serviceChanges.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    CareCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow('Service updated'),
                          const SizedBox(height: 10),
                          for (final change in booking.serviceChanges) ...[
                            Text(
                              '${change.oldService} (${Money.rupees(change.oldPricePaise)}) '
                              '→ ${change.newService} (${Money.rupees(change.newPricePaise)})',
                              style: context.type.bodySmall!.copyWith(height: 1.5),
                            ),
                            if (change != booking.serviceChanges.last) const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  ],
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
                          // Chimney jobs get the real airflow (CFM) reading
                          // the technician actually took, before and after
                          // the clean — the only appliance the Partner app
                          // ever asks this for. Anything else (or an older
                          // booking recorded before that was true) falls
                          // back to the plain before/after lines below.
                          if (booking?.appliance == Appliance.chimney &&
                              booking?.suctionBefore != null &&
                              booking?.suctionAfter != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 9),
                              child: _AirflowCompare(
                                  before: booking!.suctionBefore!, after: booking.suctionAfter!),
                            )
                          else ...[
                            if (booking?.suctionBefore != null)
                              _line(context, 'Airflow before', '${booking!.suctionBefore} CFM'),
                            if (booking?.suctionAfter != null)
                              _line(context, 'Airflow after', '${booking!.suctionAfter} CFM',
                                  color: context.care.success),
                          ],
                          if (booking?.timeOnSiteMin != null)
                            _line(context, 'Time on site',
                                _formatMinutes(booking!.timeOnSiteMin!)),
                        ],
                        if ((booking?.brand?.trim().isNotEmpty ?? false) ||
                            (booking?.modelNumber?.trim().isNotEmpty ?? false)) ...[
                          const Divider(height: 22),
                          if (booking?.brand?.trim().isNotEmpty ?? false)
                            _line(context, 'Brand', booking!.brand!),
                          if (booking?.modelNumber?.trim().isNotEmpty ?? false)
                            _line(context, 'Model', booking!.modelNumber!),
                        ],
                      ],
                    ),
                  ),
                  if (booking != null && booking.parts.isNotEmpty)
                    _PartsQuoteCard(bookingId: bookingId, parts: booking.parts),
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

/// Real part/extra-work quotes the technician has raised for this booking —
/// see app.py's booking_parts table. A pending quote gets real Approve/
/// Reject actions; once decided, that decision is shown and can't be
/// retaken (the backend enforces the same rule).
class _PartsQuoteCard extends ConsumerStatefulWidget {
  const _PartsQuoteCard({required this.bookingId, required this.parts});
  final String bookingId;
  final List<PartQuote> parts;

  @override
  ConsumerState<_PartsQuoteCard> createState() => _PartsQuoteCardState();
}

class _PartsQuoteCardState extends ConsumerState<_PartsQuoteCard> {
  String? _decidingPartId;

  Future<void> _decide(PartQuote part, bool approve) async {
    setState(() => _decidingPartId = part.id);
    final ok = await ref
        .read(apiRepositoryProvider)
        .decidePart(bookingId: widget.bookingId, partId: part.id, approve: approve);
    if (!mounted) return;
    setState(() => _decidingPartId = null);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text("Couldn't submit your decision — check your connection and try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: CareCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow('Parts & extra work'),
            const SizedBox(height: 12),
            for (var i = 0; i < widget.parts.length; i++) ...[
              _PartQuoteRow(
                part: widget.parts[i],
                deciding: _decidingPartId == widget.parts[i].id,
                onDecide: (approve) => _decide(widget.parts[i], approve),
              ),
              if (i != widget.parts.length - 1) const Divider(height: 26),
            ],
          ],
        ),
      ),
    );
  }
}

class _PartQuoteRow extends StatelessWidget {
  const _PartQuoteRow({required this.part, required this.deciding, required this.onDecide});
  final PartQuote part;
  final bool deciding;
  final ValueChanged<bool> onDecide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(part.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('Qty ${part.qty}${part.sku != null ? ' · ${part.sku}' : ''}',
                      style: context.type.bodySmall),
                ],
              ),
            ),
            Text(Money.rupees(part.pricePaise * part.qty),
                style: CareType.mono(context.scheme.onSurface, size: 13)),
          ],
        ),
        const SizedBox(height: 10),
        if (part.isPending)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: deciding ? null : () => onDecide(false),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: deciding ? null : () => onDecide(true),
                  child: deciding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Approve'),
                ),
              ),
            ],
          )
        else
          StatusChip(
            part.isApproved ? 'Approved' : 'Rejected',
            tone: part.isApproved ? ChipTone.success : ChipTone.danger,
            height: 26,
          ),
      ],
    );
  }
}

/// The real before/after airflow (CFM) reading a technician took on a
/// chimney job — see the Partner app's AirflowCheckScreen, the only place
/// these numbers ever come from. No invented improvement figure: the
/// percentage badge only appears when the after reading actually measured
/// higher than the before one.
class _AirflowCompare extends StatelessWidget {
  const _AirflowCompare({required this.before, required this.after});
  final int before;
  final int after;

  @override
  Widget build(BuildContext context) {
    final delta = after - before;
    final pct = before > 0 ? ((delta / before) * 100).round() : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _stat(context, 'Airflow before', '$before CFM', context.scheme.onSurface)),
            Icon(Icons.arrow_forward_rounded, size: 16, color: context.care.inkFaint),
            const SizedBox(width: 8),
            Expanded(child: _stat(context, 'Airflow after', '$after CFM', context.care.success)),
          ],
        ),
        if (delta > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: context.care.success.withValues(alpha: 0.1),
              borderRadius: Radii.pill,
            ),
            child: Text('+$pct% stronger airflow after cleaning',
                style: CareType.mono(context.care.success, size: 11, w: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  Widget _stat(BuildContext context, String label, String value, Color valueColor) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.bodySmall),
          const SizedBox(height: 3),
          Text(value, style: CareType.mono(valueColor, size: 15, w: FontWeight.w600)),
        ],
      );
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
