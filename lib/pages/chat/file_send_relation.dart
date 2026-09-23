/// Builds a message relation that survives attachment upload retries.
///
/// The Matrix SDK persists `extraContent` for a failed file event, but its
/// retry path does not persist the separate thread ID arguments. Keeping the
/// relation in the content prevents retried attachments from escaping a thread.
Map<String, dynamic>? buildFileSendRelation({
  String? threadRootEventId,
  String? threadLastEventId,
  String? inReplyToEventId,
}) {
  if (threadRootEventId != null) {
    final fallbackEventId =
        inReplyToEventId ?? threadLastEventId ?? threadRootEventId;
    return {
      'event_id': threadRootEventId,
      'rel_type': 'm.thread',
      'is_falling_back': inReplyToEventId == null,
      if (fallbackEventId != null)
        'm.in_reply_to': {'event_id': fallbackEventId},
    };
  }

  if (inReplyToEventId != null) {
    return {
      'm.in_reply_to': {'event_id': inReplyToEventId},
    };
  }

  return null;
}
