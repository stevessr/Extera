import 'package:flutter_test/flutter_test.dart';

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
  });
}
