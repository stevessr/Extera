import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/localizations.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/avatar_change_dialog.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/mxc_image.dart';

void main() {
  late MatrixSdkDatabase database;
  late Room room;

  setUpAll(() async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  setUp(() async {
    database = await MatrixSdkDatabase.init(
      'avatar_change_test_${DateTime.now().microsecondsSinceEpoch}',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    );
    room = Room(
      id: '!avatar-change-test:example.org',
      client: Client('avatar_change_test', database: database),
    );
  });

  tearDown(() => database.delete());

  Event event({
    required String type,
    required Map<String, dynamic> content,
    required Map<String, dynamic> unsigned,
  }) => Event(
    eventId: '\$avatar-change',
    type: type,
    content: content,
    unsigned: unsigned,
    stateKey: '@alice:example.org',
    senderId: '@alice:example.org',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1650000000000),
    room: room,
  );

  group('isAvatarChangeEvent', () {
    test('detects an avatar swap', () {
      final e = event(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'avatar_url': 'mxc://example.org/new'},
        unsigned: {
          'prev_content': {
            'membership': 'join',
            'avatar_url': 'mxc://example.org/old',
          },
        },
      );
      expect(isAvatarChangeEvent(e), isTrue);
    });

    test('detects an avatar removal', () {
      final e = event(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'avatar_url': null},
        unsigned: {
          'prev_content': {
            'membership': 'join',
            'avatar_url': 'mxc://example.org/old',
          },
        },
      );
      expect(isAvatarChangeEvent(e), isTrue);
    });

    test('ignores unchanged avatars', () {
      final e = event(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'avatar_url': 'mxc://example.org/same'},
        unsigned: {
          'prev_content': {
            'membership': 'join',
            'avatar_url': 'mxc://example.org/same',
          },
        },
      );
      expect(isAvatarChangeEvent(e), isFalse);
    });

    test('ignores member events without prev_content', () {
      final e = event(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'avatar_url': 'mxc://a/new'},
        unsigned: {'age': 1},
      );
      expect(isAvatarChangeEvent(e), isFalse);
    });

    test('ignores non-member events', () {
      final e = event(
        type: EventTypes.Message,
        content: {'msgtype': 'm.text', 'body': 'hi'},
        unsigned: {
          'prev_content': {'avatar_url': 'mxc://a/old'},
        },
      );
      expect(isAvatarChangeEvent(e), isFalse);
    });
  });

  testWidgets('dialog shows previous and new columns for avatar removal', (
    tester,
  ) async {
    final e = event(
      type: EventTypes.RoomMember,
      // The previous URI is not mxc, so no network fetch happens in tests and
      // both avatars render their initials fallback.
      content: {'membership': 'join', 'avatar_url': null},
      unsigned: {
        'prev_content': {
          'membership': 'join',
          'avatar_url': 'https://example.org/not-mxc',
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAvatarChangeDialog(context, e),
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
    await tester.tap(find.text('open'));

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('旧头像').evaluate().isNotEmpty) break;
    }

    expect(find.text('旧头像'), findsOneWidget);
    expect(find.text('新头像'), findsOneWidget);
    expect(find.text('头像变更'), findsOneWidget);
    expect(find.byType(Avatar), findsNWidgets(2));
    expect(find.byType(MxcImage), findsNothing);
  });
}
