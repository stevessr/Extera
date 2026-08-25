import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n_en.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/cached_localized_body.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';

class _FailingDatabase implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected database call');
}

Client _client() => Client(
  'cached-localized-body-test',
  database: _FailingDatabase(),
  httpClient: MockClient((request) async => http.Response('{}', 404)),
);

void _addMember(Room room, String mxid, String displayname) {
  // Seed the member into memory so the SDK's unknown-sender background
  // lookup (which would hit the failing fake database) never runs.
  (room.states[EventTypes.RoomMember] ??= {})[mxid] = StrippedStateEvent(
    type: EventTypes.RoomMember,
    stateKey: mxid,
    senderId: mxid,
    content: {'membership': Membership.join.name, 'displayname': displayname},
  );
}

Event _event(Room room, {String body = 'hello'}) => Event(
  type: EventTypes.Message,
  content: {'msgtype': 'm.text', 'body': body},
  senderId: '@alice:example.invalid',
  originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
  eventId: '\$evt1',
  room: room,
);

void main() {
  group('CachedLocalizedBody', () {
    test('memoizes the sync fallback per event instance', () {
      final room = Room(id: '!room:example.invalid', client: _client());
      final first = _event(room);
      _addMember(room, '@alice:example.invalid', 'Alice');
      final replaced = _event(room, body: 'changed');

      final body = first.calcLocalizedBodyFallbackCached(
        MatrixLocals(L10nEn()),
      );
      expect(body, contains('hello'));
      expect(
        first.calcLocalizedBodyFallbackCached(MatrixLocals(L10nEn())),
        body,
      );

      // A replaced event instance must not inherit the old cached body.
      expect(
        replaced.calcLocalizedBodyFallbackCached(MatrixLocals(L10nEn())),
        contains('changed'),
      );
    });

    test('reuses one future per instance and flag combination', () async {
      final room = Room(id: '!room:example.invalid', client: _client());
      final event = _event(room);
      _addMember(room, '@alice:example.invalid', 'Alice');

      final plain = event.calcLocalizedBodyCached(MatrixLocals(L10nEn()));
      final plainAgain = event.calcLocalizedBodyCached(MatrixLocals(L10nEn()));
      final hiddenEdit = event.calcLocalizedBodyCached(
        MatrixLocals(L10nEn()),
        hideEdit: true,
      );

      expect(identical(plain, plainAgain), isTrue);
      expect(identical(plain, hiddenEdit), isFalse);
      await expectLater(plain, completion(isA<String>()));
    });

    test('evicts failed sender lookups so they are retried', () async {
      // Rooms start as partial, so the lookup touches the database which
      // fails in this harness: a deterministic failed lookup.
      final room = Room(id: '!room:example.invalid', client: _client());
      final event = _event(room);

      final first = event.fetchSenderUserCached();
      final second = event.fetchSenderUserCached();
      expect(identical(first, second), isTrue);

      await first.then<void>((_) {}, onError: (Object _) {});

      expect(identical(event.fetchSenderUserCached(), second), isFalse);
    });
  });
}
