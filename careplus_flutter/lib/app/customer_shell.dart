import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/care_plus_theme.dart';
import '../l10n/l10n_extensions.dart';

/// Bottom-nav shell for the four primary destinations. The center "+" FAB
/// opens the Rasoi Care Shop directly — booking a service still lives under
/// the "Services" tab.
class CustomerShell extends StatelessWidget {
  const CustomerShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _icons = [
    (Icons.home_outlined, Icons.home),
    (Icons.grid_view_outlined, Icons.grid_view),
    (Icons.event_note_outlined, Icons.event_note),
    (Icons.person_outline, Icons.person),
  ];

  void _go(int i) => navigationShell.goBranch(
        i,
        initialLocation: i == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final idx = navigationShell.currentIndex;
    final t = context.l10n;
    final labels = [t.navHome, t.navServices, t.navBookings, t.navAccount];
    // Without this, the system back button exits the app the moment you're
    // on any tab besides Home (Services/Bookings/Account) with nothing
    // pushed on top — StatefulShellRoute gives each tab its own navigation
    // stack, but does nothing on its own to send you back to the first tab
    // once that stack is empty. A pushed screen within the current tab
    // still pops normally first; this only fires once that tab's own stack
    // has nothing left to pop.
    return PopScope(
      canPop: idx == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _go(0);
      },
      child: Scaffold(
        body: navigationShell,
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push('/shop'),
          child: const Icon(Icons.add),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          height: 68,
          padding: EdgeInsets.zero,
          color: context.scheme.surface,
          child: Row(
            children: [
              _navItem(context, 0, idx, labels),
              _navItem(context, 1, idx, labels),
              const Expanded(child: SizedBox()), // FAB notch
              _navItem(context, 2, idx, labels),
              _navItem(context, 3, idx, labels),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(BuildContext context, int i, int idx, List<String> labels) {
    final active = i == idx;
    final icons = _icons[i];
    return Expanded(
      child: InkWell(
        onTap: () => _go(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? icons.$2 : icons.$1,
                size: 23,
                color: active ? context.scheme.primary : context.care.inkFaint),
            const SizedBox(height: 3),
            Text(labels[i],
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
