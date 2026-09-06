// The cancellation policy shown to the customer — see [CancellationPolicy]
// for the real tiers this mirrors, and app.py's _cancellation_fee_for for
// where the server independently applies them.

import 'package:flutter/material.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../l10n/l10n_extensions.dart';

/// Opens a bottom sheet listing every cancellation-fee tier, highlighting
/// the one that applies right now if [booking] is given (e.g. from the
/// tracking screen or the cancel-confirmation dialog) — omit it to just
/// show the policy on its own (e.g. from checkout, before a booking
/// exists yet).
Future<void> showCancellationPolicySheet(BuildContext context, {Booking? booking}) {
  final currentFeePaise =
      booking == null ? null : CancellationPolicy.feePaisePreview(booking);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final t = sheetContext.l10n;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.cancellationPolicyTitle, style: sheetContext.type.titleMedium),
            const SizedBox(height: 4),
            Text(t.cancellationPolicyBody, style: sheetContext.type.bodySmall),
            const SizedBox(height: 16),
            for (final tier in CancellationPolicy.tiers) ...[
              _PolicyRow(
                label: tier.isFree
                    ? t.cancellationTierFree(tier.hoursThreshold)
                    : t.cancellationTierWithin(tier.hoursThreshold),
                feePaise: tier.feePaise,
                current: currentFeePaise == tier.feePaise,
              ),
              if (tier != CancellationPolicy.tiers.last) const Divider(height: 20),
            ],
            const SizedBox(height: 16),
            CareCard(
              color: sheetContext.scheme.secondaryContainer,
              borderColor: Colors.transparent,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.handshake_outlined,
                      color: sheetContext.scheme.onSecondaryContainer, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.cancellationPolicyDisclaimer,
                      style: sheetContext.type.bodySmall!
                          .copyWith(color: sheetContext.scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PolicyRow extends StatelessWidget {
  const _PolicyRow({required this.label, required this.feePaise, required this.current});
  final String label;
  final int feePaise;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final feeLabel = feePaise == 0 ? t.cancellationFree : Money.rupees(feePaise);
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: context.type.bodyMedium!.copyWith(
                fontWeight: current ? FontWeight.w700 : FontWeight.w400,
              )),
        ),
        const SizedBox(width: 12),
        if (current) ...[
          StatusChip(t.cancellationAppliesNow, tone: ChipTone.selected, height: 26),
          const SizedBox(width: 8),
        ],
        Text(feeLabel,
            style: CareType.mono(
              feePaise == 0 ? context.care.success : context.scheme.onSurface,
              size: 15,
              w: FontWeight.w700,
            )),
      ],
    );
  }
}
