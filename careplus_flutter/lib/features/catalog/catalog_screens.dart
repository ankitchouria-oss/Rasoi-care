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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Eyebrow('from'),
                          const SizedBox(height: 2),
                          Text(Money.rupees(ref.read(repositoryProvider).servicesFor(a)[1].pricePaise),
                              style: CareType.mono(context.scheme.onSurface,
                                  size: 14, w: FontWeight.w600)),
                        ],
                      ),
                    ]),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _blurb(Appliance a) => switch (a) {
        Appliance.chimney => 'Deep clean, suction loss, oil leak, auto-clean',
        Appliance.hob => 'Igniter, low flame, burner and knob replacement',
        Appliance.cooktop => 'Induction and glass-top faults, coil and sensor',
        Appliance.dishwasher => 'Not draining, not cleaning, error codes, install',
        Appliance.microwave => 'Magnetron, turntable, door switch, panel',
        Appliance.refrigerator => 'Not cooling, gas refill, compressor, noise',
        Appliance.otg => 'Heating element, thermostat, timer',
        Appliance.purifier => 'Filter change, RO membrane, leakage, AMC',
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

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(repositoryProvider).servicesFor(widget.appliance);
    _selected ??= services.first;

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
                  Container(
                    height: 150,
                    decoration: BoxDecoration(
                        color: context.scheme.surfaceContainerHigh,
                        borderRadius: Radii.rLg),
                    alignment: Alignment.center,
                    child: Text(widget.appliance.glyph,
                        style: TextStyle(
                            fontSize: 64, color: context.scheme.primary)),
                  ),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, children: const [
                    StatusChip('★ 4.89 (3,102)', tone: ChipTone.success, height: 28),
                    StatusChip('90 min avg', height: 28),
                    StatusChip('All brands', height: 28),
                  ]),
                  const SizedBox(height: 16),
                  Text('${_short()} care', style: context.type.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                      'Suction loss, oil dripping, loud motor, auto-clean failure — diagnosed and fixed by technicians trained on all major brands.',
                      style: context.type.bodyMedium),
                  const SizedBox(height: 22),
                  _Segmented(
                    tabs: const ['Services', "What's included", 'Reviews'],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                  const SizedBox(height: 16),
                  if (_tab == 0) ..._servicesTab(services),
                  if (_tab == 1) ..._includedTab(),
                  if (_tab == 2) ..._reviewsTab(),
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

  String _short() => widget.appliance.label.split(' ').last;

  List<Widget> _servicesTab(List<ServiceItem> services) => [
        for (final s in services) ...[
          CareCard(
            child: Row(
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
          ),
          const SizedBox(height: 10),
        ],
      ];

  List<Widget> _includedTab() => [
        CareCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('In every deep clean',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final t in const [
                'Baffle or mesh filters soaked and scrubbed',
                'Blower wheel and motor housing degreased',
                'Oil collector emptied and washed',
                'Duct checked for blockage and leak',
                'Suction reading before and after, logged in app',
                'Floor sheeting and full cleanup',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(children: [
                    Icon(Icons.check, size: 16, color: context.care.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t, style: context.type.bodySmall)),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        CareCard(
          color: context.scheme.errorContainer,
          borderColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Not included',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: context.scheme.error)),
              const SizedBox(height: 8),
              Text(
                  'Replacement filters, motor rewinding, control boards and duct extensions. These are quoted in the app before work starts.',
                  style: context.type.bodySmall),
            ],
          ),
        ),
      ];

  List<Widget> _reviewsTab() => [
        CareCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(children: [
                Text('4.89',
                    style: CareType.mono(context.scheme.onSurface,
                        size: 32, w: FontWeight.w600)),
                Text('★★★★★',
                    style: TextStyle(color: context.scheme.secondary, fontSize: 12)),
                const SizedBox(height: 5),
                Text('3,102 ratings', style: context.type.bodySmall),
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
        for (final r in const [
          ('PJ', 'Priya Joshi', 'Elica 90cm · 20 Jul',
              'Suction went from 480 to 1,180 m³/hr on the app reading. Worth every rupee.'),
          ('VN', 'Vikram Nair', 'Faber auto-clean · 09 Jul',
              'Turned out to be a jammed heating coil, not a motor issue. He explained it instead of upselling.'),
        ]) ...[
          CareCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Blob(r.$1, size: 34),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.$2,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      Text(r.$3, style: context.type.bodySmall),
                    ],
                  ),
                ]),
                const SizedBox(height: 11),
                Text(r.$4, style: context.type.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ];
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
