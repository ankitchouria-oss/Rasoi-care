import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
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
  ServiceItem? _selected;
  final Set<String> _expandedIncluded = {};

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final detail = repo.applianceDetail(widget.appliance);

    if (detail.comingSoon) {
      return _ComingSoonScreen(appliance: widget.appliance, detail: detail);
    }

    final services = repo.servicesFor(widget.appliance);
    _selected ??= services.first;
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
                      Eyebrow('1 service'),
                      Text(Money.rupees(_selected!.pricePaise),
                          style: CareType.mono(context.scheme.onSurface,
                              size: 16, w: FontWeight.w600)),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    ref.read(bookingDraftProvider.notifier).start(_selected!);
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
                    ChoiceTag(_selected == s ? 'Added' : 'Add',
                        selected: _selected == s,
                        onTap: () => setState(() => _selected = s)),
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

class _ApplianceHero extends StatefulWidget {
  const _ApplianceHero({required this.appliance});
  final Appliance appliance;
  @override
  State<_ApplianceHero> createState() => _ApplianceHeroState();
}

class _ApplianceHeroState extends State<_ApplianceHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.scheme.primary;
    return Container(
      height: 150,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: Radii.rLg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.scheme.primaryContainer, context.scheme.surfaceContainerHigh],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ..._accents(primary),
          CareDial(
            value: 1,
            size: 108,
            stroke: 6,
            showTicks: false,
            color: primary,
            trackColor: primary.withValues(alpha: 0.16),
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.35),
                  radius: 0.95,
                  colors: [Color.lerp(primary, Colors.white, 0.4)!, primary],
                ),
                boxShadow: [
                  BoxShadow(
                      color: primary.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6)),
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Text(widget.appliance.glyph,
                  style: const TextStyle(
                      fontSize: 30, color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _accents(Color primary) {
    switch (widget.appliance) {
      case Appliance.chimney:
        return [
          _Puff(controller: _c, delay: 0.00, dx: -16, color: primary),
          _Puff(controller: _c, delay: 0.33, dx: 0, color: primary),
          _Puff(controller: _c, delay: 0.66, dx: 16, color: primary),
        ];
      case Appliance.hob:
      case Appliance.cooktop:
      case Appliance.otg:
        return [_Flicker(controller: _c)];
      case Appliance.dishwasher:
        return [
          _Puff(controller: _c, delay: 0.00, dx: -14, color: Colors.lightBlue),
          _Puff(controller: _c, delay: 0.50, dx: 14, color: Colors.lightBlue),
        ];
      case Appliance.refrigerator:
        return [
          _Sparkle(controller: _c, delay: 0.00, dx: -26, dy: -22),
          _Sparkle(controller: _c, delay: 0.40, dx: 26, dy: -8),
          _Sparkle(controller: _c, delay: 0.70, dx: -8, dy: 24),
        ];
      case Appliance.microwave:
        return [_PulseRing(controller: _c)];
      case Appliance.purifier:
        return [_Drip(controller: _c)];
    }
  }
}

/// A single rising, fading puff — used for chimney smoke and dishwasher
/// steam/bubbles. [delay] staggers puffs sharing one looping controller by
/// offsetting where in the 0..1 cycle each one reads from.
class _Puff extends StatelessWidget {
  const _Puff({
    required this.controller,
    required this.delay,
    required this.dx,
    required this.color,
  });
  final Animation<double> controller;
  final double delay;
  final double dx;
  final Color color;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = (controller.value + delay) % 1.0;
          final fade = math.sin(t * math.pi).clamp(0.0, 1.0);
          final size = 8 + t * 6;
          return Positioned(
            top: 16,
            child: Transform.translate(
              offset: Offset(dx, -t * 44),
              child: Opacity(
                opacity: fade * 0.55,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
              ),
            ),
          );
        },
      );
}

/// Flickering flame — hob, cooktop, OTG.
class _Flicker extends StatelessWidget {
  const _Flicker({required this.controller});
  final Animation<double> controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final wobble = math.sin(controller.value * 2 * math.pi);
          final scale = 1.0 + wobble * 0.14;
          final opacity = 0.75 + wobble * 0.2;
          return Positioned(
            bottom: 20,
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: const Icon(Icons.local_fire_department,
                    color: Colors.deepOrange, size: 26),
              ),
            ),
          );
        },
      );
}

/// Twinkling frost accent — refrigerator.
class _Sparkle extends StatelessWidget {
  const _Sparkle({
    required this.controller,
    required this.delay,
    required this.dx,
    required this.dy,
  });
  final Animation<double> controller;
  final double delay, dx, dy;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = (controller.value + delay) % 1.0;
          final fade = math.sin(t * math.pi).clamp(0.0, 1.0);
          return Transform.translate(
            offset: Offset(dx, dy),
            child: Opacity(
              opacity: fade,
              child: const Text('❄', style: TextStyle(fontSize: 13, color: Colors.lightBlue)),
            ),
          );
        },
      );
}

/// Expanding heat pulse — microwave.
class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.controller});
  final Animation<double> controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          final scale = 0.5 + t * 0.9;
          final opacity = (1 - t) * 0.5;
          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: context.scheme.primary, width: 2),
                ),
              ),
            ),
          );
        },
      );
}

/// Falling droplet + landing ripple — water purifier.
class _Drip extends StatelessWidget {
  const _Drip({required this.controller});
  final Animation<double> controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          final dropOpacity = t < 0.6 ? 1 - (t / 0.6) : 0.0;
          final dropDy = -26 + t * 46;
          final rippleT = t > 0.5 ? (t - 0.5) * 2 : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: Offset(0, dropDy),
                child: Opacity(
                  opacity: dropOpacity.clamp(0.0, 1.0),
                  child: const Icon(Icons.water_drop, color: Colors.lightBlue, size: 16),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, 24),
                child: Transform.scale(
                  scale: 0.3 + rippleT * 1.1,
                  child: Opacity(
                    opacity: ((1 - rippleT) * 0.5).clamp(0.0, 1.0),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.lightBlue, width: 1.6),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
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
