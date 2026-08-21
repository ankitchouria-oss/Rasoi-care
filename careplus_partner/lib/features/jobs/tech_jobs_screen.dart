import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/api/api_repository.dart';
import '../../data/models.dart';
import '../../l10n/l10n_extensions.dart';
import '../../state/providers.dart';
import '../../state/auth_providers.dart'
    show fetchTechnicianMe, technicianMeProvider;
import '../../state/technician_location_reporter.dart';

class TechJobsScreen extends ConsumerStatefulWidget {
  const TechJobsScreen({super.key});
  @override
  ConsumerState<TechJobsScreen> createState() => _TechJobsScreenState();
}

class _TechJobsScreenState extends ConsumerState<TechJobsScreen> {
  int _acceptSecs = 42;
  bool _requestOpen = true;
  bool _accepting = false;
  bool _togglingDuty = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_acceptSecs == 0) return;
      setState(() => _acceptSecs--);
    });
    // Kick off a real fetch once this screen is up — the repository starts
    // with an empty/mock-shaped cache until this completes. Fire-and-forget
    // from the UI's point of view; _bump forces a rebuild when it lands.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialRefresh());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _initialRefresh() async {
    final repo = ref.read(repositoryProvider);
    if (repo is ApiRepository) {
      await repo.refreshAll();
      unawaited(_refreshMyPosition(repo));
      if (mounted) ref.read(jobsFeedTickProvider.notifier).bump();
    }
    final me = await fetchTechnicianMe();
    if (mounted && me != null)
      ref.read(technicianMeProvider.notifier).state = me;
  }

  /// Best-effort real distance for an incoming request's card — see
  /// ApiRepository.setMyPosition/incomingRequest. Never blocks the rest of
  /// the screen: a denied permission or a timeout just leaves distance
  /// unset rather than ever showing a made-up figure.
  Future<void> _refreshMyPosition(ApiRepository repo) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.reduced),
      ).timeout(const Duration(seconds: 8));
      repo.setMyPosition(pos.latitude, pos.longitude);
      if (mounted) ref.read(jobsFeedTickProvider.notifier).bump();
    } catch (_) {
      // Best-effort — the request card just shows area without a distance.
    }
  }

  bool _passing = false;

  Future<void> _passRequest(String jobId) async {
    setState(() => _passing = true);
    final repo = ref.read(repositoryProvider);
    bool? reassigned;
    if (repo is ApiRepository) reassigned = await repo.declineJob(jobId);
    if (!mounted) return;
    setState(() {
      _passing = false;
      if (reassigned != null) _requestOpen = false;
    });
    ref.read(jobsFeedTickProvider.notifier).bump();
    final t = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (reassigned) {
      true => t.jobsPassedToast,
      false => t.jobsPassedCancelledToast,
      null => t.jobsPassError,
    })));
  }

  Future<void> _acceptRequest(String jobId) async {
    setState(() => _accepting = true);
    final repo = ref.read(repositoryProvider);
    if (repo is ApiRepository) {
      final ok = await repo.advanceJob(jobId); // Requested -> Accepted
      if (ok) ref.read(jobsFeedTickProvider.notifier).bump();
    }
    if (!mounted) return;
    setState(() {
      _accepting = false;
      _requestOpen = false;
    });
    context.push('/tech/job/$jobId');
  }

  Future<void> _toggleDuty(bool current) async {
    setState(() => _togglingDuty = true);
    final repo = ref.read(repositoryProvider);
    if (repo is ApiRepository) {
      final ok = await repo.setOnDuty(!current);
      if (ok) {
        ref.read(jobsFeedTickProvider.notifier).bump();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.jobsDutyError)),
        );
      }
    }
    if (mounted) setState(() => _togglingDuty = false);
  }

  // Dials India's national emergency number (112) directly — a real,
  // always-working safety action that needs no backend, unlike a
  // monitored-SOS system we don't have infrastructure to run.
  Future<void> _callSos() async {
    final uri = Uri(scheme: 'tel', path: '112');
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.jobsSosDialerError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(jobsFeedTickProvider); // rebuild once a real fetch/action lands
    // Keeps live GPS reporting alive for as long as this screen is in the
    // widget tree — which is the whole /tech/jobs stack, since job
    // detail/close are pushed on top rather than replacing this route. It
    // self-starts/stops on on-duty + active-job changes; nothing else to do
    // with the value here.
    ref.watch(technicianLocationReporterProvider);
    final repo = ref.watch(repositoryProvider);
    final stats = repo.techStats();
    final request = _requestOpen ? repo.incomingRequest() : null;
    final route = repo.routeToday();
    final t = context.l10n;

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
                        Eyebrow(t.jobsEyebrowTechnician),
                        const SizedBox(height: 3),
                        Text(
                          (ref.watch(technicianMeProvider)?['name']
                                  as String?) ??
                              t.jobsFallbackName,
                          style: context.type.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _togglingDuty
                        ? null
                        : () => _toggleDuty(stats.onDuty),
                    child: StatusChip(
                      stats.onDuty ? t.jobsOnDuty : t.jobsOffDuty,
                      tone: stats.onDuty ? ChipTone.success : ChipTone.neutral,
                    ),
                  ),
                  const SizedBox(width: 9),
                  _RoundIcon(
                    icon: Icons.sos_outlined,
                    danger: true,
                    onTap: _callSos,
                  ),
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
                    onTap: () => context.go('/tech/earnings'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Eyebrow(
                                t.jobsTodaysEarnings,
                                color: CareColors.brass,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                Money.rupees(stats.earningsTodayPaise),
                                style: CareType.mono(
                                  CareColors.porcelain,
                                  size: 26,
                                  w: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                t.jobsSummary(stats.jobsDone, stats.jobsTotal),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: CareColors.porcelain.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        CareDial(
                          value: stats.progress,
                          size: 60,
                          stroke: 7,
                          showTicks: false,
                          color: CareColors.brass,
                          trackColor: const Color(0x33F6F4EF),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatBox(
                          label: t.jobsRating,
                          value: '${stats.rating}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatBox(
                          label: t.jobsCompletedTotal,
                          value: '${stats.jobsCompletedTotal}',
                        ),
                      ),
                    ],
                  ),
                  if (request != null) ...[
                    SectionHeader(
                      t.jobsNewRequest,
                      trailing: Text(
                        _acceptSecs > 0
                            ? t.jobsAcceptIn(_acceptSecs.toString().padLeft(2, '0'))
                            : t.jobsOfferExpired,
                        style: CareType.mono(
                          context.scheme.error,
                          size: 11.5,
                          w: FontWeight.w600,
                        ),
                      ),
                    ),
                    CareCard(
                      borderColor: context.scheme.secondary,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              StatusChip(
                                request.serviceTitle,
                                tone: ChipTone.warning,
                                height: 24,
                              ),
                              Mono(request.jobId, color: context.care.inkMuted),
                            ],
                          ),
                          const SizedBox(height: 11),
                          if (request.areaLabel.isNotEmpty ||
                              request.distanceKm != null)
                            Text(
                              [
                                if (request.areaLabel.isNotEmpty) request.areaLabel,
                                if (request.distanceKm != null)
                                  t.jobsRequestDistance(request.distanceKm!.toStringAsFixed(1)),
                              ].join(' · '),
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            '${request.timeWindow} · payout ${Money.rupees(request.payoutPaise)} · ${request.note}',
                            style: context.type.bodySmall,
                          ),
                          const SizedBox(height: 13),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _passing
                                      ? null
                                      : () => _passRequest(request.jobId),
                                  child: _passing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Text(t.jobsPass),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _accepting
                                      ? null
                                      : () => _acceptRequest(request.jobId),
                                  child: _accepting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(t.jobsAccept),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  SectionHeader(t.jobsRouteToday),
                  Stagger(
                    children: [
                      for (final stop in route)
                        CareCard(
                          onTap: () => context.push('/tech/job/${stop.jobId}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  StatusChip(
                                    stop.status == StopStatus.inProgress
                                        ? t.jobsInProgress
                                        : t.jobsNext,
                                    tone: stop.status == StopStatus.inProgress
                                        ? ChipTone.success
                                        : ChipTone.neutral,
                                    height: 24,
                                  ),
                                  Mono(stop.time, color: context.care.inkMuted),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${stop.title} · ${stop.customerName}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(stop.meta, style: context.type.bodySmall),
                            ],
                          ),
                        ),
                    ],
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
        Text(
          value,
          style: CareType.mono(
            context.scheme.onSurface,
            size: 20,
            w: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    scale: 0.9,
    child: Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: danger ? context.scheme.errorContainer : context.scheme.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: danger ? Colors.transparent : context.care.hairline,
        ),
      ),
      child: Icon(icon, size: 18, color: danger ? context.scheme.error : null),
    ),
  );
}
