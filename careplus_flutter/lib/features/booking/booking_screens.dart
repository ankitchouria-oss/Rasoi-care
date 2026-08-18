import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
          Row(children: [
            for (final label in const ['Filter', 'Model tag', 'Add', 'Gallery']) ...[
              Expanded(child: _PhotoBox(label: label)),
              if (label != 'Gallery') const SizedBox(width: 10),
            ],
          ]),
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

class _PhotoBox extends StatelessWidget {
  const _PhotoBox({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.scheme.surfaceContainerHigh,
            borderRadius: Radii.rMd,
            border: Border.all(
                color: context.care.hairline,
                style: BorderStyle.solid),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.camera_alt_outlined, size: 18, color: context.care.inkFaint),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(fontSize: 11, color: context.care.inkFaint)),
            ],
          ),
        ),
      );
}

// ============================================================ 2 · SLOT
class SlotScreen extends ConsumerWidget {
  const SlotScreen({super.key});
  static const _days = [
    ('Today', '24 Jul'), ('Sat', '25 Jul'), ('Sun', '26 Jul'),
    ('Mon', '27 Jul'), ('Tue', '28 Jul'), ('Wed', '29 Jul'),
  ];
  static const _am = ['8:00 – 9:00 am', '9:00 – 10:00 am', '10:00 – 11:00 am', '11:00 – 12:00 pm'];
  static const _pm = ['12:00 – 2:00 pm', '2:00 – 4:00 pm', '4:00 – 6:00 pm', '6:00 – 8:00 pm'];

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
          const SizedBox(height: 16),
          CareCard(
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ask for Sandeep P.',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text('He did your last chimney visit · ★ 4.94',
                        style: context.type.bodySmall),
                  ],
                ),
              ),
              const _MiniSwitch(initial: true),
            ]),
          ),
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
      childAspectRatio: 3.1,
      children: [
        for (final s in slots)
          Pressable(
            onTap: () => vm.setSlot(draft.day, s),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: draft.slot == s ? context.scheme.primary : context.scheme.surface,
                borderRadius: Radii.rMd,
                border: Border.all(
                    color: draft.slot == s ? context.scheme.primary : context.care.hairline),
              ),
              child: Text(s,
                  style: TextStyle(
                      fontSize: 12.5,
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

class _MiniSwitch extends StatefulWidget {
  const _MiniSwitch({this.initial = false});
  final bool initial;
  @override
  State<_MiniSwitch> createState() => _MiniSwitchState();
}

class _MiniSwitchState extends State<_MiniSwitch> {
  late bool _v = widget.initial;
  @override
  Widget build(BuildContext context) =>
      Switch(value: _v, onChanged: (x) => setState(() => _v = x));
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
          const CareField('Directions for the technician',
              initial: 'Gate code 4402, lift on the left'),
        ],
      ),
    );
  }
}

// ============================================================ 4 · PAYMENT
class PaymentScreen extends ConsumerWidget {
  const PaymentScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final draft = ref.watch(bookingDraftProvider);
    final vm = ref.read(bookingDraftProvider.notifier);
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
          onPressed: () {
            // Razorpay checkout opens here in production, then the app listens
            // to the booking doc for payment.status before advancing.
            final service = draft.service;
            if (service != null) {
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
              // Fire-and-forget — this booking flow always completes
              // locally regardless of whether the real backend is
              // reachable, same "never block a flow" philosophy as the
              // Firestore profile write in firestore_user_profile_service.dart.
              unawaited(ref.read(apiRepositoryProvider).createBooking(
                    service: service,
                    totalPaise: draft.totalPaise,
                    areaLabel: selected?.label,
                    lat: selected?.lat,
                    lng: selected?.lng,
                  ));
            }
            context.go('/booking/CP-2481-NSK/confirmed');
          },
          child: Text('Pay ${Money.rupees(draft.totalPaise)}'),
        ),
      ]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(draft.service?.title ?? 'Service',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    Text(Money.rupees(draft.itemPaise),
                        style: CareType.mono(context.scheme.onSurface, size: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${draft.day} · ${draft.slot}', style: context.type.bodySmall),
                const Divider(height: 24),
                _line(context, 'Item total', Money.rupees(draft.itemPaise)),
                _line(context, 'Visit and safety kit', Money.rupees(draft.visitPaise)),
                if (draft.couponApplied)
                  _line(context, 'CARE30 discount', '−${Money.rupees(draft.discountPaise)}',
                      color: context.care.success),
                if (draft.useCoins)
                  _line(context, '200 Care Coins', '−${Money.rupees(draft.coinsPaise)}',
                      color: context.care.success),
                _line(context, 'GST 18%', Money.rupees(draft.taxPaise)),
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
          const SizedBox(height: 12),
          CareCard(
            onTap: vm.toggleCoupon,
            color: draft.couponApplied ? context.scheme.primaryContainer : null,
            borderColor: draft.couponApplied ? Colors.transparent : null,
            child: Row(children: [
              const Text('🎟', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    draft.couponApplied ? 'CARE30 applied' : 'Apply a coupon',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: draft.couponApplied
                            ? context.scheme.primary
                            : context.scheme.onSurface)),
              ),
              Text(draft.couponApplied ? 'Remove' : 'Add',
                  style: TextStyle(fontSize: 12, color: context.scheme.primary)),
            ]),
          ),
          const SizedBox(height: 10),
          CareCard(
            child: Row(children: [
              const Text('◍', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Use 200 Care Coins',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    Text('₹200 off · 440 will remain', style: context.type.bodySmall),
                  ],
                ),
              ),
              Switch(value: draft.useCoins, onChanged: (_) => vm.toggleCoins()),
            ]),
          ),
          const SectionHeader('Pay with'),
          for (final m in repo.paymentMethods()) ...[
            CareCard(
              onTap: () => vm.setPayment(m.id),
              borderColor: draft.paymentId == m.id ? context.scheme.primary : null,
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: context.scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(m.glyph, style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      Text(m.detail, style: context.type.bodySmall),
                    ],
                  ),
                ),
                Icon(
                    draft.paymentId == m.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: draft.paymentId == m.id
                        ? context.scheme.primary
                        : context.care.hairline),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          CareCard(
            child: Row(children: [
              const Text('🛡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                    'Payments run through Razorpay. Card details never touch Care+ servers.',
                    style: context.type.bodySmall),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: context.type.bodySmall!
                    .copyWith(color: color ?? context.care.inkMuted)),
            Text(value,
                style: CareType.mono(color ?? context.scheme.onSurface, size: 11)),
          ],
        ),
      );
}

// ============================================================ CONFIRMED
class ConfirmedScreen extends ConsumerWidget {
  const ConfirmedScreen({super.key, required this.bookingId});
  final String bookingId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tech = ref.watch(repositoryProvider).preferredTechnician;
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
                        Text('Sat 25 Jul, 10:00–11:00 am at Home.\nA technician is being assigned now.',
                            textAlign: TextAlign.center, style: context.type.bodyMedium),
                        const SizedBox(height: 14),
                        Mono('JOB $bookingId', color: context.scheme.secondary, size: 13),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  CareCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow('Your technician'),
                        const SizedBox(height: 12),
                        Row(children: [
                          Blob(tech.initials,
                              bg: context.scheme.primary, fg: context.scheme.onPrimary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tech.name,
                                    style: const TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w700)),
                                Text('★ ${tech.rating} · ${tech.jobsDone} jobs · ${tech.years} yrs',
                                    style: context.type.bodySmall),
                              ],
                            ),
                          ),
                          _RoundIcon(icon: Icons.call, onTap: () {}),
                          const SizedBox(width: 8),
                          _RoundIcon(icon: Icons.chat_bubble_outline, onTap: () {}),
                        ]),
                        const Divider(height: 24),
                        Text.rich(TextSpan(children: [
                          TextSpan(text: 'Share the start code ', style: context.type.bodySmall),
                          TextSpan(
                              text: '4402',
                              style: CareType.mono(context.scheme.onSurface,
                                  size: 12, w: FontWeight.w600)),
                          TextSpan(text: ' only when he begins work.', style: context.type.bodySmall),
                        ])),
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

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
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
          child: Icon(icon, size: 18),
        ),
      );
}
