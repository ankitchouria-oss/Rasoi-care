import 'package:go_router/go_router.dart';

import '../features/auth/auth_screens.dart';
import '../features/apply/tech_apply_screen.dart';
import '../features/apply/tech_financial_screen.dart';
import '../features/apply/tech_pending_screen.dart';
import '../features/apply/tech_profile_screen.dart';
import '../features/earnings/tech_earnings_screen.dart';
import '../features/jobs/tech_jobs_screen.dart';
import '../features/jobs/tech_job_screen.dart';
import '../features/jobs/tech_close_screen.dart';
import '../features/support/coming_soon_screen.dart';
import '../features/support/tech_help_screen.dart';

final router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(
      path: '/login',
      builder: (_, _) => const PhoneScreen(),
      routes: [
        GoRoute(path: 'otp', builder: (_, _) => const OtpScreen()),
      ],
    ),

    GoRoute(
        path: '/tech/apply',
        builder: (_, s) =>
            TechApplyScreen(existing: s.extra as Map<String, dynamic>?)),
    GoRoute(path: '/tech/pending', builder: (_, __) => const TechPendingScreen()),
    GoRoute(path: '/tech/jobs', builder: (_, __) => const TechJobsScreen()),
    GoRoute(path: '/tech/profile', builder: (_, __) => const TechProfileScreen()),
    GoRoute(path: '/tech/earnings', builder: (_, __) => const TechEarningsScreen()),
    GoRoute(path: '/tech/financial', builder: (_, __) => const TechFinancialScreen()),
    GoRoute(path: '/tech/help', builder: (_, __) => const TechHelpScreen()),
    GoRoute(
        path: '/tech/soon',
        builder: (_, s) => ComingSoonScreen(title: s.extra as String? ?? 'Coming soon')),
    GoRoute(
        path: '/tech/job/:id',
        builder: (_, s) => TechJobScreen(jobId: s.pathParameters['id']!)),
    GoRoute(
        path: '/tech/job/:id/close',
        builder: (_, s) => TechCloseScreen(jobId: s.pathParameters['id']!)),
  ],
);
