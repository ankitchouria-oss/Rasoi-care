import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // --- location + notifications ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _locationSheet(context, ref),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow('Serving'),
                          const SizedBox(height: 3),
                          Row(children: [
                            Flexible(
                              child: Text('Gangapur Road, Nashik',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.type.titleMedium),
                            ),
                            const SizedBox(width: 5),
                            const Icon(Icons.expand_more, size: 16),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  _RoundBtn(icon: Icons.notifications_none, badge: '3', onTap: () {}),
                  const SizedBox(width: 9),
                  Pressable(
                    onTap: () => context.go('/account'),
                    child: const Blob('RD', size: 38),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  // --- search ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: CareCard(
                      onTap: () => context.go('/services'),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(children: [
                        Icon(Icons.search, color: context.care.inkFaint, size: 20),
                        const SizedBox(width: 10),
                        Text('Search "chimney not sucking smoke"',
                            style: context.type.bodyMedium),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // --- hero ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _HeroBanner(
                        onTap: () => _startBooking(context, ref, Appliance.chimney)),
                  ),
                  // --- categories ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SectionHeader('What needs care today?',
                        actionLabel: 'All', onAction: () => context.go('/services')),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.82,
                      children: [
                        for (final a in Appliance.values)
                          _CategoryTile(
                              appliance: a,
                              onTap: () => _startBooking(context, ref, a)),
                      ],
                    ),
                  ),
                  // --- repeat ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SectionHeader('Book it again',
                        actionLabel: 'History',
                        onAction: () => context.go('/bookings')),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: CareCard(
                      onTap: () => _startBooking(context, ref, Appliance.chimney),
                      child: Row(children: [
                        Blob('◍',
                            glyph: true,
                            bg: context.scheme.secondaryContainer,
                            fg: context.scheme.secondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Chimney deep clean · Elica 90cm',
                                  style: TextStyle(
                                      fontSize: 13.5, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text('Last done 12 Feb · due in 8 days',
                                  style: context.type.bodySmall),
                            ],
                          ),
                        ),
                        const StatusChip('Rebook', height: 30),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // --- AMC strip ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: CareCard(
                      onTap: () => context.push('/plans'),
                      color: context.scheme.secondaryContainer,
                      borderColor: Colors.transparent,
                      child: Row(children: [
                        CareDial(
                            value: 0.45,
                            size: 46,
                            stroke: 7,
                            showTicks: false,
                            color: context.scheme.secondary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Care+ Complete — 2 visits left',
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: context.scheme.secondary)),
                              const SizedBox(height: 3),
                              Text('Renews 04 Nov 2026 · covers 4 appliances',
                                  style: context.type.bodySmall),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: context.scheme.secondary),
                      ]),
                    ),
                  ),
                  // --- offers ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SectionHeader('Offers', actionLabel: 'See all', onAction: () {}),
                  ),
                  SizedBox(
                    height: 118,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: const [
                        _OfferCard(
                            tone: ChipTone.danger,
                            tag: 'Ends in 2 days',
                            title: '30% off first booking',
                            sub: 'Code CARE30 · max ₹400'),
                        SizedBox(width: 9),
                        _OfferCard(
                            tone: ChipTone.success,
                            tag: 'Bundle',
                            title: 'Chimney + Hob together',
                            sub: 'One visit, one technician · ₹1,299'),
                        SizedBox(width: 9),
                        _OfferCard(
                            tone: ChipTone.warning,
                            tag: 'Loyalty',
                            title: '640 Care Coins ready',
                            sub: '₹1 off per coin, up to 20%'),
                      ],
                    ),
                  ),
                  // --- trust ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SectionHeader('Why homes trust Care+'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: [
                      Expanded(child: _StatCard(value: '4.86', label: 'from 12,400 verified visits')),
                      const SizedBox(width: 10),
                      Expanded(child: _StatCard(value: '90 days', label: 'warranty on every repair')),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Service detail reads the appliance from the route and starts the draft there.
  void _startBooking(BuildContext context, WidgetRef ref, Appliance a) =>
      context.push('/services/${a.name}');

  void _locationSheet(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose a location', style: context.type.titleMedium),
            const SizedBox(height: 14),
            for (final ad in repo.addresses()) ...[
              CareCard(
                onTap: () => Navigator.pop(context),
                child: Row(children: [
                  Text(ad.glyph, style: const TextStyle(fontSize: 17)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ad.label,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(ad.line, style: context.type.bodySmall),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Use current location')),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          decoration: BoxDecoration(
              color: context.scheme.primary, borderRadius: Radii.rLg),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('Monsoon tune-up', color: context.scheme.secondary),
              const SizedBox(height: 8),
              SizedBox(
                width: 220,
                child: Text('Chimney deep clean, done in 90 minutes',
                    style: CareType.display(context.scheme.onPrimary, size: 27)),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Text('₹899',
                    style: CareType.mono(context.scheme.onPrimary,
                        size: 19, w: FontWeight.w600)),
                const SizedBox(width: 10),
                Text('₹1,299',
                    style: CareType.mono(
                            context.scheme.onPrimary.withValues(alpha: 0.55),
                            size: 12)
                        .copyWith(decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 10),
                const StatusChip('Save 30%', tone: ChipTone.warning, height: 26),
              ]),
            ],
          ),
        ),
      );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.appliance, required this.onTap});
  final Appliance appliance;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.94,
        child: Container(
          decoration: BoxDecoration(
            color: context.scheme.surface,
            borderRadius: Radii.rMd,
            border: Border.all(color: context.care.hairline),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(appliance.glyph,
                  style: TextStyle(fontSize: 20, color: context.scheme.primary)),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_short(appliance),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, height: 1.2)),
                ),
              ),
            ],
          ),
        ),
      );

  String _short(Appliance a) => switch (a) {
        Appliance.chimney => 'Chimney',
        Appliance.hob => 'Hob',
        Appliance.cooktop => 'Cooktop',
        Appliance.dishwasher => 'Dishwasher',
        Appliance.microwave => 'Microwave',
        Appliance.refrigerator => 'Fridge',
        Appliance.otg => 'OTG',
        Appliance.purifier => 'Purifier',
      };
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.tone, required this.tag, required this.title, required this.sub});
  final ChipTone tone;
  final String tag, title, sub;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 214,
        child: CareCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(tag, tone: tone, height: 24),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(sub, style: context.type.bodySmall),
            ],
          ),
        ),
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => CareCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: CareType.mono(context.scheme.onSurface,
                    size: 22, w: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(label, style: context.type.bodySmall),
          ],
        ),
      );
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, this.badge, required this.onTap});
  final IconData icon;
  final String? badge;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.scheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: context.care.hairline),
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Icon(icon, size: 20),
            if (badge != null)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(
                      color: context.scheme.error, shape: BoxShape.circle),
                  child: Text(badge!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
      );
}
