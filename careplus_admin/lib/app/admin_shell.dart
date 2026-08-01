import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/care_plus_theme.dart';

/// Bottom-nav shell for the five primary destinations.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _dests = [
    (Icons.insights_outlined, Icons.insights, 'Overview'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Reports'),
    (Icons.event_note_outlined, Icons.event_note, 'Bookings'),
    (Icons.groups_outlined, Icons.groups, 'Team'),
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Stock'),
  ];

  void _go(int i) => navigationShell.goBranch(
        i,
        initialLocation: i == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final idx = navigationShell.currentIndex;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomAppBar(
        height: 68,
        padding: EdgeInsets.zero,
        color: context.scheme.surface,
        child: Row(
          children: [for (var i = 0; i < _dests.length; i++) _navItem(context, i, idx)],
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int i, int idx) {
    final active = i == idx;
    final d = _dests[i];
    return Expanded(
      child: InkWell(
        onTap: () => _go(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? d.$2 : d.$1,
                size: 21,
                color: active ? context.scheme.primary : context.care.inkFaint),
            const SizedBox(height: 3),
            Text(d.$3,
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? context.scheme.primary : context.care.inkFaint)),
          ],
        ),
      ),
    );
  }
}
