import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/config/emoji_data.dart';

void main() {
  test('includes the Unicode 18.0 additions in the standard data set', () {
    expect(EmojiData.unicodeVersion, '18.0');

    final names = EmojiData.all().map((emoji) => emoji.name).toSet();
    expect(
      names,
      containsAll([
        'cracking face',
        'leftwards thumb sign',
        'rightwards thumb sign',
        'monarch butterfly',
        'pickle',
        'lighthouse',
        'meteor',
        'eraser',
        'net with handle',
      ]),
    );
  });

  test('includes the Unicode 18.0 skin-tone variants', () {
    final names = EmojiData.all().map((emoji) => emoji.name).toSet();

    expect(
      names,
      containsAll([
        'leftwards thumb sign: light skin tone',
        'leftwards thumb sign: dark skin tone',
        'rightwards thumb sign: light skin tone',
        'rightwards thumb sign: dark skin tone',
      ]),
    );
  });

  test('lookup resolves char, full name and short name through one index', () {
    final crackingFace = EmojiData.lookup('cracking face');
    expect(crackingFace, isNotNull);
    expect(EmojiData.lookup(crackingFace!.char), same(crackingFace));
    expect(EmojiData.lookup(crackingFace.shortName), same(crackingFace));
    expect(EmojiData.lookup('not-an-emoji'), isNull);
  });
}
