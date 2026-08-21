import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/api/api_repository.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../state/providers.dart';
import 'signature_pad.dart';

class TechCloseScreen extends ConsumerStatefulWidget {
  const TechCloseScreen({super.key, required this.jobId});
  final String jobId;
  @override
  ConsumerState<TechCloseScreen> createState() => _TechCloseScreenState();
}

class _TechCloseScreenState extends ConsumerState<TechCloseScreen> {
  final _sigKey = GlobalKey<SignaturePadState>();
  int _payMethod = 0; // 0 UPI QR · 1 Card · 2 Cash · 3 Send link
  bool _closing = false;

  // Matches the strings app.py's /api/bookings/<id>/payment accepts.
  static const _methodCodes = ['upi', 'card', 'cash', 'link'];

  List<(String, String)> _methods(AppLocalizations t) => [
        (t.closeMethodUpiTitle, t.closeMethodUpiSub),
        (t.closeMethodCardTitle, t.closeMethodCardSub),
        (t.closeMethodCashTitle, t.closeMethodCashSub),
        (t.closeMethodLinkTitle, t.closeMethodLinkSub),
      ];

  /// Records which payment method was actually used — previously this
  /// button called nothing at all (the booking was already Completed by
  /// the prior screen's advance-to-Completed call), so "Mark paid" had no
  /// real effect beyond a SnackBar. A failure here still lets the
  /// technician leave (the job itself is genuinely done either way) but
  /// says so honestly rather than pretending it was recorded.
  Future<void> _markPaid() async {
    setState(() => _closing = true);
    final repo = ref.read(repositoryProvider);
    var ok = false;
    if (repo is ApiRepository) {
      ok = await repo.setPaymentMethod(widget.jobId, _methodCodes[_payMethod]);
    }
    if (!mounted) return;
    setState(() => _closing = false);
    final t = context.l10n;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(ok ? t.closePaidToast : t.closePaymentError)));
    context.go('/tech/jobs');
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(repositoryProvider).closeInvoice(widget.jobId);
    final collectNow = lines.fold<int>(0, (sum, l) => sum + l.amountPaise);
    final t = context.l10n;
    final methods = _methods(t);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: Text(t.closeTitle),
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
                        Eyebrow(t.closeInvoice(widget.jobId)),
                        const Divider(height: 22),
                        for (final l in lines) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(l.label,
                                    style: context.type.bodySmall!.copyWith(
                                        color: l.tone == LineTone.success
                                            ? context.care.success
                                            : context.scheme.onSurface)),
                                Text(Money.rupees(l.amountPaise),
                                    style: CareType.mono(
                                        l.tone == LineTone.success
                                            ? context.care.success
                                            : context.scheme.onSurface,
                                        size: 12)),
                              ],
                            ),
                          ),
                        ],
                        const Divider(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(t.closeCollectNow,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(Money.rupees(collectNow),
                                style: CareType.mono(context.scheme.onSurface,
                                    size: 19, w: FontWeight.w600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SectionHeader(t.closeCustomerSignature,
                      trailing: GestureDetector(
                        onTap: () => _sigKey.currentState?.clear(),
                        child: Text(t.closeClear,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.scheme.primary)),
                      )),
                  CareCard(
                    padding: EdgeInsets.zero,
                    child: SignaturePad(key: _sigKey),
                  ),
                  SectionHeader(t.closeCollectPayment),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.05,
                    children: [
                      for (var i = 0; i < methods.length; i++)
                        CareCard(
                          onTap: () => setState(() => _payMethod = i),
                          borderColor: _payMethod == i ? context.scheme.primary : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(methods[i].$1,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text(methods[i].$2, style: context.type.bodySmall),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CareCard(
                    color: context.scheme.surfaceContainerHigh,
                    borderColor: Colors.transparent,
                    child: Column(
                      children: [
                        Container(
                          width: 118,
                          height: 118,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: context.scheme.surface,
                            borderRadius: Radii.rSm,
                          ),
                          child: Icon(
                              _payMethod == 0 ? Icons.qr_code_2 : Icons.point_of_sale,
                              size: 44,
                              color: context.care.inkFaint),
                        ),
                        const SizedBox(height: 11),
                        Text(_hint(t, _payMethod, collectNow), style: context.type.bodySmall),
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
                  onPressed: _closing ? null : _markPaid,
                  child: _closing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(t.closeMarkPaid),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _hint(AppLocalizations t, int method, int collectNow) {
    final amount = Money.rupees(collectNow);
    return switch (method) {
      0 => t.closeHintUpi(amount),
      1 => t.closeHintCard(amount),
      2 => t.closeHintCash(amount),
      _ => t.closeHintLink(amount),
    };
  }
}
