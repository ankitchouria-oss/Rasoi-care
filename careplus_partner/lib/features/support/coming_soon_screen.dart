// Generic placeholder for Urban-Company-style features (Credits, Loans, a
// parts shop, formal Training) that need real business infrastructure —
// lending, a store, a training/booking system — we don't have yet. Better to
// say so plainly than fabricate numbers or a fake flow.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/care_widgets.dart';

class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title, this.glyph = '🛠️'});
  final String title;
  final String glyph;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: context.pop),
        title: Text(title),
      ),
      body: SafeArea(
        top: false,
        child: EmptyState(
          glyph: glyph,
          title: '$title is coming soon',
          body: "We're still building this out — it'll show up here once it's ready.",
        ),
      ),
    );
  }
}
