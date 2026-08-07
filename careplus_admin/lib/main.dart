import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/care_plus_theme.dart';
import 'state/providers.dart';
import 'app/router.dart';

void main() {
  runApp(const ProviderScope(child: RasoiCareAdminApp()));
}

class RasoiCareAdminApp extends ConsumerWidget {
  const RasoiCareAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Rasoi Care Admin',
      debugShowCheckedModeBanner: false,
      theme: CarePlusTheme.light(),
      darkTheme: CarePlusTheme.dark(),
      themeMode: mode,
      routerConfig: router,
    );
  }
}
