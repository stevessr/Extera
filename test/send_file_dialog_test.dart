import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/send_file_dialog.dart';

void main() {
  late MatrixSdkDatabase database;
  late Room room;

  setUpAll(() async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({
      AppSettings.sendOnEnter.key: false,
    });
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.reload();
  });

  setUp(() async {
    database = await MatrixSdkDatabase.init(
      'send_file_dialog_test_${DateTime.now().microsecondsSinceEpoch}',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    room = Room(
      id: '!send-file-dialog-test:example.org',
      client: Client('send_file_dialog_test', database: database),
    );
  });

  tearDown(() => database.delete());

  testWidgets('renders transparent preview pixels on a transparent surface', (
    tester,
  ) async {
    const previewSurface = Colors.transparent;
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
      ).copyWith(surfaceContainerHighest: previewSurface),
    );
    final transparentPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => SendFileDialog(
            room: room,
            thread: null,
            files: [
              XFile.fromData(
                transparentPng,
                name: 'transparent.png',
                mimeType: 'image/png',
              ),
            ],
            outerContext: context,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.type == MaterialType.canvas &&
            widget.color == previewSurface,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Material && widget.color == Colors.black,
      ),
      findsNothing,
    );
  });
}
