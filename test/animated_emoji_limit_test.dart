import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/config/animated_emoji_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/utils/animated_emoji.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      AppSettings.notoEmojiFont.key: true,
      AppSettings.animatedEmoji.key: true,
    });
    await AppSettings.init(loadWebConfigFile: false);
    await AppSettings.store.reload();
  });

  test('animated emoji playback limit defaults to 10', () {
    expect(maxAnimatedEmojiPerMessage, 10);
  });

  test('allows exactly the configured number of animated emoji', () {
    final text = List.filled(maxAnimatedEmojiPerMessage, '😀').join();
    final spans = buildAnimatedEmojiSpans(text, fontSize: 14);

    expect(spans.whereType<WidgetSpan>().length, maxAnimatedEmojiPerMessage);
  });

  test('keeps the whole text static after the configured limit', () {
    final text = List.filled(maxAnimatedEmojiPerMessage + 1, '😀').join();
    final spans = buildAnimatedEmojiSpans(text, fontSize: 14);

    expect(spans, hasLength(1));
    expect(spans.single, isA<TextSpan>());
    expect((spans.single as TextSpan).text, text);
  });

  test('counts emoji across split and nested spans before animating', () {
    final firstHalf = List.filled(6, '😀').join();
    final secondHalf = List.filled(5, '😀').join();
    final original = <InlineSpan>[
      TextSpan(
        text: firstHalf,
        children: [TextSpan(text: secondHalf)],
      ),
    ];

    final result = replaceEmojiInSpans(original, fontSize: 14);

    expect(identical(result.single, original.single), isTrue);
    expect(result.whereType<WidgetSpan>(), isEmpty);
  });
}
