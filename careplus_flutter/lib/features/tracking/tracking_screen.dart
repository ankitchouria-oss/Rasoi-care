import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../state/providers.dart';

class TrackingScreen extends ConsumerWidget {
  const TrackingScreen({super.key, required this.bookingId});
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tech = ref.watch(repositoryProvider).preferredTechnician;
    final etaAsync = ref.watch(etaProvider(bookingId));
    final eta = etaAsync.valueOrNull ?? 14;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        title: const Text('Live tracking'),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.ios_share))],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          children: [
            // Map placeholder — google_maps_flutter renders here in production.
            Container(
              height: 210,
              decoration: BoxDecoration(
                color: context.scheme.surfaceContainerHigh,
                borderRadius: Radii.rLg,
                border: Border.all(color: context.care.hairline),
              ),
              child: Center(
                child: Icon(Icons.map_outlined, size: 44, color: context.care.inkFaint),
              ),
            ),
            const SizedBox(height: 16),
            CareCard(
              child: Row(children: [
                CareDial(
                    value: (1 - eta / 20).clamp(0, 1),
                    size: 66,
                    color: context.scheme.secondary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow('Arriving in'),
                      const SizedBox(height: 2),
                      Text('$eta min',
                          style: CareType.mono(context.scheme.onSurface,
                              size: 24, w: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text('2.4 km away · slot 10:00–11:00 am',
                          style: context.type.bodySmall),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            CareCard(
              child: Row(children: [
                Blob(tech.initials, bg: context.scheme.primary, fg: context.scheme.onPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tech.name,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      Text('${tech.vehicle} · ★ ${tech.rating}',
                          style: context.type.bodySmall),
                    ],
                  ),
                ),
                _RoundIcon(icon: Icons.call, onTap: () {}),
                const SizedBox(width: 8),
                _RoundIcon(icon: Icons.chat_bubble_outline, onTap: () {}),
              ]),
            ),
            const SizedBox(height: 12),
            CareCard(
              color: context.scheme.primaryContainer,
              borderColor: Colors.transparent,
              child: Column(children: [
                Eyebrow('Start code — share when work begins'),
                const SizedBox(height: 8),
                Text('4402',
                    style: CareType.mono(context.scheme.primary, size: 30, w: FontWeight.w600)
                        .copyWith(letterSpacing: 8)),
              ]),
            ),
            const SectionHeader('Progress'),
            const StepDot(TimelineStepView('Booking confirmed',
                '9:12 am · paid ₹800 via UPI', TrackState.done)),
            const StepDot(TimelineStepView('Technician assigned',
                '9:14 am · Sandeep Pawar', TrackState.done)),
            const StepDot(TimelineStepView('On the way',
                '9:47 am · left Ashok Nagar hub', TrackState.now)),
            const StepDot(TimelineStepView('Work in progress', '', TrackState.upcoming)),
            const StepDot(TimelineStepView('Invoice and payment', '', TrackState.upcoming),
                last: true),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                  onPressed: () => context.push('/booking/$bookingId/invoice'),
                  child: const Text('Skip ahead → job completed')),
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
