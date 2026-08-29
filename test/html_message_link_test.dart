import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/events/message_content.dart';
import 'package:extera_next/utils/dummy_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingDatabase implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected database call');
}

const consentTitle = 'Open link in browser';

Event makeEvent(Room room, String formattedBody) => Event(
  eventId: '\$ev1',
  type: EventTypes.Message,
  originServerTs: DateTime.now(),
  content: {
    'msgtype': 'm.text',
    'body': 'check https://example.com',
    'format': 'org.matrix.custom.html',
    'formatted_body': formattedBody,
  },
  room: room,
  senderId: '@other:example.invalid',
);

Future<void> pumpContent(WidgetTester tester, Event event) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Center(
          child: MessageContent(
            event,
            timeline: DummyTimeline(),
            textColor: Colors.black,
            linkColor: Colors.blue,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  testWidgets('anchor link (text-only) opens consent dialog', (tester) async {
    final client = Client(
      'a',
      database: _FailingDatabase(),
      httpClient: MockClient((request) async => http.Response('{}', 404)),
    );
    final room = Room(id: '!room:example.invalid', client: client);
    await pumpContent(
      tester,
      makeEvent(room, '<a href="https://example.com">https://example.com</a>'),
    );
    // No InkWell anymore for text-only anchors.
    expect(find.byType(InkWell), findsNothing);
    final link = find.text('https://example.com', findRichText: true);
    expect(link, findsOneWidget);
    await tester.tap(link, warnIfMissed: true);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text(consentTitle, skipOffstage: false), findsOneWidget);
  });

  testWidgets('bare url text node opens consent dialog', (tester) async {
    final client = Client(
      'b',
      database: _FailingDatabase(),
      httpClient: MockClient((request) async => http.Response('{}', 404)),
    );
    final room = Room(id: '!room:example.invalid', client: client);
    await pumpContent(tester, makeEvent(room, 'https://example.com'));
    final link = find.text('https://example.com');
    expect(link, findsOneWidget);
    await tester.tap(link, warnIfMissed: true);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text(consentTitle, skipOffstage: false), findsOneWidget);
  });

  testWidgets('anchor with element children keeps widget rendering', (
    tester,
  ) async {
    final client = Client(
      'c',
      database: _FailingDatabase(),
      httpClient: MockClient((request) async => http.Response('{}', 404)),
    );
    final room = Room(id: '!room:example.invalid', client: client);
    await pumpContent(
      tester,
      makeEvent(room, '<a href="https://example.com">line1<br>line2</a>'),
    );
    // Complex anchor still uses the WidgetSpan/InkWell path.
    expect(find.byType(InkWell), findsOneWidget);
    expect(find.textContaining('line1', findRichText: true), findsOneWidget);
  });
}
