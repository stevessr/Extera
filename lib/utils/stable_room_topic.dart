import 'package:matrix/matrix.dart';

/// Builds a Matrix v1.15+ `m.room.topic` content object.
///
/// The legacy plain `topic` remains mandatory for backwards compatibility,
/// while `m.topic` carries the extensible textual representation from MSC3765.
Map<String, dynamic> stableRoomTopicContent(String topic) => {
  'topic': topic,
  'm.topic': {
    'm.text': [
      {'body': topic, 'mimetype': 'text/plain'},
    ],
  },
};

extension StableRoomTopicExtension on Room {
  /// Writes both the legacy topic and the stable extensible `m.topic` block.
  Future<String> setStableDescription(String topic) => client.setRoomStateWithKey(
    id,
    EventTypes.RoomTopic,
    '',
    stableRoomTopicContent(topic),
  );
}
