import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/widgets/appliance_illustration.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/auth_providers.dart';
import '../../state/firestore_providers.dart';
import '../../state/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(savedAddressesProvider);
    final selectedId = ref.watch(selectedAddressIdProvider);
    final current = addresses.isEmpty
        ? null
        : addresses.firstWhere((a) => a.id == selectedId, orElse: () => addresses.first);
    final profile = ref.watch(userProfileStreamProvider).valueOrNull;
    final isMock = ref.read(authFlowProvider.notifier).isMock;
    final displayName = (profile?.name.isNotEmpty ?? false)
        ? profile!.name
        : (isMock ? 'Rohan Deshpande' : '');
    final repo = ref.watch(repositoryProvider);
    final chimneyServices = repo.servicesFor(Appliance.chimney);
    final heroService = chimneyServices.isEmpty
        ? null
        : chimneyServices.firstWhere((s) => s.mostBooked, orElse: () => chimneyServices.first);
    // Rebuild once ApiRepository's real-booking cache lands, same signal
    // BookingsScreen watches — otherwise this stays empty until some other
    // screen happens to trigger a rebuild first.
    ref.watch(bookingsRefreshProvider);
    final completedBookings = repo.bookings(completed: true);
    final lastCompleted = completedBookings.isEmpty ? null : completedBookings.first;
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
                              child: Text(current?.line ?? 'Add your address',
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
                    child: profile?.photoUrl != null
                        ? CircleAvatar(radius: 19, backgroundImage: NetworkImage(profile!.photoUrl!))
                        : Blob(_initialsOf(displayName), size: 38),
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
                  if (heroService != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _HeroBanner(
                          service: heroService,
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
                  // --- repeat --- real, most recent completed booking only;
                  // hidden entirely rather than showing a fabricated
                  // "Elica 90cm, due in 8 days" reminder when there's
                  // nothing real to rebook yet.
                  if (lastCompleted != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SectionHeader('Book it again',
                          actionLabel: 'History',
                          onAction: () => context.go('/bookings')),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: CareCard(
                        onTap: () => _startBooking(context, ref, lastCompleted.appliance),
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
                                Text(lastCompleted.title,
                                    style: const TextStyle(
                                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text('Last done ${lastCompleted.whenLabel}',
                                    style: context.type.bodySmall),
                              ],
                            ),
                          ),
                          const StatusChip('Rebook', height: 30),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
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
    final addresses = ref.read(savedAddressesProvider);
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
            for (final ad in addresses) ...[
              CareCard(
                onTap: () {
                  ref.read(selectedAddressIdProvider.notifier).state = ad.id;
                  Navigator.pop(context);
                },
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

/// "Rohan Deshpande" -> "RD"; falls back to "?" for an empty/unknown name —
/// this used to always be the hardcoded literal "RD" no matter who was
/// actually signed in.
String _initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first[0];
  final last = words.length > 1 ? words.last[0] : '';
  return (first + last).toUpperCase();
}

/// Promotes the most-booked chimney service with its real catalog price —
/// previously a fixed "₹1,199 ~~₹1,599~~ Save 25%" that didn't correspond
/// to any actual service: the ₹1,599 happened to match this service's real
/// price, but the "sale" price and the 25%-off badge next to it were both
/// invented, and tapping through led to the generic catalog with no such
/// discount waiting there.
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.service, required this.onTap});
  final ServiceItem service;
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
              Eyebrow('Most booked', color: context.scheme.secondary),
              const SizedBox(height: 8),
              SizedBox(
                width: 240,
                child: Text('${service.title}, ${service.durationMin} min',
                    style: CareType.display(context.scheme.onPrimary, size: 27)),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Text(Money.rupees(service.pricePaise),
                    style: CareType.mono(context.scheme.onPrimary,
                        size: 19, w: FontWeight.w600)),
                if (service.strikePaise != null) ...[
                  const SizedBox(width: 10),
                  Text(Money.rupees(service.strikePaise!),
                      style: CareType.mono(
                              context.scheme.onPrimary.withValues(alpha: 0.55),
                              size: 12)
                          .copyWith(decoration: TextDecoration.lineThrough)),
                ],
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
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.scheme.primaryContainer,
                ),
                child: ApplianceIllustration(
                    appliance: appliance, size: 24, color: context.scheme.primary),
              ),
              const SizedBox(height: 9),
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
