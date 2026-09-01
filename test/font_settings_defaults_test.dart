import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/config/app_settings.dart';

void main() {
  test('default font fallbacks do not implicitly opt into SystemFont', () {
    expect(AppSettings.fallbackFonts.defaultValue, 'sans-serif');
    expect(AppSettings.chatFallbackFonts.defaultValue, 'sans-serif');
    expect(
      AppSettings.monospaceFallbackFonts.defaultValue,
      'monospace,sans-serif',
    );

    for (final fallback in [
      AppSettings.fallbackFonts.defaultValue,
      AppSettings.chatFallbackFonts.defaultValue,
      AppSettings.monospaceFallbackFonts.defaultValue,
    ]) {
      expect(fallback.split(','), isNot(contains('SystemFont')));
    }
  });
}
