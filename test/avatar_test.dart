import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/mxc_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  for (final entry in <String?, String>{
    'Alice Smith Jones': 'AS',
    '  Project   Room  ': 'PR',
    'Alice': 'Al',
    '中文房间': '中文',
    '👨‍👩‍👧‍👦朋友': '👨‍👩‍👧‍👦朋',
    'e\u0301clair': 'e\u0301c',
    'A': 'A',
    '   ': '@',
    null: '@',
  }.entries) {
    testWidgets('missing avatar uses initials for ${entry.key}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Avatar(name: entry.key)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byType(MxcImage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty avatar URI uses initials and updates with the name', (
    tester,
  ) async {
    for (final name in ['First Room', 'Second Room']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Avatar(name: name, mxContent: Uri()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(name == 'First Room' ? 'FR' : 'SR'), findsOneWidget);
      expect(find.byType(MxcImage), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
