import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/care_plus_theme.dart';
import '../../core/widgets/appliance_illustration.dart';
import '../../core/widgets/care_widgets.dart';
import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/l10n_extensions.dart';
import '../../state/providers.dart';

/// A cleaning product Rasoi Care sells alongside its repair/service visits —
/// one-time-use kits technicians and customers can buy directly, priced at
/// the real suggested retail prices from the product sheet. `id` must match
/// a key in SHOP_PRODUCTS in app.py — that's the source of truth for price,
/// this list is only for display. Name/contents aren't stored here (unlike
/// price) since they need a real translation per locale — see
/// [productName]/[productContents].
class CleaningProduct {
  const CleaningProduct({
    required this.id,
    required this.appliance,
    required this.mrpPaise,
  });
  final String id;
  final Appliance appliance;
  final int mrpPaise;
}

/// Public (not file-private) because PaymentScreen (booking_screens.dart)
/// needs to resolve `shopCartProvider`'s {productId: qty} map back to real
/// names/prices to show product line items on the same bill as any booked
/// service — see the module doc-comment on shopCartProvider.
const shopProducts = [
  CleaningProduct(id: 'chimney_kit', appliance: Appliance.chimney, mrpPaise: 14900),
  CleaningProduct(id: 'cooktop_kit', appliance: Appliance.cooktop, mrpPaise: 11900),
  CleaningProduct(id: 'dishwasher_kit', appliance: Appliance.dishwasher, mrpPaise: 12900),
  CleaningProduct(id: 'microwave_kit', appliance: Appliance.microwave, mrpPaise: 11900),
  CleaningProduct(id: 'refrigerator_kit', appliance: Appliance.refrigerator, mrpPaise: 9900),
];

String productName(String id, AppLocalizations t) => switch (id) {
      'chimney_kit' => t.shopChimneyKitName,
      'cooktop_kit' => t.shopCooktopKitName,
      'dishwasher_kit' => t.shopDishwasherKitName,
      'microwave_kit' => t.shopMicrowaveKitName,
      'refrigerator_kit' => t.shopFridgeKitName,
      _ => id,
    };

String productContents(String id, AppLocalizations t) => switch (id) {
      'chimney_kit' => t.shopChimneyKitContents,
      'cooktop_kit' => t.shopCooktopKitContents,
      'dishwasher_kit' => t.shopDishwasherKitContents,
      'microwave_kit' => t.shopMicrowaveKitContents,
      'refrigerator_kit' => t.shopFridgeKitContents,
      _ => '',
    };

class ShopScreen extends ConsumerWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(shopCartProvider);
    final itemCount = cart.values.fold(0, (a, b) => a + b);
    final totalPaise = cart.entries.fold(
        0, (sum, e) => sum + shopProducts.firstWhere((p) => p.id == e.key).mrpPaise * e.value);
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: Text(t.shopTitle),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, itemCount > 0 ? 100 : 30),
          children: [
            Text(t.shopIntro, style: context.type.bodySmall),
            SectionHeader(t.shopKitsHeader),
            for (final p in shopProducts) ...[
              _ProductCard(product: p, qty: cart[p.id] ?? 0),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      bottomNavigationBar: itemCount == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: FilledButton(
                  onPressed: () => context.push('/book/payment'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: Text(t.shopCheckout(itemCount, Money.rupees(totalPaise))),
                ),
              ),
            ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product, required this.qty});
  final CleaningProduct product;
  final int qty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    return CareCard(
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
                  Text(productName(product.id, t),
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(productContents(product.id, t),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: context.type.bodySmall),
                  const SizedBox(height: 9),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t.shopMrp(Money.rupees(product.mrpPaise)),
                          style: CareType.mono(context.scheme.onSurface,
                              size: 14, w: FontWeight.w600)),
                      _QtyStepper(
                        qty: qty,
                        onChanged: (q) =>
                            ref.read(shopCartProvider.notifier).setQty(product.id, q),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.qty, required this.onChanged});
  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (qty == 0) {
      return OutlinedButton(
        onPressed: () => onChanged(1),
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 14)),
        child: Text(context.l10n.shopAdd,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: context.scheme.primary.withValues(alpha: 0.10),
        borderRadius: Radii.rSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => onChanged(qty - 1),
          ),
          Text('$qty', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => onChanged(qty + 1),
          ),
        ],
      ),
    );
  }
}
