/// Selects the unread boundary for the timeline that is actually open.
///
/// A room's m.fully_read event is not necessarily part of a thread (especially
/// when a muted room has unread thread replies). Never use it as a thread
/// boundary: trying to locate it can leave an unresolvable scroll banner that
/// prevents the thread from being marked as read.
String initialChatReadMarkerEventId({
  required bool roomHasNewMessages,
  required String roomFullyRead,
  String? threadRootEventId,
  bool threadHasNewMessages = false,
  String? threadReadEventId,
}) {
  if (threadRootEventId != null) {
    return threadHasNewMessages ? (threadReadEventId ?? '') : '';
  }
  return roomHasNewMessages ? roomFullyRead : '';
}

/// An older in-flight receipt must not clear unread counts for a newer reply.
bool shouldClearThreadUnreadAfterReceipt({
  required String acknowledgedEventId,
  required String? latestSyncedEventId,
}) => acknowledgedEventId == latestSyncedEventId;
