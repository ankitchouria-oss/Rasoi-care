import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/widgets/appliance_illustration.dart';
import '../../core/widgets/spatial_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../l10n/l10n_extensions.dart';
import '../../state/auth_providers.dart';
import '../../state/firestore_providers.dart';
import '../../state/providers.dart';
import '../booking/select_location_screen.dart';

/// Pilot of the "Spatial UI" visual language — frosted glass panels floating
/// over a dark ambient backdrop instead of the app's usual bordered-card
/// style. Business logic (providers, navigation, real vs. fabricated data)
/// is unchanged from the previous Home screen; only the presentation layer
/// is new. Scoped to this one screen for now — the rest of the app (and the
/// bottom nav bar, part of CustomerShell) keeps the standard Care+ look
/// until this direction is signed off.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final addresses = ref.watch(savedAddressesProvider);
    final selectedId = ref.watch(selectedAddressIdProvider);
    final override = ref.watch(homeAddressOverrideProvider);
    final current = override ??
        (addresses.isEmpty
            ? null
            : addresses.firstWhere((a) => a.id == selectedId, orElse: () => addresses.first));
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
      backgroundColor: SpatialColors.bg0,
      body: SpatialBackdrop(
        child: SafeArea(
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
                            Eyebrow(t.homeServing, color: SpatialColors.textFaint),
                            const SizedBox(height: 3),
                            Row(children: [
                              Flexible(
                                child: Text(current?.line ?? t.homeAddAddress,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.23,
                                        color: SpatialColors.textPrimary)),
                              ),
                              const SizedBox(width: 5),
                              const Icon(Icons.expand_more, size: 16, color: SpatialColors.textMuted),
                            ]),
                          ],
                        ),
                      ),
                    ),
                    SpatialIconButton(
                        icon: Icons.notifications_none,
                        onTap: () => _notificationsComingSoon(context)),
                    const SizedBox(width: 9),
                    Pressable(
                      onTap: () => context.go('/account'),
                      child: profile?.photoUrl != null
                          ? CircleAvatar(radius: 19, backgroundImage: NetworkImage(profile!.photoUrl!))
                          : Blob(_initialsOf(displayName),
                              size: 38,
                              bg: SpatialColors.glowMint.withValues(alpha: 0.16),
                              fg: SpatialColors.glowMint),
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
                      child: GlassPanel(
                        onTap: () => context.go('/services'),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        borderRadius: Radii.rLg,
                        child: Row(children: [
                          const Icon(Icons.search, color: SpatialColors.textMuted, size: 20),
                          const SizedBox(width: 10),
                          Text(t.homeSearchHint,
                              style: const TextStyle(fontSize: 13, color: SpatialColors.textMuted)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // --- hero ---
                    if (heroService != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _SpatialHeroBanner(
                            service: heroService,
                            onTap: () => _startBooking(context, ref, Appliance.chimney)),
                      ),
                    // --- categories ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SpatialSectionHeader(t.homeWhatNeedsCare,
                          actionLabel: t.homeAll, onAction: () => context.go('/services')),
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
                            _SpatialCategoryTile(
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
                        child: SpatialSectionHeader(t.homeBookItAgain,
                            actionLabel: t.homeHistory,
                            onAction: () => context.go('/bookings')),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GlassPanel(
                          onTap: () => _startBooking(context, ref, lastCompleted.appliance),
                          borderRadius: Radii.rLg,
                          child: Row(children: [
                            Blob('◍',
                                glyph: true,
                                bg: SpatialColors.glowBrass.withValues(alpha: 0.22),
                                fg: SpatialColors.glowBrass),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(lastCompleted.title,
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: SpatialColors.textPrimary)),
                                  const SizedBox(height: 3),
                                  Text(t.homeLastDone(lastCompleted.whenLabel),
                                      style: const TextStyle(
                                          fontSize: 11.5, color: SpatialColors.textMuted)),
                                ],
                              ),
                            ),
                            StatusChip(t.homeRebook, height: 30, tone: ChipTone.selected),
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
      ),
    );
  }

  // Service detail reads the appliance from the route and starts the draft there.
  void _startBooking(BuildContext context, WidgetRef ref, Appliance a) =>
      context.push('/services/${a.name}');

  /// The bell used to show a hardcoded "3" badge and do nothing when
  /// tapped — there's no real notifications system behind it (no push
  /// setup, no backend feed), so rather than keep faking a count, this
  /// says so plainly, same as the Account screen's other not-built-yet
  /// features (Wallet and Care Coins, Help and support).
  void _notificationsComingSoon(BuildContext context) {
    final t = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.notificationsTitle, style: context.type.titleMedium),
            const SizedBox(height: 12),
            Text(t.notificationsBody, style: context.type.bodyMedium),
          ],
        ),
      ),
    );
  }

  Future<void> _locationSheet(BuildContext context, WidgetRef ref) async {
    final currentId = ref.read(selectedAddressIdProvider);
    final picked = await Navigator.of(context).push<SavedAddress>(
      MaterialPageRoute(builder: (_) => SelectLocationScreen(currentId: currentId)),
    );
    if (picked == null) return;
    ref.read(homeAddressOverrideProvider.notifier).state = picked;
    ref.read(selectedAddressIdProvider.notifier).state = picked.id;
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
class _SpatialHeroBanner extends StatelessWidget {
  const _SpatialHeroBanner({required this.service, required this.onTap});
  final ServiceItem service;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GlassPanel(
        onTap: onTap,
        elevated: true,
        borderRadius: Radii.rLg,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(context.l10n.homeMostBooked, color: SpatialColors.glowBrass),
            const SizedBox(height: 8),
            SizedBox(
              width: 240,
              child: Text('${service.title}, ${service.durationMin} min',
                  style: CareType.display(SpatialColors.textPrimary, size: 27)),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Text(Money.rupees(service.pricePaise),
                  style: CareType.mono(SpatialColors.glowMint, size: 19, w: FontWeight.w600)),
              if (service.strikePaise != null) ...[
                const SizedBox(width: 10),
                Text(Money.rupees(service.strikePaise!),
                    style: CareType.mono(SpatialColors.textFaint, size: 12)
                        .copyWith(decoration: TextDecoration.lineThrough)),
              ],
            ]),
          ],
        ),
      );
}

class _SpatialCategoryTile extends StatelessWidget {
  const _SpatialCategoryTile({required this.appliance, required this.onTap});
  final Appliance appliance;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GlassPanel(
        onTap: onTap,
        borderRadius: Radii.rMd,
        blur: 20,
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
                color: SpatialColors.glowMint.withValues(alpha: 0.18),
              ),
              child: ApplianceIllustration(
                  appliance: appliance, size: 24, color: SpatialColors.glowMint),
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_short(context, appliance),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        color: SpatialColors.textPrimary)),
              ),
            ),
          ],
        ),
      );

  String _short(BuildContext context, Appliance a) {
    final t = context.l10n;
    return switch (a) {
      Appliance.chimney => t.applianceChimney,
      Appliance.hob => t.applianceHob,
      Appliance.cooktop => t.applianceCooktop,
      Appliance.dishwasher => t.applianceDishwasher,
      Appliance.microwave => t.applianceMicrowave,
      Appliance.refrigerator => t.applianceFridge,
      Appliance.otg => t.applianceOtg,
      Appliance.purifier => t.appliancePurifier,
    };
  }
}
