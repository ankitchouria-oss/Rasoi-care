import 'package:go_router/go_router.dart';

import '../features/auth/auth_screens.dart';
import '../features/jobs/tech_jobs_screen.dart';
import '../features/jobs/tech_job_screen.dart';
import '../features/jobs/tech_close_screen.dart';

final router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(
      path: '/login',
      builder: (_, __) => const PhoneScreen(),
      routes: [
        GoRoute(path: 'otp', builder: (_, __) => const OtpScreen()),
        GoRoute(path: 'email', builder: (_, __) => const EmailAuthScreen()),
      ],
    ),

    GoRoute(path: '/tech/jobs', builder: (_, __) => const TechJobsScreen()),
    GoRoute(
        path: '/tech/job/:id',
        builder: (_, s) => TechJobScreen(jobId: s.pathParameters['id']!)),
    GoRoute(
        path: '/tech/job/:id/close',
        builder: (_, s) => TechCloseScreen(jobId: s.pathParameters['id']!)),
  ],
);
