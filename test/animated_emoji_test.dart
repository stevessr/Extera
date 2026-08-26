import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/utils/animated_emoji.dart';
import 'package:extera_next/widgets/animated_emoji_image.dart';

void main() {
  group('animated emoji', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        AppSettings.notoEmojiFont.key: true,
        AppSettings.animatedEmoji.key: true,
      });
      await AppSettings.init(loadWebConfigFile: false);
      // `init` keeps the store it created for the first test, so the new mock
      // values only take effect after an explicit reload.
      await AppSettings.store.reload();
    });

    test('resolves the codepoint of an emoji', () {
      expect(animatedEmojiCodepoint('😀'), '1f600');
      expect(
        animatedEmojiUrl('1f600').toString(),
        'https://fonts.gstatic.com/s/e/notoemoji/latest/1f600/lottie.json',
      );
      expect(
        animatedEmojiAssetPath('1f600'),
        'assets/animated_emoji/1f600.json',
      );
    });

    test('normalizes the variation selector in both directions', () {
      expect(animatedEmojiCodepoint('❤️'), '2764_fe0f');
      expect(animatedEmojiCodepoint('❤'), '2764_fe0f');
    });

    test('keeps skin tone modifiers', () {
      expect(animatedEmojiCodepoint('👍🏽'), '1f44d_1f3fd');
    });

    test('has no animation for flags or plain text', () {
      expect(animatedEmojiCodepoint('🇨🇳'), null);
      expect(animatedEmojiCodepoint('a'), null);
    });

    test('splits text around animatable emoji', () {
      final spans = buildAnimatedEmojiSpans('hi 😀 there', fontSize: 14);
      expect(spans.length, 3);
      expect((spans[0] as TextSpan).text, 'hi ');
      expect(spans[1], isA<WidgetSpan>());
      expect((spans[2] as TextSpan).text, ' there');
    });

    test('keeps emoji without an animation as text', () {
      final spans = buildAnimatedEmojiSpans('flag 🇨🇳', fontSize: 14);
      expect(spans.length, 1);
      expect((spans.single as TextSpan).text, 'flag 🇨🇳');
    });

    test('handles zero width joiner sequences as one emoji', () {
      // 😶‍🌫️ is a single ZWJ sequence Google animates.
      const face = '\u{1F636}‍\u{1F32B}\u{FE0F}';
      final spans = buildAnimatedEmojiSpans(face, fontSize: 14);
      expect(spans.length, 1);
      expect(spans.single, isA<WidgetSpan>());
    });

    test('keeps an unanimated zero width joiner sequence intact', () {
      // 👨‍👩‍👧‍👦 has no animation, so it must stay one piece of text rather
      // than being split into its members.
      const family = '👨‍👩‍👧‍👦';
      final spans = buildAnimatedEmojiSpans(family, fontSize: 14);
      expect(spans.length, 1);
      expect((spans.single as TextSpan).text, family);
    });

    test('rewrites emoji nested in existing spans', () {
      final result = replaceEmojiInSpans([
        const TextSpan(
          text: 'a😀',
          children: [TextSpan(text: 'b😀')],
        ),
      ], fontSize: 14);

      final children = (result.single as TextSpan).children!;
      // 'a', emoji, then the nested span.
      expect(children.length, 3);
      expect((children[0] as TextSpan).text, 'a');
      expect(children[1], isA<WidgetSpan>());

      final nested = (children[2] as TextSpan).children!;
      expect((nested[0] as TextSpan).text, 'b');
      expect(nested[1], isA<WidgetSpan>());
    });

    test('does nothing while the setting is off', () async {
      SharedPreferences.setMockInitialValues({
        AppSettings.notoEmojiFont.key: true,
        AppSettings.animatedEmoji.key: false,
      });
      await AppSettings.store.reload();

      final spans = buildAnimatedEmojiSpans('hi 😀', fontSize: 14);
      expect(spans.length, 1);
      expect((spans.single as TextSpan).text, 'hi 😀');
    });

    testWidgets('AnimatedEmojiText animates a reaction key', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AnimatedEmojiText('😀'),
        ),
      );
      // The lottie renderer is deferred (kept out of the web startup
      // bundle). Its load timer lives in the fake-async zone, so advance
      // fake time (and let real async work run) until it has fired, or the
      // binding fails on a pending timer at teardown.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 5));
      // placeholder. What matters here is that the emoji became a widget span.
      expect(find.byType(AnimatedEmojiImage), findsOneWidget);
    });

    testWidgets('AnimatedEmojiText stays plain while the setting is off', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        AppSettings.notoEmojiFont.key: false,
        AppSettings.animatedEmoji.key: true,
      });
      await AppSettings.store.reload();

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AnimatedEmojiText('😀'),
        ),
      );
      expect(find.byType(AnimatedEmojiImage), findsNothing);
    });
  });
}
