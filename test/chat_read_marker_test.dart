import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/pages/chat/chat_read_marker.dart';

void main() {
  group('initialChatReadMarkerEventId', () {
    test('room timeline keeps its own m.fully_read boundary', () {
      expect(
        initialChatReadMarkerEventId(
          roomHasNewMessages: true,
          roomFullyRead: r'$room-read',
        ),
        r'$room-read',
      );
      expect(
        initialChatReadMarkerEventId(
          roomHasNewMessages: false,
          roomFullyRead: r'$room-read',
        ),
        isEmpty,
      );
    });

    test('unread muted thread never inherits an unrelated room boundary', () {
      expect(
        initialChatReadMarkerEventId(
          roomHasNewMessages: true,
          roomFullyRead: r'$room-read',
          threadRootEventId: r'$thread-root',
          threadHasNewMessages: true,
        ),
        isEmpty,
      );
    });

    test('unread thread uses its own receipt when one is available', () {
      expect(
        initialChatReadMarkerEventId(
          roomHasNewMessages: false,
          roomFullyRead: r'$room-read',
          threadRootEventId: r'$thread-root',
          threadHasNewMessages: true,
          threadReadEventId: r'$thread-reply',
        ),
        r'$thread-reply',
      );
    });

    test('already-read thread does not reuse stale thread or room marker', () {
      expect(
        initialChatReadMarkerEventId(
          roomHasNewMessages: true,
          roomFullyRead: r'$room-read',
          threadRootEventId: r'$thread-root',
          threadHasNewMessages: false,
          threadReadEventId: r'$old-thread-reply',
        ),
        isEmpty,
      );
    });
  });
  group('shouldClearThreadUnreadAfterReceipt', () {
    test('clears unread state when the newest reply was acknowledged', () {
      expect(
        shouldClearThreadUnreadAfterReceipt(
          acknowledgedEventId: r'$reply-2',
          latestSyncedEventId: r'$reply-2',
        ),
        isTrue,
      );
    });

    test('keeps a newer reply unread while an older receipt completes', () {
      expect(
        shouldClearThreadUnreadAfterReceipt(
          acknowledgedEventId: r'$reply-1',
          latestSyncedEventId: r'$reply-2',
        ),
        isFalse,
      );
    });

    test('does not clear unread state without a synced reply', () {
      expect(
        shouldClearThreadUnreadAfterReceipt(
          acknowledgedEventId: r'$reply-1',
          latestSyncedEventId: null,
        ),
        isFalse,
      );
    });
  });

}
