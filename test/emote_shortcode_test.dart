import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/emote_shortcode.dart';

void main() {
  group('stable MSC2545 emote shortcode', () {
    final maxLength = List.filled(maxEmoteShortcodeBytes, 'x').join();
    final oversized = List.filled(maxEmoteShortcodeBytes + 1, 'x').join();

    test('accepts the stable ASCII grammar up to 100 bytes', () {
      expect(emoteShortcodePattern.hasMatch('fox'), true);
      expect(emoteShortcodePattern.hasMatch('A-b_C9'), true);
      expect(emoteShortcodePattern.hasMatch(maxLength), true);
    });

    test('rejects non-ASCII, delimiters, whitespace and oversized names', () {
      expect(emoteShortcodePattern.hasMatch('表情'), false);
      expect(emoteShortcodePattern.hasMatch('привет'), false);
      expect(emoteShortcodePattern.hasMatch('has:colon'), false);
      expect(emoteShortcodePattern.hasMatch('has space'), false);
      expect(emoteShortcodePattern.hasMatch('has~tilde'), false);
      expect(emoteShortcodePattern.hasMatch(oversized), false);
      expect(emoteShortcodePattern.hasMatch(''), false);
    });

    test('keeps only stable character runs while editing', () {
      expect(
        emoteShortcodeAllowedCharacters
            .allMatches('fox 表情:x-y')
            .map((m) => m.group(0))
            .toList(),
        ['fox', 'x-y'],
      );
    });

    test('sanitizes arbitrary names and enforces the byte limit', () {
      expect(sanitizeEmoteShortcode('hello world'), 'hello_world');
      expect(sanitizeEmoteShortcode('表情'), '__');
      expect(sanitizeEmoteShortcode(''), 'emote');
      expect(sanitizeEmoteShortcode(oversized), maxLength);
    });

    test('creates deterministic unique names inside the byte limit', () {
      final used = <String>{};
      expect(uniqueEmoteShortcode('a b', used), 'a_b');
      expect(uniqueEmoteShortcode('a?b', used), 'a_b_2');

      expect(uniqueEmoteShortcode(maxLength, used), maxLength);
      final collision = uniqueEmoteShortcode(maxLength, used);
      expect(collision.length, maxEmoteShortcodeBytes);
      expect(collision.endsWith('_2'), isTrue);
      expect(emoteShortcodePattern.hasMatch(collision), isTrue);
    });
  });
}
