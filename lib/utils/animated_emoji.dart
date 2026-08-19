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

/// The animation Google ships for [emoji], or `null` if there is none.
Uri? animatedEmojiUrl(String emoji) {
  final key = _codepointKey(emoji);
  final codepoint = kAnimatedEmojiCodepoints.contains(key)
      ? key
      : _byStrippedCodepoint[_stripVariationSelectors(key)];
  if (codepoint == null) return null;
  return Uri.parse(
    'https://fonts.gstatic.com/s/e/notoemoji/latest/$codepoint/lottie.json',
  );
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
    final url = animatedEmojiUrl(emoji);
    if (url == null) continue;

    addText(text.substring(index, match.start));
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: AnimatedEmojiImage(
          emoji: emoji,
          url: url,
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
