// Real language picker — switching here actually re-renders every screen's
// UI chrome in the chosen language via AppLocalizations (see lib/l10n/).
// Job data that came from the server (a customer's name, an address a
// technician typed) is never machine-translated; only the app's own labels,
// buttons and messages change.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';
import '../../l10n/l10n_extensions.dart';
import '../../state/providers.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: Text(t.languagePickerTitle),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            CareCard(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  _langRow(
                    context,
                    ref,
                    label: t.languageEnglish,
                    locale: const Locale('en'),
                    selected: current.languageCode == 'en',
                  ),
                  Divider(height: 1, color: context.care.hairline),
                  _langRow(
                    context,
                    ref,
                    label: t.languageHindi,
                    locale: const Locale('hi'),
                    selected: current.languageCode == 'hi',
                    last: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(t.languageNote, style: context.type.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _langRow(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required Locale locale,
    required bool selected,
    bool last = false,
  }) {
    return InkWell(
      onTap: () => ref.read(localeProvider.notifier).set(locale),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 20, color: context.scheme.primary)
            else
              Icon(Icons.circle_outlined, size: 20, color: context.care.inkFaint),
          ],
        ),
      ),
    );
  }
}
