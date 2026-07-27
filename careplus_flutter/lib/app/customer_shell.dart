import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/care_plus_theme.dart';

/// Bottom-nav shell for the four primary destinations. The center "Book" FAB
/// jumps into the catalog to start a fresh booking.
class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _dests = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.grid_view_outlined, Icons.grid_view, 'Services'),
    (Icons.event_note_outlined, Icons.event_note, 'Bookings'),
    (Icons.person_outline, Icons.person, 'Account'),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/services'),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        height: 68,
        padding: EdgeInsets.zero,
        color: context.scheme.surface,
        child: Row(
          children: [
            _navItem(context, 0, idx),
            _navItem(context, 1, idx),
            const Expanded(child: SizedBox()), // FAB notch
            _navItem(context, 2, idx),
            _navItem(context, 3, idx),
          ],
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
                size: 23,
                color: active ? context.scheme.primary : context.care.inkFaint),
            const SizedBox(height: 3),
            Text(d.$3,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? context.scheme.primary : context.care.inkFaint)),
          ],
        ),
      ),
    );
  }
}
