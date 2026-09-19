import 'package:material_ui/material_ui.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/config/localizations.dart';
import 'package:extera_next/generated/l10n/l10n.dart';

void main() {
  testWidgets('provides material_ui localizations for Chinese', (tester) async {
    late String backButtonTooltip;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            backButtonTooltip = MaterialLocalizations.of(
              context,
            ).backButtonTooltip;
            return Text(backButtonTooltip);
          },
        ),
      ),
    );

    // Generated app translations are deferred; let their load complete
    // before checking the material_ui localization inherited by the child.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(seconds: 5));

    expect(backButtonTooltip, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
