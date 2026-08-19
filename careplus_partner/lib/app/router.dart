import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screens.dart';
import '../features/apply/tech_apply_screen.dart';
import '../features/apply/tech_financial_screen.dart';
import '../features/apply/tech_pending_screen.dart';
import '../features/apply/tech_profile_screen.dart';
import '../features/apply/tech_more_screen.dart';
import '../features/earnings/tech_earnings_screen.dart';
import '../features/jobs/tech_jobs_screen.dart';
import '../features/jobs/tech_shifts_screen.dart';
import '../features/jobs/tech_job_screen.dart';
import '../features/jobs/tech_close_screen.dart';
import '../features/jobs/airflow_check_screen.dart';
import '../features/support/coming_soon_screen.dart';
import '../features/support/language_screen.dart';
import '../features/support/tech_help_screen.dart';
import '../l10n/l10n_extensions.dart';
import 'partner_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(
      path: '/login',
      builder: (_, _) => const PhoneScreen(),
      routes: [GoRoute(path: 'otp', builder: (_, _) => const OtpScreen())],
    ),

    GoRoute(
      path: '/tech/apply',
      parentNavigatorKey: _rootKey,
      builder: (_, s) =>
          TechApplyScreen(existing: s.extra as Map<String, dynamic>?),
    ),
    GoRoute(
      path: '/tech/pending',
      parentNavigatorKey: _rootKey,
      builder: (_, __) => const TechPendingScreen(),
    ),
    GoRoute(
      path: '/tech/financial',
      parentNavigatorKey: _rootKey,
      builder: (_, __) => const TechFinancialScreen(),
    ),
    GoRoute(
      path: '/tech/help',
      parentNavigatorKey: _rootKey,
      builder: (_, __) => const TechHelpScreen(),
    ),
    GoRoute(
      path: '/tech/soon',
      parentNavigatorKey: _rootKey,
      builder: (context, s) =>
          ComingSoonScreen(title: s.extra as String? ?? context.l10n.moreWork),
    ),
    GoRoute(
      path: '/tech/language',
      parentNavigatorKey: _rootKey,
      builder: (_, __) => const LanguageScreen(),
    ),
    GoRoute(
      path: '/tech/job/:id',
      parentNavigatorKey: _rootKey,
      builder: (_, s) => TechJobScreen(jobId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/tech/job/:id/close',
      parentNavigatorKey: _rootKey,
      builder: (_, s) => TechCloseScreen(jobId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/tech/job/:id/airflow',
      parentNavigatorKey: _rootKey,
      builder: (_, s) {
        final extra = s.extra as (String, String)?;
        return AirflowCheckScreen(
          jobId: s.pathParameters['id']!,
          customerName: extra?.$1 ?? 'Customer',
          customerArea: extra?.$2 ?? '',
        );
      },
    ),

    // Home / Money / Shifts / Profile / More — the five persistent tabs,
    // matching the bottom-nav shape of Swiggy Partner / Urban Company
    // Partner instead of the old tap-a-card-to-push-a-screen navigation.
    StatefulShellRoute.indexedStack(
      parentNavigatorKey: _rootKey,
      builder: (_, __, shell) => PartnerShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tech/jobs',
              builder: (_, __) => const TechJobsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tech/earnings',
              builder: (_, __) => const TechEarningsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tech/shifts',
              builder: (_, __) => const TechShiftsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tech/profile',
              builder: (_, __) => const TechProfileScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tech/more',
              builder: (_, __) => const TechMoreScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
