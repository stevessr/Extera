import 'package:flutter/widgets.dart';

import 'package:extera_next/config/animated_emoji_data.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/widgets/animated_emoji_image.dart';

/// Matches a single emoji, including ZWJ sequences, skin tone modifiers,
/// keycaps and regional indicator (flag) pairs.
final RegExp _emojiPattern = RegExp(
  // Flags are pairs of regional indicators.
  r'(?:[\u{1F1E6}-\u{1F1FF}]{2})'
  // Keycaps, e.g. 1️⃣.
  r'|(?:[0-9#*]️?⃣)'
  // Everything else, optionally followed by a variation selector or skin tone
  // modifier and joined into a sequence with zero width joiners.
  r'|(?:\p{Extended_Pictographic}(?:️|[\u{1F3FB}-\u{1F3FF}])*'
  r'(?:‍\p{Extended_Pictographic}(?:️|[\u{1F3FB}-\u{1F3FF}])*)*)',
  unicode: true,
);

const String _variationSelector16 = 'fe0f';

/// Maps a codepoint key without variation selectors to the key Google actually
/// ships, so that both `❤` and `❤️` resolve to `2764_fe0f`.
final Map<String, String> _byStrippedCodepoint = {
  for (final codepoint in kAnimatedEmojiCodepoints)
    _stripVariationSelectors(codepoint): codepoint,
};

String _stripVariationSelectors(String codepointKey) => codepointKey
    .split('_')
    .where((part) => part != _variationSelector16)
    .join('_');

String _codepointKey(String emoji) =>
    emoji.runes.map((rune) => rune.toRadixString(16)).join('_');

/// Whether animated emoji should replace the glyphs of the emoji font.
///
/// Animated emoji are an extension of the Noto emoji font setting, so they are
/// only used while that font is enabled.
bool get animatedEmojiEnabled =>
    AppSettings.notoEmojiFont.value && AppSettings.animatedEmoji.value;

/// Directory the animations are downloaded into at build time.
const String animatedEmojiAssetDirectory = 'assets/animated_emoji';

/// The bundled animation of [codepoint].
String animatedEmojiAssetPath(String codepoint) =>
    '$animatedEmojiAssetDirectory/$codepoint.json';

/// Where [codepoint] can be downloaded from when it was not bundled.
Uri animatedEmojiUrl(String codepoint) => Uri.parse(
  'https://fonts.gstatic.com/s/e/notoemoji/latest/$codepoint/lottie.json',
);

/// Raster animation published alongside the Lottie source.
///
/// Dynamic-emoji sending uses this GIF as the source animation and then
/// transcodes it to the user's selected AVIF/GIF/APNG format. Keeping sending
/// separate from the Lottie preview avoids expensive frame-by-frame Flutter
/// canvas capture on every platform.
Uri animatedEmojiGifUrl(String codepoint) => Uri.parse(
  'https://fonts.gstatic.com/s/e/notoemoji/latest/$codepoint/512.gif',
);

/// The codepoint of the animation Google ships for [emoji], or `null` if there
/// is none.
String? animatedEmojiCodepoint(String emoji) {
  final key = _codepointKey(emoji);
  if (kAnimatedEmojiCodepoints.contains(key)) return key;
  return _byStrippedCodepoint[_stripVariationSelectors(key)];
}

/// Splits [text] into plain text spans and animated emoji.
///
/// Emoji without an animation, and every emoji while the setting is off, stay
/// part of the text so that they keep being rendered by the emoji font.
List<InlineSpan> buildAnimatedEmojiSpans(
  String text, {
  required double fontSize,
  TextStyle? style,
}) {
  if (!animatedEmojiEnabled || text.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }

  final spans = <InlineSpan>[];
  var index = 0;

  void addText(String value) {
    if (value.isEmpty) return;
    spans.add(TextSpan(text: value, style: style));
  }

  for (final match in _emojiPattern.allMatches(text)) {
    final emoji = match.group(0)!;
    final codepoint = animatedEmojiCodepoint(emoji);
    if (codepoint == null) continue;

    addText(text.substring(index, match.start));
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: AnimatedEmojiImage(
          emoji: emoji,
          codepoint: codepoint,
          fontSize: fontSize,
          style: style,
        ),
      ),
    );
    index = match.end;
  }

  if (spans.isEmpty) return [TextSpan(text: text, style: style)];
  addText(text.substring(index));
  return spans;
}

/// Replaces the emoji of every [TextSpan] in [spans] with animated ones.
///
/// Used for span trees that are built elsewhere, e.g. by the linkifier.
List<InlineSpan> replaceEmojiInSpans(
  List<InlineSpan> spans, {
  required double fontSize,
}) {
  if (!animatedEmojiEnabled) return spans;

  return spans.map((span) => _replaceEmojiInSpan(span, fontSize)).toList();
}

InlineSpan _replaceEmojiInSpan(InlineSpan span, double fontSize) {
  if (span is! TextSpan) return span;

  final children = span.children;
  final text = span.text;

  // A span cannot hold both its own emoji spans and its existing children, so
  // fold the text into the children list.
  final newChildren = <InlineSpan>[
    if (text != null && text.isNotEmpty)
      ...buildAnimatedEmojiSpans(text, fontSize: fontSize, style: span.style),
    if (children != null)
      for (final child in children) _replaceEmojiInSpan(child, fontSize),
  ];

  if (newChildren.isEmpty) return span;
  return TextSpan(
    style: span.style,
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
    children: newChildren,
  );
}

/// A [Text] that renders its emoji as animations when the setting is on.
///
/// Meant for the short, emoji heavy places outside of the message body:
/// reactions, reply previews and the emoji picker.
class AnimatedEmojiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextScaler? textScaler;

  /// Font size used to size the animations.
  ///
  /// Defaults to the font size of [style] or of the surrounding text style.
  final double? fontSize;

  const AnimatedEmojiText(
    this.text, {
    this.style,
    this.maxLines,
    this.overflow,
    this.textScaler,
    this.fontSize,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!animatedEmojiEnabled) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textScaler: textScaler,
      );
    }

    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final effectiveFontSize =
        fontSize ?? effectiveStyle.fontSize ?? kDefaultFontSize;

    return Text.rich(
      TextSpan(
        style: style,
        children: buildAnimatedEmojiSpans(
          text,
          fontSize: (textScaler ?? TextScaler.noScaling).scale(
            effectiveFontSize,
          ),
        ),
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      textScaler: textScaler,
    );
  }
}
