import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';

class TechJobsScreen extends ConsumerStatefulWidget {
  const TechJobsScreen({super.key});
  @override
  ConsumerState<TechJobsScreen> createState() => _TechJobsScreenState();
}

class _TechJobsScreenState extends ConsumerState<TechJobsScreen> {
  int _acceptSecs = 42;
  bool _requestOpen = true;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_acceptSecs == 0) return;
      setState(() => _acceptSecs--);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final stats = repo.techStats();
    final request = _requestOpen ? repo.incomingRequest() : null;
    final route = repo.routeToday();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Eyebrow('Technician'),
                        const SizedBox(height: 3),
                        Text('Sandeep Pawar', style: context.type.titleMedium),
                      ],
                    ),
                  ),
                  StatusChip(stats.onDuty ? '● On duty' : 'Off duty',
                      tone: stats.onDuty ? ChipTone.success : ChipTone.neutral),
                  const SizedBox(width: 9),
                  _RoundIcon(
                      icon: Icons.arrow_back,
                      onTap: () =>
                          context.canPop() ? context.pop() : context.go('/account')),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  CareCard(
                    color: CareColors.pine,
                    borderColor: Colors.transparent,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Eyebrow("Today's earnings", color: CareColors.brass),
                              const SizedBox(height: 5),
                              Text(Money.rupees(stats.earningsTodayPaise),
                                  style: CareType.mono(CareColors.porcelain,
                                      size: 26, w: FontWeight.w600)),
                              const SizedBox(height: 5),
                              Text(
                                  '${stats.jobsDone} of ${stats.jobsTotal} jobs done · ${Money.rupees(stats.tipsPaise)} tips',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: CareColors.porcelain.withValues(alpha: 0.6))),
                            ],
                          ),
                        ),
                        CareDial(
                            value: stats.progress,
                            size: 60,
                            stroke: 7,
                            showTicks: false,
                            color: CareColors.brass,
                            trackColor: const Color(0x33F6F4EF)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _StatBox(label: 'Rating', value: '${stats.rating}')),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _StatBox(
                            label: 'First-time fix', value: '${stats.firstTimeFixPct}%')),
                  ]),
                  if (request != null) ...[
                    SectionHeader('New request',
                        trailing: Text(
                            _acceptSecs > 0
                                ? '0:${_acceptSecs.toString().padLeft(2, '0')} to accept'
                                : 'Offer expired',
                            style: CareType.mono(
                                context.scheme.error, size: 11.5, w: FontWeight.w600))),
                    CareCard(
                      borderColor: context.scheme.secondary,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              StatusChip(request.serviceTitle,
                                  tone: ChipTone.warning, height: 24),
                              Mono(request.jobId, color: context.care.inkMuted),
                            ],
                          ),
                          const SizedBox(height: 11),
                          Text('Gangapur Road · ${request.distanceKm} km',
                              style: const TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                              '${request.timeWindow} · payout ${Money.rupees(request.payoutPaise)} · ${request.note}',
                              style: context.type.bodySmall),
                          const SizedBox(height: 13),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() => _requestOpen = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Passed to next technician')));
                                },
                                child: const Text('Pass'),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  setState(() => _requestOpen = false);
                                  context.push('/tech/job/${request.jobId}');
                                },
                                child: const Text('Accept'),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ],
                  SectionHeader('Route today',
                      trailing: GestureDetector(
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Opens Google Maps'))),
                        child: Text('Map',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.scheme.primary)),
                      )),
                  Stagger(children: [
                    for (final stop in route)
                      CareCard(
                        onTap: () => context.push('/tech/job/${stop.jobId}'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                StatusChip(
                                    stop.status == StopStatus.inProgress
                                        ? 'In progress'
                                        : 'Next',
                                    tone: stop.status == StopStatus.inProgress
                                        ? ChipTone.success
                                        : ChipTone.neutral,
                                    height: 24),
                                Mono(stop.time, color: context.care.inkMuted),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text('${stop.title} · ${stop.customerName}',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(stop.meta, style: context.type.bodySmall),
                          ],
                        ),
                      ),
                  ]),
                  const SizedBox(height: 14),
                  CareCard(
                    color: context.scheme.errorContainer,
                    borderColor: Colors.transparent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Van stock running low',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.scheme.error)),
                        const SizedBox(height: 6),
                        Text(
                            'Elica baffle filters: 2 left. Request a top-up at the Ashok Nagar hub.',
                            style: context.type.bodySmall),
                        const SizedBox(height: 11),
                        OutlinedButton(
                          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Stock request sent'))),
                          child: const Text('Request stock'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => CareCard(
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
