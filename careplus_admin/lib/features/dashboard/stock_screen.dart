import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../state/providers.dart';
import 'dashboard_header.dart';

class StockScreen extends ConsumerWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(repositoryProvider).stock();
    final lowCount = stock.where((s) => s.low).length;
    final soonest = stock.reduce((a, b) => a.daysLeft < b.daysLeft ? a : b);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const DashboardHeader(eyebrow: 'Rasoi Care operations', title: 'Stock & inventory'),
            Expanded(
              child: ListView(
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
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.scheme.error)),
                        const SizedBox(height: 6),
                        Text(
                            '${soonest.name} runs out in ${soonest.daysLeft} days at the current burn rate.',
                            style: context.type.bodySmall),
                        const SizedBox(height: 11),
                        OutlinedButton(
                          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Purchase order drafted'))),
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
                                    style: const TextStyle(
                                        fontSize: 13.5, fontWeight: FontWeight.w700)),
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
                            const SizedBox(height: 8),
                            Text(
                                '${s.burnPerDay.toStringAsFixed(1)}/day · ${s.daysLeft} days of cover left',
                                style: context.type.bodySmall),
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
