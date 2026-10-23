import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/pages/chat/retry_failed_event.dart';

class _RecordingRoom implements Room {
  final calls = <({Map<String, dynamic> content, String type, String? txid})>[];

  @override
  String get id => '!test:example.org';

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    calls.add((content: Map.of(content), type: type, txid: txid));
    return r'$sent';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Event _failedEvent(
  _RecordingRoom room, {
  required String type,
  required Map<String, dynamic> content,
  String eventId = r'$local-event',
  Map<String, dynamic>? unsigned,
  EventStatus status = EventStatus.error,
}) => Event(
  room: room,
  eventId: eventId,
  senderId: '@sender:example.org',
  type: type,
  content: content,
  originServerTs: DateTime.utc(2026, 10, 24),
  unsigned: unsigned,
  status: status,
);

void main() {
  test('failed sticker retries as m.sticker with its original payload', () async {
    final room = _RecordingRoom();
    final content = <String, dynamic>{
      'body': ':cat:',
      'url': 'mxc://example.org/cat',
      'info': {'mimetype': 'image/webp', 'w': 128, 'h': 128},
      'm.relates_to': {
        'rel_type': 'm.thread',
        'event_id': r'$thread-root',
        'm.in_reply_to': {'event_id': r'$thread-last'},
      },
    };
    final event = _failedEvent(
      room,
      type: EventTypes.Sticker,
      content: content,
      unsigned: {'transaction_id': 'original-txn'},
    );

    expect(await retryFailedEventPreservingType(event), r'$sent');

    expect(room.calls, hasLength(1));
    expect(room.calls.single.type, EventTypes.Sticker);
    expect(room.calls.single.txid, 'original-txn');
    expect(room.calls.single.content, content);
  });

  test('sticker without an unsigned transaction ID reuses its local ID', () async {
    final room = _RecordingRoom();
    final event = _failedEvent(
      room,
      type: EventTypes.Sticker,
      content: {'body': ':cat:', 'url': 'mxc://example.org/cat'},
    );

    await retryFailedEventPreservingType(event);

    expect(room.calls.single.txid, r'$local-event');
    expect(room.calls.single.type, EventTypes.Sticker);
  });

  test('ordinary text retries through the normal SDK path', () async {
    final room = _RecordingRoom();
    final event = _failedEvent(
      room,
      type: EventTypes.Message,
      content: {'msgtype': MessageTypes.Text, 'body': 'hello'},
      unsigned: {'transaction_id': 'text-txn'},
    );

    await retryFailedEventPreservingType(event);

    expect(room.calls.single.type, EventTypes.Message);
    expect(room.calls.single.txid, 'text-txn');
    expect(room.calls.single.content['body'], 'hello');
  });

  test('non-failed stickers are not sent again', () async {
    final room = _RecordingRoom();
    final event = _failedEvent(
      room,
      type: EventTypes.Sticker,
      content: {'body': ':cat:', 'url': 'mxc://example.org/cat'},
      status: EventStatus.sent,
    );

    expect(await retryFailedEventPreservingType(event), isNull);
    expect(room.calls, isEmpty);
  });
}
