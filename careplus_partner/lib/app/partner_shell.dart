import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/care_plus_theme.dart';
import '../l10n/l10n_extensions.dart';

/// Bottom-nav shell for the five primary destinations — Home, Money,
/// Shifts, Profile, More — matching the tab layout of real gig-partner
/// apps (Swiggy Partner, Urban Company Partner) instead of the old
/// tap-a-card-to-push-a-screen navigation.
class PartnerShell extends StatelessWidget {
  const PartnerShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _icons = [
    (Icons.home_outlined, Icons.home),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet),
    (Icons.calendar_month_outlined, Icons.calendar_month),
    (Icons.person_outline, Icons.person),
    (Icons.grid_view_outlined, Icons.grid_view),
  ];

  void _go(int i) => navigationShell.goBranch(
    i,
    initialLocation: i == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final idx = navigationShell.currentIndex;
    final t = context.l10n;
    final labels = [t.navHome, t.navMoney, t.navShifts, t.navProfile, t.navMore];
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomAppBar(
        height: 66,
        padding: EdgeInsets.zero,
        color: context.scheme.surface,
        child: Row(
          children: [
            for (var i = 0; i < _icons.length; i++)
              _navItem(context, i, idx, labels[i]),
          ],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int i, int idx, String label) {
    final active = i == idx;
    final d = _icons[i];
    return Expanded(
      child: InkWell(
        onTap: () => _go(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? d.$2 : d.$1,
              size: 21,
              color: active ? context.scheme.primary : context.care.inkFaint,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? context.scheme.primary : context.care.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
