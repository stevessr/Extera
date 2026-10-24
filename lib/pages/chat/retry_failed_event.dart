import 'package:matrix/matrix.dart';

/// Retry a failed sticker without changing its Matrix event type.
///
/// The pinned Matrix SDK's [Event.sendAgain] retries non-file events using
/// [Room.sendEvent]'s default type (m.room.message), which turns an m.sticker
/// into a plain text message containing its shortcode.
Future<String?> retryFailedEventPreservingType(Event event) {
  if (!event.status.isError) return Future.value(null);

  if (event.type == EventTypes.Sticker) {
    return event.room.sendEvent(
      event.content,
      type: event.type,
      txid: event.transactionId ?? event.eventId,
    );
  }

  // Keep the SDK's file-cache / upload retry handling for other messages.
  return event.sendAgain();
}
