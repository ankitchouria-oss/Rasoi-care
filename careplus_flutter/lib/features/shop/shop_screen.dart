import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/care_plus_theme.dart';
import '../../core/widgets/appliance_illustration.dart';
import '../../core/widgets/care_widgets.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

/// A cleaning product Rasoi Care sells alongside its repair/service visits —
/// one-time-use kits technicians and customers can buy directly, priced at
/// the real suggested retail prices from the product sheet. `id` must match
/// a key in SHOP_PRODUCTS in app.py — that's the source of truth for price,
/// this list is only for display.
class CleaningProduct {
  const CleaningProduct({
    required this.id,
    required this.appliance,
    required this.name,
    required this.contents,
    required this.mrpPaise,
  });
  final String id;
  final Appliance appliance;
  final String name;
  final String contents;
  final int mrpPaise;
}

const _products = [
  CleaningProduct(
    id: 'chimney_kit',
    appliance: Appliance.chimney,
    name: 'Chimney Cleaning Kit',
    contents: 'Degreaser concentrate, rinse & shine solution, microfiber cloth, '
        'nitrile gloves — one-time use, one chimney.',
    mrpPaise: 14900,
  ),
  CleaningProduct(
    id: 'cooktop_kit',
    appliance: Appliance.cooktop,
    name: 'Cooktop & Hob Cleaning Kit',
    contents: 'Hob cleaner concentrate, rinse & shine solution, microfiber cloth, '
        'nitrile gloves — safe on glass, ceramic, steel and aluminium.',
    mrpPaise: 11900,
  ),
  CleaningProduct(
    id: 'dishwasher_kit',
    appliance: Appliance.dishwasher,
    name: 'Dishwasher Cleaning Kit',
    contents: 'Dishwasher cleaner, rinse aid, scrub pad, gloves.',
    mrpPaise: 12900,
  ),
  CleaningProduct(
    id: 'microwave_kit',
    appliance: Appliance.microwave,
    name: 'Microwave Cleaning Kit',
    contents: 'Microwave cleaner, deodorizer solution, sponge, microfiber cloth, gloves.',
    mrpPaise: 11900,
  ),
  CleaningProduct(
    id: 'refrigerator_kit',
    appliance: Appliance.refrigerator,
    name: 'Refrigerator Cleaning Kit',
    contents: 'Fridge cleaner, deodorizer gel, microfiber cloth, gloves — food-safe formula.',
    mrpPaise: 9900,
  ),
];

/// productId -> quantity, kept at the ShopScreen route level (not a global
/// provider) so the cart resets when someone leaves the shop rather than
/// silently persisting an old selection across visits.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});
  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  final Map<String, int> _cart = {};

  int get _itemCount => _cart.values.fold(0, (a, b) => a + b);
  int get _totalPaise => _cart.entries.fold(
      0, (sum, e) => sum + _products.firstWhere((p) => p.id == e.key).mrpPaise * e.value);

  void _setQty(String productId, int qty) {
    setState(() {
      if (qty <= 0) {
        _cart.remove(productId);
      } else {
        _cart[productId] = qty;
      }
    });
  }

  Future<void> _checkout() async {
    final totalPaise = await Navigator.of(context).push<int>(
      MaterialPageRoute(
          builder: (_) => ShopPaymentScreen(cart: Map.of(_cart), products: _products)),
    );
    if (totalPaise == null || !mounted) return;
    setState(() => _cart.clear());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order placed — ${Money.rupees(totalPaise)}, pay on delivery.')));
  }

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
          padding: EdgeInsets.fromLTRB(20, 0, 20, _itemCount > 0 ? 100 : 30),
          children: [
            Text(
              'Pre-measured, one-time-use cleaning kits for your appliances — '
              'the same products our technicians carry.',
              style: context.type.bodySmall,
            ),
            const SectionHeader('Cleaning kits'),
            for (final p in _products) ...[
              _ProductCard(
                product: p,
                qty: _cart[p.id] ?? 0,
                onQtyChanged: (q) => _setQty(p.id, q),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _itemCount == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                child: FilledButton(
                  onPressed: _checkout,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50)),
                  child: Text('Checkout · $_itemCount ${_itemCount == 1 ? 'item' : 'items'} · '
                      '${Money.rupees(_totalPaise)}'),
                ),
              ),
            ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.qty, required this.onQtyChanged});
  final CleaningProduct product;
  final int qty;
  final ValueChanged<int> onQtyChanged;

  @override
  Widget build(BuildContext context) => CareCard(
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
                  const SizedBox(height: 9),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('MRP ${Money.rupees(product.mrpPaise)}',
                          style: CareType.mono(context.scheme.onSurface,
                              size: 14, w: FontWeight.w600)),
                      _QtyStepper(qty: qty, onChanged: onQtyChanged),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
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
        child: const Text('Add', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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

/// A real payment/review page for the shop cart — mirrors the service
/// booking flow's "Review and pay" screen (same grouped payment-method
/// list, same "display-only, no gateway wired up" honesty) instead of the
/// lightweight confirm sheet this used to be. Kit MRPs are the final,
/// all-inclusive price — unlike a service booking there's no visit fee or
/// GST stacked on top, so the order total here is just the cart subtotal.
/// Pops with the real placed total on success so ShopScreen can clear its
/// cart and show a confirmation; pops with null if cancelled or it failed.
class ShopPaymentScreen extends ConsumerStatefulWidget {
  const ShopPaymentScreen({super.key, required this.cart, required this.products});
  final Map<String, int> cart;
  final List<CleaningProduct> products;

  @override
  ConsumerState<ShopPaymentScreen> createState() => _ShopPaymentScreenState();
}

class _ShopPaymentScreenState extends ConsumerState<ShopPaymentScreen> {
  bool _placing = false;
  String _paymentId = 'cod';

  int get _totalPaise => widget.cart.entries.fold(
      0, (sum, e) => sum + widget.products.firstWhere((p) => p.id == e.key).mrpPaise * e.value);

  Future<void> _place() async {
    setState(() => _placing = true);
    final result = await ref.read(apiRepositoryProvider).placeShopOrder(widget.cart);
    if (!mounted) return;
    setState(() => _placing = false);
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    Navigator.of(context).pop(result.totalPaise);
  }

  @override
  Widget build(BuildContext context) {
    final paymentMethodsList = ref.watch(repositoryProvider).paymentMethods();
    final itemCount = widget.cart.values.fold(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: Text('Payment options'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('$itemCount ${itemCount == 1 ? 'item' : 'items'} · Total: '
                '${Money.rupees(_totalPaise)}'),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: [
            CareCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in widget.cart.entries) ...[
                    Builder(builder: (context) {
                      final p = widget.products.firstWhere((p) => p.id == e.key);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Expanded(
                            child: Text('${p.name} × ${e.value}',
                                style: const TextStyle(
                                    fontSize: 13.5, fontWeight: FontWeight.w600)),
                          ),
                          Text(Money.rupees(p.mrpPaise * e.value), style: context.type.bodyMedium),
                        ]),
                      );
                    }),
                  ],
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total (MRP, all-inclusive)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(Money.rupees(_totalPaise),
                          style: CareType.mono(context.scheme.onSurface,
                              size: 17, w: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            // Same honesty as the booking flow's PaymentScreen: no card/UPI/
            // wallet gateway is wired up anywhere in this app. Real payment
            // collection is pay-on-delivery regardless of what's selected.
            for (var i = 0; i < paymentMethodsList.length; i++) ...[
              if (i == 0 || paymentMethodsList[i].section != paymentMethodsList[i - 1].section)
                SectionHeader(paymentMethodsList[i].section),
              CareCard(
                onTap: () => setState(() => _paymentId = paymentMethodsList[i].id),
                borderColor:
                    _paymentId == paymentMethodsList[i].id ? context.scheme.primary : null,
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: context.scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(paymentMethodsList[i].glyph, style: const TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(paymentMethodsList[i].name,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        Text(paymentMethodsList[i].detail, style: context.type.bodySmall),
                      ],
                    ),
                  ),
                  Icon(
                      _paymentId == paymentMethodsList[i].id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: _paymentId == paymentMethodsList[i].id
                          ? context.scheme.primary
                          : context.care.hairline),
                ]),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: FilledButton(
            onPressed: _placing ? null : _place,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _placing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('Place order · ${Money.rupees(_totalPaise)}'),
          ),
        ),
      ),
    );
  }
}
