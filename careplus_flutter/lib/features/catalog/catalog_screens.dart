import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/widgets/appliance_illustration.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

// ============================================================ ALL SERVICES
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All services'),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.tune))],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            CareCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: 'Search appliance, brand or symptom',
                  hintStyle: context.type.bodyMedium,
                  prefixIcon: Icon(Icons.search, color: context.care.inkFaint, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Eyebrow('8 appliance categories'),
            const SizedBox(height: 12),
            Stagger(
              children: [
                for (final a in Appliance.values)
                  CareCard(
                    onTap: () => context.push('/services/${a.name}'),
                    child: Row(children: [
                      Blob(a.glyph, glyph: true),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.label,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(_blurb(a), style: context.type.bodySmall),
                          ],
                        ),
                      ),
                      _fromPrice(context, ref, a),
                    ]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fromPrice(BuildContext context, WidgetRef ref, Appliance a) {
    final services = ref.read(repositoryProvider).servicesFor(a);
    if (services.isEmpty) {
      return const StatusChip('Coming soon', height: 26);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Eyebrow('from'),
        const SizedBox(height: 2),
        Text(Money.rupees(services[1].pricePaise),
            style: CareType.mono(context.scheme.onSurface, size: 14, w: FontWeight.w600)),
      ],
    );
  }

  String _blurb(Appliance a) => switch (a) {
        Appliance.chimney => 'Deep clean, suction loss, oil leak, auto-clean',
        Appliance.hob => 'Igniter, low flame, burner and knob replacement',
        Appliance.cooktop => 'Induction and glass-top faults, coil and sensor',
        Appliance.dishwasher => 'Not draining, not cleaning, error codes, install',
        Appliance.microwave => 'Magnetron, turntable, door switch, panel',
        Appliance.refrigerator => 'Booking opens shortly — tap to get notified',
        Appliance.otg => 'Heating element, thermostat, timer',
        Appliance.purifier => 'Booking opens shortly — tap to get notified',
      };
}

// ============================================================ SERVICE DETAIL
class ServiceDetailScreen extends ConsumerStatefulWidget {
  const ServiceDetailScreen({super.key, required this.appliance});
  final Appliance appliance;
  @override
  ConsumerState<ServiceDetailScreen> createState() => _ServiceDetailState();
}

class _ServiceDetailState extends ConsumerState<ServiceDetailScreen> {
  int _tab = 0;
  final Set<String> _selectedIds = {};
  final Set<String> _expandedIncluded = {};
  bool _seeded = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final detail = repo.applianceDetail(widget.appliance);

    if (detail.comingSoon) {
      return _ComingSoonScreen(appliance: widget.appliance, detail: detail);
    }

    final services = repo.servicesFor(widget.appliance);
    // Pre-select the most-booked service once, on first load only — not
    // "whenever nothing's selected", or removing the last pick (allowed
    // below) would just get silently re-added on the next rebuild.
    if (!_seeded) {
      _selectedIds.add(services.first.id);
      _seeded = true;
    }
    final selected = [for (final s in services) if (_selectedIds.contains(s.id)) s];
    final selectedTotalPaise = selected.fold<int>(0, (sum, s) => sum + s.pricePaise);
    final avgDurationMin =
        services.firstWhere((s) => s.mostBooked, orElse: () => services.first).durationMin;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: Text(widget.appliance.label),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.favorite_border))],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                children: [
                  _ApplianceHero(appliance: widget.appliance),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, children: [
                    StatusChip(
                        '★ ${detail.rating} (${_thousands(detail.ratingCount)})',
                        tone: ChipTone.success,
                        height: 28),
                    StatusChip('$avgDurationMin min avg', height: 28),
                    const StatusChip('All brands', height: 28),
                  ]),
                  const SizedBox(height: 16),
                  Text(detail.heading, style: context.type.headlineMedium),
                  const SizedBox(height: 8),
                  Text(detail.blurb, style: context.type.bodyMedium),
                  const SizedBox(height: 22),
                  _Segmented(
                    tabs: const ['Services', 'Reviews'],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == 0) ..._servicesTab(services),
                  if (_tab == 1) ..._reviewsTab(detail),
                ],
              ),
            ),
            Dock(
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(selected.length == 1
                          ? '1 service'
                          : '${selected.length} services'),
                      Text(Money.rupees(selectedTotalPaise),
                          style: CareType.mono(context.scheme.onSurface,
                              size: 16, w: FontWeight.w600)),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () {
                          ref.read(bookingDraftProvider.notifier).start(selected);
                          context.push('/book/issue');
                        },
                  child: const Text('Continue'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  String _thousands(int n) => n
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

  List<Widget> _servicesTab(List<ServiceItem> services) => [
        for (final s in services) ...[
          CareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (s.mostBooked) ...[
                            const StatusChip('Most booked',
                                tone: ChipTone.warning, height: 22),
                            const SizedBox(height: 8),
                          ],
                          Text(s.title,
                              style: const TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          Text(s.blurb, style: context.type.bodySmall),
                          const SizedBox(height: 9),
                          Row(children: [
                            Text(Money.rupees(s.pricePaise),
                                style: CareType.mono(context.scheme.onSurface,
                                    size: 15, w: FontWeight.w600)),
                            if (s.strikePaise != null) ...[
                              const SizedBox(width: 8),
                              Text(Money.rupees(s.strikePaise!),
                                  style: CareType.mono(context.care.inkFaint, size: 12)
                                      .copyWith(decoration: TextDecoration.lineThrough)),
                            ],
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ChoiceTag(_selectedIds.contains(s.id) ? 'Added' : 'Add',
                        selected: _selectedIds.contains(s.id),
                        onTap: () => setState(() {
                              // A real multi-add, not a single radio pick —
                              // the "Add"/"Added" wording always implied you
                              // could pick more than one service in a visit.
                              // Deselecting the last one is allowed too —
                              // Continue just disables until something's
                              // picked again (see the FilledButton below).
                              if (_selectedIds.contains(s.id)) {
                                _selectedIds.remove(s.id);
                              } else {
                                _selectedIds.add(s.id);
                              }
                            })),
                  ],
                ),
                if (s.included.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _IncludedDropdown(
                    service: s,
                    expanded: _expandedIncluded.contains(s.id),
                    onToggle: () => setState(() => _expandedIncluded.contains(s.id)
                        ? _expandedIncluded.remove(s.id)
                        : _expandedIncluded.add(s.id)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ];

  List<Widget> _reviewsTab(ApplianceDetail detail) => [
        CareCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(children: [
                Text('${detail.rating}',
                    style: CareType.mono(context.scheme.onSurface,
                        size: 32, w: FontWeight.w600)),
                Text('★★★★★',
                    style: TextStyle(color: context.scheme.secondary, fontSize: 12)),
                const SizedBox(height: 5),
                Text('${_thousands(detail.ratingCount)} ratings', style: context.type.bodySmall),
              ]),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    for (final p in const [0.88, 0.09, 0.02, 0.01, 0.01])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ProgressBar(p),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (final r in detail.reviews) ...[
          CareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Blob(r.initials, size: 34),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      Text(r.meta, style: context.type.bodySmall),
                    ],
                  ),
                ]),
                const SizedBox(height: 11),
                Text(r.quote, style: context.type.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ];
}

/// A collapsible "What's included" card shown above the services list,
/// instead of its own tab — tap the header to expand/collapse.
class _IncludedDropdown extends StatelessWidget {
  const _IncludedDropdown({
    required this.service,
    required this.expanded,
    required this.onToggle,
  });
  final ServiceItem service;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: context.scheme.surfaceContainerHigh,
          borderRadius: Radii.rMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Pressable(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text("What's included",
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: Motion.press,
                      child: Icon(Icons.expand_more, size: 20, color: context.care.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    for (final t in service.included)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Icon(Icons.check, size: 15, color: context.care.success),
                          const SizedBox(width: 8),
                          Expanded(child: Text(t, style: context.type.bodySmall)),
                        ]),
                      ),
                    if (service.notIncluded.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Not included',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.scheme.error)),
                      const SizedBox(height: 5),
                      Text(service.notIncluded, style: context.type.bodySmall),
                    ],
                  ],
                ),
              ),
              crossFadeState:
                  expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: Motion.screen,
              sizeCurve: Motion.ease,
            ),
          ],
        ),
      );
}

/// The appliance illustration shown at the top of its service-detail
/// screen — a soft gradient card with the pictogram centered on a glossy
/// badge. Deliberately simple/static (no floating overlays that could
/// clip or overflow at odd screen sizes): a fixed-size illustration
/// centered in a fixed-height card, nothing positioned outside its bounds.
class _ApplianceHero extends StatelessWidget {
  const _ApplianceHero({required this.appliance});
  final Appliance appliance;

  @override
  Widget build(BuildContext context) {
    final primary = context.scheme.primary;
    return Container(
      height: 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: Radii.rLg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.scheme.primaryContainer, context.scheme.surfaceContainerHigh],
        ),
      ),
      child: Container(
        width: 108,
        height: 108,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.35),
            radius: 0.95,
            colors: [Color.lerp(primary, Colors.white, 0.45)!, primary],
          ),
          boxShadow: [
            BoxShadow(
                color: primary.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8)),
          ],
        ),
        child: ApplianceIllustration(appliance: appliance, size: 62, color: Colors.white),
      ),
    );
  }
}

// ============================================================ COMING SOON
class _ComingSoonScreen extends StatelessWidget {
  const _ComingSoonScreen({required this.appliance, required this.detail});
  final Appliance appliance;
  final ApplianceDetail detail;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: context.pop), title: Text(appliance.label)),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                _ApplianceHero(appliance: appliance),
                const SizedBox(height: 16),
                const StatusChip('Coming soon', height: 28),
                const SizedBox(height: 16),
                Text(detail.heading, style: context.type.headlineMedium),
                const SizedBox(height: 8),
                Text(detail.blurb, textAlign: TextAlign.center, style: context.type.bodyMedium),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("We'll notify you when this opens up"))),
                    child: const Text('Notify me'),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.tabs, required this.index, required this.onChanged});
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
            color: context.scheme.surfaceContainerHigh, borderRadius: Radii.rSm),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
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
                    child: Text(tabs[i],
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
