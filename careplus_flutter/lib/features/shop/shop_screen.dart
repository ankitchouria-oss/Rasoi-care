import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/care_plus_theme.dart';
import '../../core/widgets/appliance_illustration.dart';
import '../../core/widgets/care_widgets.dart';
import '../../data/models.dart';

/// A cleaning product Rasoi Care sells alongside its repair/service visits —
/// one-time-use kits technicians and customers can buy directly, priced at
/// the real suggested retail prices from the product sheet.
class CleaningProduct {
  const CleaningProduct({
    required this.appliance,
    required this.name,
    required this.contents,
    required this.mrpPaise,
  });
  final Appliance appliance;
  final String name;
  final String contents;
  final int mrpPaise;
}

const _products = [
  CleaningProduct(
    appliance: Appliance.chimney,
    name: 'Chimney Cleaning Kit',
    contents: 'Degreaser concentrate, rinse & shine solution, nylon brush, '
        'plastic scraper, microfiber cloth, nitrile gloves — one-time use, one chimney.',
    mrpPaise: 14900,
  ),
  CleaningProduct(
    appliance: Appliance.cooktop,
    name: 'Cooktop & Hob Cleaning Kit',
    contents: 'Hob cleaner concentrate, rinse & shine solution, soft brush, '
        'plastic scraper, microfiber cloth, nitrile gloves — safe on glass, '
        'ceramic, steel and aluminium.',
    mrpPaise: 11900,
  ),
  CleaningProduct(
    appliance: Appliance.dishwasher,
    name: 'Dishwasher Cleaning Kit',
    contents: 'Dishwasher cleaner, rinse aid, scrub pad, gloves.',
    mrpPaise: 12900,
  ),
  CleaningProduct(
    appliance: Appliance.microwave,
    name: 'Microwave Cleaning Kit',
    contents: 'Microwave cleaner, deodorizer solution, sponge, microfiber cloth, gloves.',
    mrpPaise: 11900,
  ),
  CleaningProduct(
    appliance: Appliance.refrigerator,
    name: 'Refrigerator Cleaning Kit',
    contents: 'Fridge cleaner, deodorizer gel, microfiber cloth, gloves — food-safe formula.',
    mrpPaise: 9900,
  ),
];

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: const Text('Rasoi Care Shop'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          children: [
            Text(
              'Pre-measured, one-time-use cleaning kits for your appliances — '
              'the same products our technicians carry.',
              style: context.type.bodySmall,
            ),
            const SectionHeader('Cleaning kits'),
            for (final p in _products) ...[
              _ProductCard(product: p),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});
  final CleaningProduct product;

  @override
  Widget build(BuildContext context) => CareCard(
        onTap: () => _showDetail(context, product),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.scheme.primary.withValues(alpha: 0.10),
                borderRadius: Radii.rMd,
              ),
              child: ApplianceIllustration(appliance: product.appliance, size: 36),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(product.contents,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: context.type.bodySmall),
                  const SizedBox(height: 7),
                  Text('MRP ${Money.rupees(product.mrpPaise)}',
                      style: CareType.mono(context.scheme.onSurface, size: 14, w: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      );

  void _showDetail(BuildContext context, CleaningProduct p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.scheme.primary.withValues(alpha: 0.10),
                  borderRadius: Radii.rLg,
                ),
                child: ApplianceIllustration(appliance: p.appliance, size: 56),
              ),
            ),
            const SizedBox(height: 16),
            Text(p.name, style: context.type.titleMedium),
            const SizedBox(height: 6),
            Text('MRP ${Money.rupees(p.mrpPaise)}',
                style: CareType.mono(context.scheme.onSurface, size: 17, w: FontWeight.w600)),
            const SizedBox(height: 12),
            Text("What's inside",
                style: context.type.bodySmall!.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(p.contents, style: context.type.bodyMedium),
            const SizedBox(height: 16),
            Text(
              'Ask about this kit on your next booking, or during a technician visit — '
              "there's no direct checkout for shop items yet.",
              style: context.type.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
