import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/stable_room_topic.dart';

void main() {
  test('builds a backwards-compatible stable rich topic', () {
    final content = stableRoomTopicContent('An interesting room');

    expect(content['topic'], 'An interesting room');
    expect(content['m.topic'], {
      'm.text': [
        {'body': 'An interesting room', 'mimetype': 'text/plain'},
      ],
    });
  });
}
