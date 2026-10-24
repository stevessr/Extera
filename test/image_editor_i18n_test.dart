import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/config/localizations.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/widgets/adaptive_dialogs/image_editor_dialog.dart';

/// The editor feature (and its deferred chunk) contains no app-localization
/// for its own labels, which come from the in-file zh/zh_Hant tables. This
/// test pins the rendered strings per active locale to guard the wiring of
/// ProImageEditorConfigs.i18n.
///
/// The whole flow runs in a single testWidgets: the editor keeps process-wide
/// statics (icon font loader, deferred chunk) that do not survive a test
/// boundary, so per-locale tests would silently exercise nothing.
void main() {
  testWidgets('image editor follows the active locale', (tester) async {
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
      '42YAAAAASUVORK5CYII=',
    );

    Future<void> openEditor(Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showImageEditor(
                    context: context,
                    byteArray: Uint8List.fromList(pngBytes),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      // Deferred L10n resolution needs a real-async beat before settling.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(ElevatedButton).evaluate().isNotEmpty) break;
      }
      expect(find.text('open'), findsOneWidget);

      await tester.tap(find.text('open'));

      // The editor lives in a deferred lib; give its load a real-async beat,
      // then pump to surface its first frames.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      final paintBtn = const ValueKey('open-paint-editor-btn');
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(paintBtn).evaluate().isNotEmpty) break;
      }
      expect(
        find.byKey(paintBtn),
        findsOneWidget,
        reason: 'the editor bottom bar never appeared',
      );
    }

    Future<void> closeEditor() async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('open-paint-editor-btn')), findsNothing);
    }

    // Simplified Chinese: every bottom-bar tool label is translated.
    await openEditor(const Locale('zh'));
    expect(find.text('绘图'), findsOneWidget);
    expect(find.text('滤镜'), findsOneWidget);
    expect(find.text('调节'), findsOneWidget);
    expect(find.text('裁剪/旋转'), findsOneWidget);
    expect(find.text('文字'), findsOneWidget);
    expect(find.text('表情'), findsOneWidget);
    expect(find.byTooltip('撤销'), findsWidgets);
    expect(find.byTooltip('重做'), findsWidgets);
    await closeEditor();

    // Traditional Chinese: script-aware variant, not the simplified table.
    await openEditor(
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    expect(find.text('繪圖'), findsOneWidget);
    expect(find.text('濾鏡'), findsOneWidget);
    expect(find.text('裁切/旋轉'), findsOneWidget);
    expect(find.text('貼圖'), findsNothing);
    expect(find.byTooltip('復原'), findsWidgets);
    await closeEditor();

    // Everything else keeps the package's English defaults.
    await openEditor(const Locale('en'));
    expect(find.text('Paint'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Tune'), findsOneWidget);
    expect(find.text('Crop/ Rotate'), findsOneWidget);
    expect(find.text('Text'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsWidgets);
    expect(find.byTooltip('Redo'), findsWidgets);
    await closeEditor();
  });
}
