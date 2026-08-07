import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_screens.dart';
import '../features/dashboard/overview_screen.dart';
import '../features/dashboard/reports_screen.dart';
import '../features/dashboard/bookings_screen.dart';
import '../features/dashboard/team_screen.dart';
import '../features/dashboard/stock_screen.dart';
import '../features/dashboard/account_screen.dart';
import '../features/dashboard/staff_access_screen.dart';
import 'admin_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, __) => const EmailAuthScreen()),

    GoRoute(
        path: '/account',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const AccountScreen()),
    GoRoute(
        path: '/staff',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const StaffAccessScreen()),

    StatefulShellRoute.indexedStack(
      parentNavigatorKey: _rootKey,
      builder: (_, __, shell) => AdminShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/dashboard', builder: (_, __) => const OverviewScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/bookings', builder: (_, __) => const BookingsScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/team', builder: (_, __) => const TeamScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/stock', builder: (_, __) => const StockScreen())],
        ),
      ],
    ),
  ],
);
