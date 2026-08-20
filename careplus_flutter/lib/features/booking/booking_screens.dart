import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

// A thin frame every booking step shares: progress bar + step caption + dock.
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.progress,
    required this.caption,
    required this.body,
    required this.dock,
  });
  final String title, caption;
  final double progress;
  final Widget body, dock;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            leading: BackButton(onPressed: context.pop), title: Text(title)),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    ProgressBar(progress),
                    const SizedBox(height: 7),
                    Mono(caption, color: context.care.inkMuted),
                    const SizedBox(height: 18),
                    body,
                  ],
                ),
              ),
              Dock(child: dock),
            ],
          ),
        ),
      );
}

// ============================================================ 1 · ISSUE
class IssueScreen extends ConsumerWidget {
  const IssueScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final vm = ref.read(bookingDraftProvider.notifier);
    return _StepScaffold(
      title: 'Describe the problem',
      progress: 0.25,
      caption: 'Step 1 of 4 — issue',
      dock: SizedBox(
        width: double.infinity,
        child: FilledButton(
            onPressed: () => context.push('/book/slot'),
            child: const Text('Pick a time slot')),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Pick everything you\'ve noticed. The technician sees this before they arrive and packs the right parts.',
              style: context.type.bodyMedium),
          const SizedBox(height: 18),
          for (var i = 0; i < draft.issues.length; i++) ...[
            _IssueRow(issue: draft.issues[i], onTap: () => vm.toggleIssue(i)),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          TextFormField(
            initialValue: draft.notes,
            maxLines: 3,
            onChanged: vm.setNotes,
            decoration: const InputDecoration(labelText: 'Anything else? (optional)'),
          ),
          const SizedBox(height: 22),
          Eyebrow('Photos help — add up to 4'),
          const SizedBox(height: 10),
          const _PhotoPicker(),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.issue, required this.onTap});
  final Issue issue;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => CareCard(
        onTap: onTap,
        borderColor: issue.selected ? context.scheme.primary : null,
        child: Row(children: [
          Icon(issue.selected ? Icons.check_box : Icons.check_box_outline_blank,
              color: issue.selected ? context.scheme.primary : context.care.hairline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(issue.label,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(issue.hint, style: context.type.bodySmall),
              ],
            ),
          ),
        ]),
      );
}

/// Up to 4 real photos, picked from the camera or gallery — previously four
/// decorative boxes captioned "Filter"/"Model tag"/"Add"/"Gallery" (leftover
/// labels that didn't match any actual action; tapping one did nothing).
/// These stay local to the booking flow rather than being uploaded anywhere
/// — there's no backend field yet to attach photos to a booking, so showing
/// them as sent to the technician would be exactly the kind of fabrication
/// this app avoids elsewhere. The customer still gets a real, working way to
/// review what they're about to describe before confirming the booking.
class _PhotoPicker extends StatefulWidget {
  const _PhotoPicker();
  @override
  State<_PhotoPicker> createState() => _PhotoPickerState();
}

class _PhotoPickerState extends State<_PhotoPicker> {
  static const _maxPhotos = 4;
  final List<File> _photos = [];

  Future<void> _add() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (picked != null && mounted) setState(() => _photos.add(File(picked.path)));
  }

  void _remove(int i) => setState(() => _photos.removeAt(i));

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < _maxPhotos; i++) ...[
        Expanded(
          child: i < _photos.length
              ? _FilledPhotoTile(file: _photos[i], onRemove: () => _remove(i))
              : _EmptyPhotoTile(onTap: i == _photos.length ? _add : null),
        ),
        if (i != _maxPhotos - 1) const SizedBox(width: 10),
      ],
    ]);
  }
}

class _EmptyPhotoTile extends StatelessWidget {
  const _EmptyPhotoTile({required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.rMd,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.scheme.surfaceContainerHigh,
              borderRadius: Radii.rMd,
              border: Border.all(color: context.care.hairline),
            ),
            child: Icon(
              onTap != null ? Icons.add_a_photo_outlined : Icons.camera_alt_outlined,
              size: 18,
              color: context.care.inkFaint,
            ),
          ),
        ),
      );
}

class _FilledPhotoTile extends StatelessWidget {
  const _FilledPhotoTile({required this.file, required this.onRemove});
  final File file;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: Radii.rMd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(file, fit: BoxFit.cover),
              Positioned(
                right: 3,
                top: 3,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, size: 13, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

// ============================================================ 2 · SLOT
class SlotScreen extends ConsumerWidget {
  const SlotScreen({super.key});

  /// Today plus the next 5 real calendar days — this used to be six days
  /// hardcoded to "24 Jul – 29 Jul" regardless of the actual date, so every
  /// booking after that one week showed the wrong "Today".
  static List<(String, String)> get _days {
    final now = DateTime.now();
    return [
      for (var i = 0; i < 6; i++)
        (
          i == 0 ? 'Today' : DateFormat('E').format(now.add(Duration(days: i))),
          DateFormat('d MMM').format(now.add(Duration(days: i))),
        ),
    ];
  }

  // Business hours 10 am–7 pm, 90-minute slots — was 8 am–8 pm in 1–2 hour
  // blocks that didn't match the actual service window.
  static const _am = ['10:00 – 11:30 am', '11:30 am – 1:00 pm'];
  static const _pm = ['1:00 – 2:30 pm', '2:30 – 4:00 pm', '4:00 – 5:30 pm', '5:30 – 7:00 pm'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final vm = ref.read(bookingDraftProvider.notifier);
    return _StepScaffold(
      title: 'Choose a slot',
      progress: 0.5,
      caption: 'Step 2 of 4 — schedule',
      dock: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('Selected'),
              Text('${draft.day} · ${draft.slot}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        FilledButton(
            onPressed: () => context.push('/book/address'), child: const Text('Next')),
      ]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (_, i) {
                final label = '${_days[i].$1} ${_days[i].$2}';
                final sel = draft.day == label;
                return Pressable(
                  onTap: () => vm.setSlot(label, draft.slot),
                  child: Container(
                    width: 66,
                    decoration: BoxDecoration(
                      color: sel ? context.scheme.primary : context.scheme.surface,
                      borderRadius: Radii.rMd,
                      border: Border.all(
                          color: sel ? context.scheme.primary : context.care.hairline),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_days[i].$1,
                            style: TextStyle(
                                fontSize: 11,
                                color: sel
                                    ? context.scheme.onPrimary.withValues(alpha: 0.8)
                                    : context.care.inkMuted)),
                        const SizedBox(height: 3),
                        Text(_days[i].$2.split(' ').first,
                            style: CareType.mono(
                                sel ? context.scheme.onPrimary : context.scheme.onSurface,
                                size: 15,
                                w: FontWeight.w600)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SectionHeader('Morning'),
          _slotGrid(context, ref, draft, _am),
          const SectionHeader('Afternoon and evening'),
          _slotGrid(context, ref, draft, _pm),
        ],
      ),
    );
  }

  Widget _slotGrid(BuildContext context, WidgetRef ref, BookingDraft draft, List<String> slots) {
    final vm = ref.read(bookingDraftProvider.notifier);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.5,
      children: [
        for (final s in slots)
          Pressable(
            onTap: () => vm.setSlot(draft.day, s),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: draft.slot == s ? context.scheme.primary : context.scheme.surface,
                borderRadius: Radii.rMd,
                border: Border.all(
                    color: draft.slot == s ? context.scheme.primary : context.care.hairline),
              ),
              child: Text(s,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: draft.slot == s
                          ? context.scheme.onPrimary
                          : context.scheme.onSurface)),
            ),
          ),
      ],
    );
  }
}

// ============================================================ 3 · ADDRESS
class AddressScreen extends ConsumerWidget {
  const AddressScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final vm = ref.read(bookingDraftProvider.notifier);
    // A newly map-picked address (see AddressPickerScreen) isn't part of
    // savedAddressesProvider's list, so it's appended here — the same
    // selection UI (radio dot compared against draft.addressId) handles it
    // unchanged.
    final addresses = [
      ...ref.watch(savedAddressesProvider),
      if (draft.pickedAddress != null) draft.pickedAddress!,
    ];
    return _StepScaffold(
      title: 'Where should we come?',
      progress: 0.75,
      caption: 'Step 3 of 4 — address',
      dock: SizedBox(
        width: double.infinity,
        child: FilledButton(
            onPressed: () => context.push('/book/payment'),
            child: const Text('Review and pay')),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 150,
            decoration: BoxDecoration(
                color: context.scheme.surfaceContainerHigh, borderRadius: Radii.rLg),
            alignment: Alignment.center,
            child: Icon(Icons.location_on, size: 40, color: context.scheme.primary),
          ),
          const SizedBox(height: 16),
          for (final ad in addresses) ...[
            CareCard(
              onTap: () => vm.setAddress(ad.id),
              borderColor: draft.addressId == ad.id ? context.scheme.primary : null,
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
                      const SizedBox(height: 3),
                      Text(ad.line, style: context.type.bodySmall),
                    ],
                  ),
                ),
                Icon(
                    draft.addressId == ad.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: draft.addressId == ad.id
                        ? context.scheme.primary
                        : context.care.hairline),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
                onPressed: () async {
                  final picked = await context.push<SavedAddress>('/book/address/pick');
                  if (picked != null) vm.setPickedAddress(picked);
                },
                child: const Text('+ Add a new address')),
          ),
          const SizedBox(height: 16),
          CareField('Directions for the technician (optional)',
              initial: draft.directions,
              maxLines: 2,
              onChanged: vm.setDirections),
        ],
      ),
    );
  }
}

// ============================================================ 4 · PAYMENT
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  bool _submitting = false;

  Future<void> _pay(BookingDraft draft) async {
    setState(() => _submitting = true);
    SavedAddress? selected;
    for (final a in [
      ...ref.read(savedAddressesProvider),
      if (draft.pickedAddress != null) draft.pickedAddress!,
    ]) {
      if (a.id == draft.addressId) {
        selected = a;
        break;
      }
    }
    // One real booking per selected service — each keeps its own real
    // price and gets routed/tracked independently on the Partner side.
    // Awaited (not fire-and-forget) because the confirmation screen needs
    // the real booking id(s) that come back — it used to always link to
    // the same hardcoded "CP-2481-NSK" no matter what was actually
    // created, which is exactly why "the actual booking" never showed up.
    final directions = draft.directions.trim();
    final created = <Booking>[];
    String? lastError;
    for (final service in draft.services) {
      final result = await ref.read(apiRepositoryProvider).createBooking(
            service: service,
            totalPaise: service.pricePaise,
            areaLabel: selected?.label,
            lat: selected?.lat,
            lng: selected?.lng,
            directions: directions.isEmpty ? null : directions,
          );
      if (result.booking != null) created.add(result.booking!);
      if (result.error != null) lastError = result.error;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    if (created.isEmpty) {
      // Honest failure — no fake "you're booked" when nothing was actually
      // created. Show the real reason (e.g. the backend has no technician
      // to route to yet) rather than always blaming the customer's
      // connection, which is wrong for anything but a genuine network
      // failure and actively misleading for a real server-side rejection.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(lastError ??
              "Couldn't confirm your booking — check your connection and try again.")));
      return;
    }
    context.go('/booking/${created.first.id}/confirmed', extra: created.length);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingDraftProvider);
    return _StepScaffold(
      title: 'Review and pay',
      progress: 1,
      caption: 'Step 4 of 4 — payment',
      dock: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('Payable now'),
              Text(Money.rupees(draft.totalPaise),
                  style: CareType.mono(context.scheme.onSurface,
                      size: 17, w: FontWeight.w600)),
            ],
          ),
        ),
        FilledButton(
          onPressed: draft.services.isEmpty || _submitting ? null : () => _pay(draft),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text('Pay ${Money.rupees(draft.totalPaise)}'),
        ),
      ]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in draft.services) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(s.title,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ),
                      Text(Money.rupees(s.pricePaise),
                          style: CareType.mono(context.scheme.onSurface, size: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Text('${draft.day} · ${draft.slot}', style: context.type.bodySmall),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    Text(Money.rupees(draft.totalPaise),
                        style: CareType.mono(context.scheme.onSurface,
                            size: 18, w: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader('Payment'),
          // There's no card/UPI/wallet payment gateway wired up yet (no
          // Razorpay or any other processor exists in this app or the
          // backend) — the previous "Pay with" selector offered five
          // choices (including a specific fake card number and a fake
          // Care+ wallet balance) that all did exactly nothing; whichever
          // one was picked was never even read by the booking call. The
          // real, only-actually-true payment model is this: the technician
          // collects payment via UPI once the job is done.
          CareCard(
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: context.scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('₹', style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pay after the visit',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    Text('UPI to the technician, once the job is done',
                        style: context.type.bodySmall),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

}

// ============================================================ CONFIRMED
// Previously always showed the same hardcoded "JOB CP-2481-NSK", a fixed
// mock technician's name/rating (with call/chat buttons that didn't do
// anything), and a fabricated "start code 4402" — regardless of what was
// actually booked. Now built from the real booking the backend just
// created; no technician identity is shown at all until one is genuinely
// assigned, since the Customer app has no real way to know who that is yet.
class ConfirmedScreen extends ConsumerWidget {
  const ConfirmedScreen({super.key, required this.bookingId, this.totalBooked = 1});
  final String bookingId;
  final int totalBooked;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(bookingsRefreshProvider);
    final booking = ref.watch(repositoryProvider).bookingById(bookingId);
    final summary = booking == null
        ? 'A technician is being assigned now.'
        : '${booking.title}${totalBooked > 1 ? ' + ${totalBooked - 1} more' : ''} at '
            '${booking.addressLabel}.\nA technician is being assigned now.';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 34, 20, 20),
                children: [
                  Center(
                    child: Column(
                      children: [
                        CareDial(
                          value: 1,
                          size: 94,
                          color: context.care.success,
                          child: Icon(Icons.check, size: 40, color: context.care.success),
                        ),
                        const SizedBox(height: 22),
                        Text("You're booked", style: context.type.headlineMedium),
                        const SizedBox(height: 10),
                        Text(summary,
                            textAlign: TextAlign.center, style: context.type.bodyMedium),
                        const SizedBox(height: 14),
                        Mono('JOB $bookingId', color: context.scheme.secondary, size: 13),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Dock(
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => context.go('/'), child: const Text('Home')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                      onPressed: () => context.push('/booking/$bookingId/track'),
                      child: const Text('Track visit')),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

