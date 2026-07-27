import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import 'customer_shell.dart';
import '../features/auth/auth_screens.dart';
import '../features/home/home_screen.dart';
import '../features/catalog/catalog_screens.dart';
import '../features/booking/booking_screens.dart';
import '../features/tracking/tracking_screen.dart';
import '../features/invoice/invoice_rate_screens.dart';
import '../features/account/account_screens.dart';
import '../features/technician/tech_jobs_screen.dart';
import '../features/technician/tech_job_screen.dart';
import '../features/technician/tech_close_screen.dart';
import '../features/admin/admin_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

Appliance _appliance(String? name) => Appliance.values.firstWhere(
      (a) => a.name == name,
      orElse: () => Appliance.chimney,
    );

/// A slide-up transition used for the booking flow, so it reads as a stacked
/// task rather than a tab switch.
CustomTransitionPage<void> _slideUp(Widget child) => CustomTransitionPage(
      child: child,
      transitionDuration: const Duration(milliseconds: 340),
      transitionsBuilder: (_, anim, __, c) => SlideTransition(
        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(
          CurvedAnimation(parent: anim, curve: const Cubic(.22, 1, .36, 1)),
        ),
        child: FadeTransition(opacity: anim, child: c),
      ),
    );

final router = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    GoRoute(
      path: '/login',
      builder: (_, __) => const PhoneScreen(),
      routes: [
        GoRoute(path: 'otp', builder: (_, __) => const OtpScreen()),
      ],
    ),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

    // Service detail sits above the shell so it can push the booking flow.
    GoRoute(
      path: '/services/:appliance',
      parentNavigatorKey: _rootKey,
      builder: (_, s) =>
          ServiceDetailScreen(appliance: _appliance(s.pathParameters['appliance'])),
    ),

    // Booking flow — root-level, slide-up, shares the BookingDraft notifier.
    GoRoute(
        path: '/book/issue',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, __) => _slideUp(const IssueScreen())),
    GoRoute(
        path: '/book/slot',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, __) => _slideUp(const SlotScreen())),
    GoRoute(
        path: '/book/address',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, __) => _slideUp(const AddressScreen())),
    GoRoute(
        path: '/book/payment',
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, __) => _slideUp(const PaymentScreen())),

    // Post-booking, keyed by booking id.
    GoRoute(
        path: '/booking/:id/confirmed',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => ConfirmedScreen(bookingId: s.pathParameters['id']!)),
    GoRoute(
        path: '/booking/:id/track',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => TrackingScreen(bookingId: s.pathParameters['id']!)),
    GoRoute(
        path: '/booking/:id/invoice',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => InvoiceScreen(bookingId: s.pathParameters['id']!)),
    GoRoute(
        path: '/booking/:id/rate',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => RateScreen(bookingId: s.pathParameters['id']!)),

    GoRoute(
        path: '/plans',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const PlansScreen()),

    // Technician app — a separate flow reached via "Switch app" in Account.
    GoRoute(
        path: '/tech/jobs',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const TechJobsScreen()),
    GoRoute(
        path: '/tech/job/:id',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => TechJobScreen(jobId: s.pathParameters['id']!)),
    GoRoute(
        path: '/tech/job/:id/close',
        parentNavigatorKey: _rootKey,
        builder: (_, s) => TechCloseScreen(jobId: s.pathParameters['id']!)),

    GoRoute(
        path: '/admin',
        parentNavigatorKey: _rootKey,
        builder: (_, __) => const AdminScreen()),

    // The four-tab customer shell.
    StatefulShellRoute.indexedStack(
      parentNavigatorKey: _rootKey,
      builder: (_, __, shell) => CustomerShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _shellKey,
          routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/services', builder: (_, __) => const CatalogScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/bookings', builder: (_, __) => const BookingsScreen())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/account', builder: (_, __) => const AccountScreen())],
        ),
      ],
    ),
  ],
);
