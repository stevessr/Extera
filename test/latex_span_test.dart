import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:latext/latext.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/pages/chat/events/html_message.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  testWidgets('native LaTeX renders synchronously inside rich text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LatexSpan(math: r'x^2', fontSize: 16, color: Colors.black),
        ),
      ),
    );

    expect(find.byType(LaTexT), findsOneWidget);
    expect(find.byType(FutureBuilder<void>), findsNothing);
    expect(find.text(r'x^2'), findsNothing);
  });
}
