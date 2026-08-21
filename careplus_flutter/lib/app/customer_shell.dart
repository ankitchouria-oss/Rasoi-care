import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/care_widgets.dart';

/// Bottom-nav shell for the four primary destinations. The center "+" FAB
/// opens a sheet to either start a fresh booking or browse the cleaning-kit
/// shop.
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
          onPressed: () => _showQuickActions(context),
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
      ),
    );
  }

  void _showQuickActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader('Quick actions'),
              CareCard(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go('/services');
                },
                child: Row(children: [
                  Icon(Icons.event_available_outlined, size: 22, color: context.scheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Book a service',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text('Repair, install or maintain an appliance',
                            style: context.type.bodySmall),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              CareCard(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.push('/shop');
                },
                child: Row(children: [
                  Icon(Icons.shopping_bag_outlined, size: 22, color: context.scheme.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Rasoi Care Shop',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text('Cleaning kits for your appliances',
                            style: context.type.bodySmall),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          ),
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
