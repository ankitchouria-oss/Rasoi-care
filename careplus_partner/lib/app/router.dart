import 'package:go_router/go_router.dart';

import '../features/auth/auth_screens.dart';
import '../features/apply/tech_apply_screen.dart';
import '../features/apply/tech_pending_screen.dart';
import '../features/jobs/tech_jobs_screen.dart';
import '../features/jobs/tech_job_screen.dart';
import '../features/jobs/tech_close_screen.dart';

final router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(
      path: '/login',
      builder: (_, _) => const PhoneScreen(),
      routes: [
        GoRoute(path: 'otp', builder: (_, _) => const OtpScreen()),
        GoRoute(path: 'email', builder: (_, _) => const EmailAuthScreen()),
      ],
    ),

    GoRoute(path: '/tech/apply', builder: (_, __) => const TechApplyScreen()),
    GoRoute(path: '/tech/pending', builder: (_, __) => const TechPendingScreen()),
    GoRoute(path: '/tech/jobs', builder: (_, __) => const TechJobsScreen()),
    GoRoute(
        path: '/tech/job/:id',
        builder: (_, s) => TechJobScreen(jobId: s.pathParameters['id']!)),
    GoRoute(
        path: '/tech/job/:id/close',
        builder: (_, s) => TechCloseScreen(jobId: s.pathParameters['id']!)),
  ],
);
