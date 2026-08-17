import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
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
          const SnackBar(content: Text('Still under review — check back soon.')));
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Text('Application under review', style: context.type.headlineMedium),
                const SizedBox(height: 10),
                Text(
                    'We\'re checking your details and documents. This usually takes a day or two — you\'ll be able to go online for jobs as soon as you\'re verified.',
                    textAlign: TextAlign.center,
                    style: context.type.bodyMedium),
                const SizedBox(height: 26),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      StepDot(
                        TimelineStepView('Application submitted',
                            'Profile, documents and bank details on file', TrackState.done),
                      ),
                      StepDot(
                        TimelineStepView('Under review',
                            'Our team is checking your details', TrackState.now),
                      ),
                      StepDot(
                        TimelineStepView('Approved — ready for jobs',
                            'Go online and start getting job requests', TrackState.upcoming),
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
                        : const Text('Check status'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    await ref.read(authServiceProvider).signOut();
                    ref.read(authFlowProvider.notifier).reset();
                    if (context.mounted) context.go('/login');
                  },
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
