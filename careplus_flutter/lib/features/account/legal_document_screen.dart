// Real Terms of Service / Privacy Policy, fetched from the shared backend
// (GET /api/legal/terms or /api/legal/privacy — see app.py) rather than the
// "coming soon" placeholder this screen used to show. `kind` picks which
// document; degrades to a real error state (with a retry) if the backend
// isn't reachable, matching every other caller in lib/data/api.

import 'package:flutter/material.dart';

import '../../core/widgets/care_widgets.dart';
import '../../core/theme/care_plus_theme.dart';
import '../../data/api/backend_client.dart';
import '../../l10n/l10n_extensions.dart';

class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({super.key, required this.kind, required this.fallbackTitle});

  /// 'terms' or 'privacy' — matches the backend's /api/legal/<kind> route.
  final String kind;
  final String fallbackTitle;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = BackendClient().fetchLegalDocument(widget.kind);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: Text(widget.fallbackTitle),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final t = context.l10n;
            final doc = snapshot.data;
            if (doc == null) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
                children: [
                  Icon(Icons.cloud_off, size: 40, color: context.care.inkFaint),
                  const SizedBox(height: 12),
                  Text(t.legalDocLoadError,
                      style: context.type.bodyMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Center(
                    child: OutlinedButton(
                      onPressed: () => setState(_load),
                      child: Text(t.legalDocRetry),
                    ),
                  ),
                ],
              );
            }
            final sections = (doc['sections'] as List? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList(growable: false);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                if (doc['lastUpdated'] != null) ...[
                  Text(t.legalDocLastUpdated('${doc['lastUpdated']}'), style: context.type.bodySmall),
                  const SizedBox(height: 18),
                ],
                for (final section in sections) ...[
                  Text('${section['heading']}',
                      style: context.type.titleMedium?.copyWith(fontWeight: FontWeight.w700) ??
                          const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final para in (section['paragraphs'] as List? ?? const []))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text('$para', style: context.type.bodyMedium),
                    ),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
