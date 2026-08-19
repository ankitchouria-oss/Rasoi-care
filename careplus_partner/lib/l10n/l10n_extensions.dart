import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// Shorthand for `AppLocalizations.of(context)!` — every screen already
/// reaches for `context.type`/`context.scheme` (see care_plus_theme.dart),
/// so this keeps translated strings just as terse: `context.l10n.jobsAccept`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
