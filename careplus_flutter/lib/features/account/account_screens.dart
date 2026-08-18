import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/api/api_repository.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../state/auth_providers.dart';
import '../../state/firestore_providers.dart';

/// True while a just-picked profile photo is uploading — the avatar shows a
/// spinner instead of letting you fire off a second upload mid-flight.
final _uploadingPhotoProvider = StateProvider<bool>((ref) => false);

// ============================================================ BOOKINGS
class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});
  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    // Rebuild when ApiRepository's real-booking cache changes (initial
    // fetch lands, or a booking is just created) — see providers.dart.
    ref.watch(bookingsRefreshProvider);
    final upcoming = repo.bookings();
    final past = repo.bookings(completed: true);
    final cancelled = repo.bookings(status: BookingStatus.cancelled);

    return Scaffold(
      appBar: AppBar(title: const Text('Your bookings')),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _Tabs(
                labels: const ['Upcoming', 'Completed', 'Cancelled'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: switch (_tab) {
                0 => upcoming.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: EmptyState(
                          glyph: '◌',
                          title: 'No upcoming visits',
                          body: 'Book a service and it shows up here.',
                          action: OutlinedButton(
                              onPressed: () => context.go('/services'),
                              child: const Text('Browse services')),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                        children: [
                          for (final b in upcoming) ...[
                            _BookingCard(booking: b, onCancel: () => _confirmCancel(b)),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
                1 => ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                    children: [
                      for (final b in past) ...[
                        _BookingCard(booking: b, completed: true),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                _ => cancelled.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: EmptyState(
                          glyph: '◌',
                          title: 'Nothing cancelled',
                          body: 'Cancelled visits appear here with any fee charged.',
                          action: OutlinedButton(
                              onPressed: () => context.go('/services'),
                              child: const Text('Browse services')),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                        children: [
                          for (final b in cancelled) ...[
                            _BookingCard(booking: b),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel(Booking booking) async {
    final feePreview = ApiRepository.cancellationFeePreviewPaise(booking);
    final feeLine = feePreview == null
        ? "This job's already too far along to cancel."
        : feePreview == 0
            ? 'No technician has taken this job yet — cancelling now is free.'
            : 'A technician has already committed time to this job. Cancelling now applies a ${Money.rupees(feePreview)} fee, credited to them — not Rasoi Care.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(feeLine),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep booking')),
          if (feePreview != null)
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Cancel booking')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repo = ref.read(repositoryProvider);
    if (repo is! ApiRepository) return;
    final fee = await repo.cancelBooking(booking.id);
    if (!mounted) return;
    ref.read(bookingsRefreshProvider.notifier).state++;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(fee == null
            ? 'Could not cancel — check connection and try again.'
            : fee == 0
                ? 'Booking cancelled — no fee.'
                : 'Booking cancelled — ${Money.rupees(fee)} fee credited to the technician.')));
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, this.completed = false, this.onCancel});
  final Booking booking;
  final bool completed;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final tone = switch (booking.status) {
      BookingStatus.onTheWay => ChipTone.warning,
      BookingStatus.completed => ChipTone.success,
      BookingStatus.cancelled => ChipTone.danger,
      _ => ChipTone.neutral,
    };
    return CareCard(
      onTap: () => booking.status == BookingStatus.onTheWay
          ? context.push('/booking/${booking.id}/track')
          : context.push('/booking/${booking.id}/invoice'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatusChip(booking.status.label, tone: tone, height: 24),
              Mono(booking.id.split('-').take(2).join('-'), color: context.care.inkMuted),
            ],
          ),
          const SizedBox(height: 11),
          Text(booking.title,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            completed
                ? '${booking.whenLabel} · ${Money.rupees(booking.totalPaise)}${booking.stars != null ? ' · ${'★' * booking.stars!}' : ''}'
                : booking.whenLabel,
            style: context.type.bodySmall,
          ),
          if (booking.status == BookingStatus.cancelled &&
              booking.cancellationFeePaise != null) ...[
            const SizedBox(height: 4),
            Text(
                booking.cancellationFeePaise == 0
                    ? 'No cancellation fee'
                    : '${Money.rupees(booking.cancellationFeePaise!)} fee credited to the technician',
                style: context.type.bodySmall),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(foregroundColor: context.scheme.error),
                child: const Text('Cancel booking'),
              ),
            ),
          ],
          if (booking.technician != null) ...[
            const Divider(height: 24),
            Row(children: [
              Blob(booking.technician!.initials, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${booking.technician!.name} · 14 min away',
                    style: context.type.bodySmall),
              ),
              Text('Track ›',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.scheme.primary)),
            ]),
          ],
        ],
      ),
    );
  }
}

// ============================================================ ACCOUNT
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final profile = ref.watch(userProfileStreamProvider).valueOrNull;
    final isMock = ref.read(authFlowProvider.notifier).isMock;
    final name = (profile?.name.isNotEmpty ?? false)
        ? profile!.name
        : (isMock ? 'Rohan Deshpande' : 'Your name');
    final phone = (profile?.phone.isNotEmpty ?? false)
        ? _formatIndianPhone(profile!.phone)
        : (isMock ? '+91 98220 41537' : '');
    final address = profile?.address ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.settings_outlined))],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          children: [
            CareCard(
              child: Row(children: [
                _ProfileAvatar(name: name, photoUrl: profile?.photoUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(phone, style: context.type.bodySmall),
                      ],
                      if (address.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(address, style: context.type.bodySmall, maxLines: 2),
                      ],
                      const SizedBox(height: 7),
                      const StatusChip('Silver member', tone: ChipTone.warning, height: 22),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _MiniStat(label: 'Visits', value: '14')),
              const SizedBox(width: 10),
              Expanded(child: _MiniStat(label: 'Saved with Care+', value: '₹8,420')),
            ]),
            const SectionHeader('Your Care+'),
            CareCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                _NavRow(icon: Icons.event_note, label: 'Bookings and history',
                    onTap: () => context.go('/bookings')),
                _NavRow(icon: Icons.shield_outlined, label: 'Plans, warranty, appliances',
                    onTap: () => context.push('/plans')),
                _NavRow(icon: Icons.account_balance_wallet_outlined,
                    label: 'Wallet and Care Coins', onTap: () {}),
                _NavRow(icon: Icons.chat_bubble_outline, label: 'Help and support',
                    onTap: () {}, last: true),
              ]),
            ),
            const SectionHeader('Preferences'),
            CareCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.dark_mode_outlined, size: 20),
                    const SizedBox(width: 13),
                    const Expanded(
                        child: Text('Dark mode',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                    Switch(
                      value: mode == ThemeMode.dark,
                      onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
                    ),
                  ]),
                ),
                _NavRow(icon: Icons.language, label: 'Language',
                    trailing: 'English ›', onTap: () {}, last: true),
              ]),
            ),
            const SectionHeader('Legal'),
            CareCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                _NavRow(
                    icon: Icons.description_outlined,
                    label: 'Terms and conditions',
                    onTap: () => _showTerms(context),
                    last: true),
              ]),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  ref.read(authFlowProvider.notifier).reset();
                  if (context.mounted) context.go('/login');
                },
                style: TextButton.styleFrom(foregroundColor: context.scheme.error),
                child: const Text('Sign out'),
              ),
            ),
            const SizedBox(height: 6),
            Center(child: Text('Care+ 0.1.0 · build 1', style: context.type.bodySmall)),
          ],
        ),
      ),
    );
  }

  void _showTerms(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Terms and conditions', style: context.type.titleMedium),
            const SizedBox(height: 12),
            Text(
                "Rasoi Care's published terms of service aren't live yet. "
                "Check back here once they are — we won't show placeholder legal text in the meantime.",
                style: context.type.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// The account photo — a real uploaded photo when there is one, otherwise
/// the initials blob. Tapping it opens the gallery to pick a new one, real
/// image_picker + Firebase Storage upload — there was previously no way to
/// set a profile photo at all, just this fixed initials circle.
class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar({required this.name, required this.photoUrl});
  final String name;
  final String? photoUrl;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !context.mounted) return;
    ref.read(_uploadingPhotoProvider.notifier).state = true;
    final url = await ref.read(userProfileServiceProvider).uploadPhoto(File(picked.path));
    ref.read(_uploadingPhotoProvider.notifier).state = false;
    if (url == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update your photo — check connection.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploading = ref.watch(_uploadingPhotoProvider);
    return GestureDetector(
      onTap: uploading ? null : () => _pick(context, ref),
      child: Stack(
        children: [
          if (uploading)
            const SizedBox(
                width: 56,
                height: 56,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (photoUrl != null)
            CircleAvatar(radius: 28, backgroundImage: NetworkImage(photoUrl!))
          else
            Blob(_initialsOf(name),
                size: 56, bg: context.scheme.primary, fg: context.scheme.onPrimary),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.scheme.primary,
                border: Border.all(color: context.scheme.surface, width: 1.5),
              ),
              child: Icon(Icons.camera_alt, size: 11, color: context.scheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Rohan Deshpande" -> "RD"; falls back to a single "?" for an empty name.
String _initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first[0];
  final last = words.length > 1 ? words.last[0] : '';
  return (first + last).toUpperCase();
}

/// "+919822041537" -> "+91 98220 41537". Anything that doesn't match the
/// expected +91-and-10-digits shape is shown as-is rather than mangled.
String _formatIndianPhone(String raw) {
  final match = RegExp(r'^\+91(\d{5})(\d{5})$').firstMatch(raw);
  if (match == null) return raw;
  return '+91 ${match.group(1)} ${match.group(2)}';
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => CareCard(
        radius: Radii.rMd,
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(label),
            const SizedBox(height: 6),
            Text(value,
                style: CareType.mono(context.scheme.onSurface, size: 20, w: FontWeight.w600)),
          ],
        ),
      );
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap, this.trailing, this.last = false});
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;
  final bool last;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(bottom: BorderSide(color: context.care.hairline)),
          ),
          child: Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 13),
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
            Text(trailing ?? '›', style: context.type.bodySmall),
          ]),
        ),
      );
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: context.scheme.surfaceContainerHigh, borderRadius: Radii.rSm),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: Motion.press,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? context.scheme.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: i == index
                          ? Shadows.card(Theme.of(context).brightness == Brightness.dark)
                          : null,
                    ),
                    child: Text(labels[i],
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: i == index
                                ? context.scheme.onSurface
                                : context.care.inkMuted)),
                  ),
                ),
              ),
          ],
        ),
      );
}

// ============================================================ PLANS (AMC)
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          leading: BackButton(onPressed: context.pop),
          title: const Text('Plans and warranty')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          children: [
            CareCard(
              color: context.scheme.primary,
              borderColor: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow('Active plan', color: context.scheme.secondary),
                  const SizedBox(height: 8),
                  Text('Care+ Complete',
                      style: CareType.display(context.scheme.onPrimary, size: 24)),
                  const SizedBox(height: 16),
                  Row(children: [
                    _PlanStat(label: 'Visits left', value: '2 of 4'),
                    const SizedBox(width: 20),
                    _PlanStat(label: 'Renews', value: '04 Nov'),
                  ]),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: Radii.pill,
                    child: LinearProgressIndicator(
                      value: 0.5,
                      minHeight: 7,
                      backgroundColor: context.scheme.onPrimary.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation(context.scheme.secondary),
                    ),
                  ),
                ],
              ),
            ),
            const SectionHeader('Upgrade or add a plan'),
            _PlanCard(
                name: 'Essential',
                price: '₹1,899',
                blurb: '2 visits · 1 appliance · 10% off repairs'),
            const SizedBox(height: 10),
            _PlanCard(
                name: 'Complete',
                price: '₹3,499',
                blurb: '4 visits · up to 4 appliances · 20% off repairs · priority slots',
                current: true),
            const SizedBox(height: 10),
            _PlanCard(
                name: 'Home Suite',
                price: '₹5,999',
                blurb: 'Unlimited visits · every kitchen appliance · 30% off · 4-hr response',
                best: true),
          ],
        ),
      ),
    );
  }
}

class _PlanStat extends StatelessWidget {
  const _PlanStat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: context.scheme.onPrimary.withValues(alpha: 0.6))),
          Text(value,
              style: CareType.mono(context.scheme.onPrimary, size: 19, w: FontWeight.w600)),
        ],
      );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.name, required this.price, required this.blurb, this.current = false, this.best = false});
  final String name, price, blurb;
  final bool current, best;
  @override
  Widget build(BuildContext context) => CareCard(
        onTap: () {},
        borderColor: current ? context.scheme.primary : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Text(name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  if (current) const StatusChip('Current', tone: ChipTone.success, height: 22),
                  if (best) const StatusChip('Best value', tone: ChipTone.warning, height: 22),
                ]),
                Text('$price/yr',
                    style: CareType.mono(context.scheme.onSurface, size: 15, w: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(blurb, style: context.type.bodySmall),
          ],
        ),
      );
}
