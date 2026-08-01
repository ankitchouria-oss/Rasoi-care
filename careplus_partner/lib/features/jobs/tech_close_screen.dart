import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
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

  static const _methods = [
    ('UPI QR', 'Instant settle'),
    ('Card on tap', 'Razorpay POS'),
    ('Cash', 'Deposit by 8 pm'),
    ('Send link', 'SMS and WhatsApp'),
  ];

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(repositoryProvider).closeInvoice(widget.jobId);
    final subtotal = lines.fold<int>(0, (sum, l) => sum + l.amountPaise);
    const prepaid = 80000;
    final collectNow = subtotal - prepaid;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: const Text('Close the job'),
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
                        Eyebrow('Invoice ${widget.jobId}-NSK'),
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
                            const Text('Collect now',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            Text(Money.rupees(collectNow),
                                style: CareType.mono(context.scheme.onSurface,
                                    size: 19, w: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text('${Money.rupees(prepaid)} already prepaid by the customer',
                            style: context.type.bodySmall),
                      ],
                    ),
                  ),
                  SectionHeader('Customer signature',
                      trailing: GestureDetector(
                        onTap: () => _sigKey.currentState?.clear(),
                        child: Text('Clear',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.scheme.primary)),
                      )),
                  CareCard(
                    padding: EdgeInsets.zero,
                    child: SignaturePad(key: _sigKey),
                  ),
                  const SectionHeader('Collect payment'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.05,
                    children: [
                      for (var i = 0; i < _methods.length; i++)
                        CareCard(
                          onTap: () => setState(() => _payMethod = i),
                          borderColor: _payMethod == i ? context.scheme.primary : null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_methods[i].$1,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text(_methods[i].$2, style: context.type.bodySmall),
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
                        Text(_hint(_payMethod, collectNow), style: context.type.bodySmall),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payment received · job closed')));
                    context.go('/tech/jobs');
                  },
                  child: const Text('Mark paid and close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _hint(int method, int collectNow) => switch (method) {
        0 => 'Ask the customer to scan · ${Money.rupees(collectNow)}',
        1 => 'Tap or insert the card on the POS · ${Money.rupees(collectNow)}',
        2 => 'Confirm cash received, then mark paid · ${Money.rupees(collectNow)}',
        _ => 'Payment link sent via SMS and WhatsApp · ${Money.rupees(collectNow)}',
      };
}
