import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../l10n/l10n_extensions.dart';
import '../../state/auth_providers.dart';

/// Shown once the application's submitted but an admin hasn't verified the
/// technician yet — mirrors Urban Company's "we're reviewing your profile"
/// hold state. Nothing to do here but wait (or check again).
class TechPendingScreen extends ConsumerStatefulWidget {
  const TechPendingScreen({super.key});
  @override
  ConsumerState<TechPendingScreen> createState() => _TechPendingScreenState();
}

class _TechPendingScreenState extends ConsumerState<TechPendingScreen> {
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    final tech = await fetchTechnicianMe();
    if (!mounted) return;
    setState(() => _checking = false);
    final stage = stageFromTechnicianJson(tech);
    if (stage == TechnicianStage.jobs) {
      context.go('/tech/jobs');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.pendingStillReview)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CareDial(
                  value: 0.5,
                  size: 90,
                  stroke: 8,
                  child: Icon(Icons.hourglass_top, color: context.scheme.primary, size: 32),
                ),
                const SizedBox(height: 22),
                Text(t.pendingTitle, style: context.type.headlineMedium),
                const SizedBox(height: 10),
                Text(t.pendingBody,
                    textAlign: TextAlign.center,
                    style: context.type.bodyMedium),
                const SizedBox(height: 26),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StepDot(
                        TimelineStepView(t.pendingStep1Title,
                            t.pendingStep1Detail, TrackState.done),
                      ),
                      StepDot(
                        TimelineStepView(t.pendingStep2Title,
                            t.pendingStep2Detail, TrackState.now),
                      ),
                      StepDot(
                        TimelineStepView(t.pendingStep3Title,
                            t.pendingStep3Detail, TrackState.upcoming),
                        last: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _checking ? null : _checkStatus,
                    child: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(t.pendingCheckStatus),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    await ref.read(authServiceProvider).signOut();
                    ref.read(authFlowProvider.notifier).reset();
                    if (context.mounted) context.go('/login');
                  },
                  child: Text(t.commonSignOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
