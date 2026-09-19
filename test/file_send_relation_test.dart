import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/pages/chat/file_send_relation.dart';

void main() {
  const rootEventId = r'$root';
  const lastEventId = r'$last';
  const replyEventId = r'$reply';

  test(
    'thread attachment retains thread relation and fallback on retry',
    () {
      final relation = buildFileSendRelation(
        threadRootEventId: rootEventId,
        threadLastEventId: lastEventId,
      );

      expect(relation, {
        'event_id': rootEventId,
        'rel_type': 'm.thread',
        'is_falling_back': true,
        'm.in_reply_to': {'event_id': lastEventId},
      });
    },
  );

  test('a reply in a thread remains a thread event', () {
    final relation = buildFileSendRelation(
      threadRootEventId: rootEventId,
      threadLastEventId: lastEventId,
      inReplyToEventId: replyEventId,
    );

    expect(relation, {
      'event_id': rootEventId,
      'rel_type': 'm.thread',
      'is_falling_back': false,
      'm.in_reply_to': {'event_id': replyEventId},
    });
  });

  test('a new thread without replies falls back to its root', () {
    final relation = buildFileSendRelation(
      threadRootEventId: rootEventId,
      threadLastEventId: rootEventId,
    );

    expect(relation?['m.in_reply_to'], {'event_id': rootEventId});
  });

  test('room-level reply has no thread relationship', () {
    expect(
      buildFileSendRelation(inReplyToEventId: replyEventId),
      {
        'm.in_reply_to': {'event_id': replyEventId},
      },
    );
  });

  test('ordinary room attachment has no relationship', () {
    expect(buildFileSendRelation(), isNull);
  });
}
