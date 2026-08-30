import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('link recognizer stays attached to linkified text', (tester) async {
    var taps = 0;
    final recognizer = TapGestureRecognizer()..onTap = () => taps++;
    addTearDown(recognizer.dispose);

    final spans = replaceEmojiInSpans(
      [
        TextSpan(
          text: 'https://example.com',
          recognizer: recognizer,
        ),
      ],
      fontSize: 14,
    );

    final linkSpan = spans.single as TextSpan;
    expect(linkSpan.text, 'https://example.com');
    expect(linkSpan.recognizer, same(recognizer));
    expect(linkSpan.children, isNull);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Text.rich(TextSpan(children: spans)),
      ),
    );

    await tester.tap(find.text('https://example.com', findRichText: true));
    expect(taps, 1);
  });
}
