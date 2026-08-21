import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// Shorthand for `AppLocalizations.of(context)!` — mirrors `context.type`/
/// `context.scheme` (see care_plus_theme.dart) so translated strings read
/// just as tersely: `context.l10n.accountSignOut`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
