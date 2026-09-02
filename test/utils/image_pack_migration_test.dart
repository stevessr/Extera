import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/emote_shortcode.dart';
import 'package:extera_next/utils/image_pack_migration.dart';

void main() {
  group('normalizeStableImagePackContent', () {
    test('moves legacy per-image usage to pack usage', () {
      final result = normalizeStableImagePackContent({
        'images': {
          'emoji': {
            'url': 'mxc://example.org/emoji',
            'usage': ['emoticon'],
          },
          'sticker': {
            'url': 'mxc://example.org/sticker',
            'usage': ['sticker'],
          },
        },
        'pack': {'display_name': 'Mixed'},
      });

      expect(result['pack']['usage'], ['emoticon', 'sticker']);
      expect(result['images']['emoji'].containsKey('usage'), isFalse);
      expect(result['images']['sticker'].containsKey('usage'), isFalse);
    });

    test('keeps an unrestricted legacy image pack unrestricted', () {
      final result = normalizeStableImagePackContent({
        'images': {
          'all': {'url': 'mxc://example.org/all'},
          'emoji': {
            'url': 'mxc://example.org/emoji',
            'usage': ['emoticon'],
          },
        },
      });

      expect(result['pack'], isNull);
      expect(result['images']['emoji'].containsKey('usage'), isFalse);
    });

    test('preserves explicit stable pack usage', () {
      final result = normalizeStableImagePackContent({
        'images': {
          'legacy-extra': {
            'url': 'mxc://example.org/sticker',
            'usage': ['emoticon'],
          },
        },
        'pack': {
          'display_name': 'Stickers',
          'usage': ['sticker'],
        },
      });

      expect(result['pack']['usage'], ['sticker']);
      expect(result['images']['legacy-extra'].containsKey('usage'), isFalse);
    });

    test('normalizes malformed legacy shortcodes without losing images', () {
      final oversized = List.filled(maxEmoteShortcodeBytes + 1, 'x').join();
      final result = normalizeStableImagePackContent({
        'images': {
          'a b': {'url': 'mxc://example.org/space'},
          'a?b': {'url': 'mxc://example.org/question'},
          '表情': {'url': 'mxc://example.org/unicode'},
          oversized: {'url': 'mxc://example.org/long'},
        },
      });

      final images = result['images'] as Map<String, dynamic>;
      expect(images.length, 4);
      expect(images.keys.every(emoteShortcodePattern.hasMatch), isTrue);
      expect(images.containsKey('a_b'), isTrue);
      expect(images.containsKey('a_b_2'), isTrue);
      expect(images.containsKey('__'), isTrue);
      expect(images.keys.any((key) => key.length == maxEmoteShortcodeBytes), true);
      expect(images['a_b']['body'], 'a b');
      expect(images['a_b_2']['body'], 'a?b');
      expect(images['__']['body'], '表情');
    });

    test('does not overwrite an explicit image body while normalizing', () {
      final result = normalizeStableImagePackContent({
        'images': {
          'bad code': {
            'url': 'mxc://example.org/image',
            'body': 'Existing description',
          },
        },
      });

      expect(result['images']['bad_code']['body'], 'Existing description');
    });
  });
}
