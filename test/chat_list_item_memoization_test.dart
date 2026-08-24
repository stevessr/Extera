import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat_list/chat_list_item.dart';
import 'package:extera_next/widgets/matrix.dart';

class _FailingDatabase implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected database call');
}

class _TestClient extends Client {
  _TestClient()
    : super(
        'chat-list-item-test',
        database: _FailingDatabase(),
        httpClient: MockClient((request) async => http.Response('{}', 404)),
      );

  @override
  String? get userID => '@self:example.invalid';
}

Room _room(Client client) {
  final room = Room(id: '!room:example.invalid', client: client)
    ..summary = RoomSummary.fromJson({
      'm.heroes': ['@alice:example.invalid'],
      'm.joined_member_count': 2,
    });
  // Named room so the hero-user FutureBuilder path stays dormant.
  (room.states[EventTypes.RoomName] ??= {})[''] = StrippedStateEvent(
    type: EventTypes.RoomName,
    stateKey: '',
    senderId: '@alice:example.invalid',
    content: {'name': 'Test Room'},
  );
  return room;
}

Future<void> _pumpItem(WidgetTester tester, Client client, Room room) async {
  final store = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    Matrix(
      clients: [client],
      store: store,
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: ChatListItem(room, onTap: () {})),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('reuses the built tile when inputs are unchanged', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = _TestClient();
    final room = _room(client);

    await _pumpItem(tester, client, room);
    final tileBefore = tester.widget<ListTile>(find.byType(ListTile));

    // Rebuild the whole host with fresh widget instances; the row's deps
    // snapshot is unchanged so the memoized tile must be reused verbatim.
    await _pumpItem(tester, client, room);
    final tileAfter = tester.widget<ListTile>(find.byType(ListTile));

    expect(identical(tileBefore, tileAfter), isTrue);
  });

  testWidgets('rebuilds the tile when the notification count changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = _TestClient();
    final room = _room(client);

    await _pumpItem(tester, client, room);
    final tileBefore = tester.widget<ListTile>(find.byType(ListTile));

    room.notificationCount += 1;
    await _pumpItem(tester, client, room);
    final tileAfter = tester.widget<ListTile>(find.byType(ListTile));

    expect(identical(tileBefore, tileAfter), isFalse);
  });

  testWidgets('rebuilds the tile when the room is renamed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = _TestClient();
    final room = _room(client);

    await _pumpItem(tester, client, room);
    expect(find.text('Test Room'), findsOneWidget);
    final tileBefore = tester.widget<ListTile>(find.byType(ListTile));

    (room.states[EventTypes.RoomName] ??= {})[''] = StrippedStateEvent(
      type: EventTypes.RoomName,
      stateKey: '',
      senderId: '@alice:example.invalid',
      content: {'name': 'Renamed Room'},
    );
    await _pumpItem(tester, client, room);
    final tileAfter = tester.widget<ListTile>(find.byType(ListTile));

    expect(find.text('Renamed Room'), findsOneWidget);
    expect(identical(tileBefore, tileAfter), isFalse);
  });
}
