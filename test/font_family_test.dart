import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/font_family.dart';

void main() {
  group('resolveFontFamily', () {
    test('system font overrides configured font', () {
      expect(
        resolveFontFamily(useSystemFont: true, configuredFont: 'Roboto'),
        'SystemFont',
      );
    });

    test('trims configured font and treats blank values as unset', () {
      expect(
        resolveFontFamily(useSystemFont: false, configuredFont: ' Roboto '),
        'Roboto',
      );
      expect(
        resolveFontFamily(useSystemFont: false, configuredFont: '   '),
        isNull,
      );
    });
  });

  group('resolveFontFallbacks', () {
    test('trims, de-duplicates and drops the primary family', () {
      expect(
        resolveFontFallbacks(
          configuredFallbacks: ' Roboto, SystemFont,Roboto, ,sans-serif ',
          primaryFont: 'SystemFont',
        ),
        ['Roboto', 'sans-serif'],
      );
    });

    test('keeps Noto Color Emoji first without duplicates', () {
      expect(
        resolveFontFallbacks(
          configuredFallbacks: 'Roboto,Noto Color Emoji,sans-serif',
          primaryFont: 'Roboto',
          includeNotoEmoji: true,
        ),
        ['Noto Color Emoji', 'sans-serif'],
      );
    });

    test('returns null for an empty effective fallback chain', () {
      expect(
        resolveFontFallbacks(
          configuredFallbacks: ' ,Roboto, ',
          primaryFont: 'Roboto',
        ),
        isNull,
      );
    });
  });
}
