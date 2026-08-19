import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/emote_shortcode.dart';

void main() {
  group('emote shortcode', () {
    test('accepts non-latin shortcodes', () {
      expect(emoteShortcodePattern.hasMatch('表情'), true);
      expect(emoteShortcodePattern.hasMatch('привет'), true);
      expect(emoteShortcodePattern.hasMatch('fox'), true);
      expect(emoteShortcodePattern.hasMatch('a-b_c'), true);
      expect(emoteShortcodePattern.hasMatch('中文mixed1'), true);
    });

    test('rejects characters that break the :code: syntax', () {
      expect(emoteShortcodePattern.hasMatch('有 空格'), false);
      expect(emoteShortcodePattern.hasMatch('has:colon'), false);
      expect(emoteShortcodePattern.hasMatch('包~名'), false);
      expect(emoteShortcodePattern.hasMatch(''), false);
    });

    test('keeps the valid runs of an input', () {
      expect(
        emoteShortcodeAllowedCharacters
            .allMatches('表情 包:x')
            .map((m) => m.group(0))
            .toList(),
        ['表情', '包', 'x'],
      );
    });

    test('sanitizes a file name without destroying non-latin characters', () {
      expect(
        '表情 包.png'.replaceAll(emoteShortcodeForbiddenCharacter, '_'),
        '表情_包_png',
      );
    });
  });
}
