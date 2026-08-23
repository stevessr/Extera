import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat_custom_experience/chat_custom_experience.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hub lists profile, wallpaper and privacy entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        // context.push is only called on tap; rendering alone needs no router.
        home: const ChatCustomExperience(roomId: '!room:example.org'),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold));
    expect(find.byType(ListTile), findsNWidgets(3));
    expect(find.text(L10n.of(context).roomProfile), findsOneWidget);
    expect(find.text(L10n.of(context).chatWallpaper), findsOneWidget);
    expect(find.text(L10n.of(context).privacy), findsOneWidget);
  });
}
