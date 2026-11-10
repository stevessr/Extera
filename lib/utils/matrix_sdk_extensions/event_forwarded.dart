import 'package:matrix/matrix.dart';

const forwardedContentKeys = [
  'm.forwarded',
  'org.matrix.msc4553.forwarded',
  'com.famedly.app.forwarded',
];

class ForwardedEventInfo {
  final String? eventId;
  final String? roomId;
  final String? sender;
  final DateTime? originServerTs;

  final Map<String, Object?>? content;

  const ForwardedEventInfo({
    this.eventId,
    this.roomId,
    this.sender,
    this.originServerTs,
    this.content,
  });

  String? get permalink => roomId != null && eventId != null
      ? 'https://matrix.to/#/${Uri.encodeComponent(roomId!)}/${Uri.encodeComponent(eventId!)}'
      : null;
}

extension EventForwarded on Event {
  ForwardedEventInfo? get forwarded {
    for (final key in forwardedContentKeys) {
      final raw = content[key];
      if (raw is! Map) continue;
      final rawMap = raw is Map<String, Object?>
          ? raw
          : Map<String, Object?>.from(raw);
      final embeddedContent = rawMap.tryGetMap<String, Object?>('content');
      return ForwardedEventInfo(
        eventId: rawMap['event_id'] is String
            ? rawMap['event_id'] as String
            : null,
        roomId: rawMap['room_id'] is String
            ? rawMap['room_id'] as String
            : null,
        sender: rawMap['sender'] is String ? rawMap['sender'] as String : null,
        originServerTs: rawMap['origin_server_ts'] is int
            ? DateTime.fromMillisecondsSinceEpoch(
                rawMap['origin_server_ts'] as int,
              )
            : null,
        content: embeddedContent != null && embeddedContent['body'] is String
            ? embeddedContent
            : null,
      );
    }
    return null;
  }

  // pseudo event for viewing forwarded event source content
  Event get forwardedContentEvent {
    final f = forwarded;
    if (f == null) return this;
    final forwardedContent = f.content;
    if (forwardedContent == null) return this;
    return Event(
      content: forwardedContent,
      type: type == EventTypes.Sticker ? type : EventTypes.Message,
      eventId: eventId,
      senderId: f.sender ?? senderId,
      originServerTs: f.originServerTs ?? originServerTs,
      room: room,
    );
  }
}
