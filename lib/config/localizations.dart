import 'package:material_ui/material_ui.dart';

import '../generated/l10n/l10n.dart';

/// The generated list uses Flutter's Material localization type. The extracted
/// [material_ui] package has its own type, so its delegates must be installed
/// alongside the generated delegates.
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  ...L10n.localizationsDelegates,
  ...GlobalMaterialLocalizations.delegates,
];
