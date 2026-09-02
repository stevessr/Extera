/// Stable MSC2545 shortcode constraints for image packs.
///
/// The stable specification limits image-pack shortcodes to 100 bytes and to
/// ASCII letters, digits, `-`, and `_`. Because every accepted character is
/// ASCII, the byte limit is exactly the same as the Dart string length limit
/// after validation/sanitization.
///
/// These constraints are for packs Extera creates or edits. Received legacy or
/// malformed packs should still be parsed and displayed on a best-effort basis.
const int maxEmoteShortcodeBytes = 100;
const String emoteShortcodeCharacters = r'a-zA-Z0-9_-';

/// Matches a shortcode that is valid for stable `m.room.image_pack` content.
final RegExp emoteShortcodePattern = RegExp(
  '^[$emoteShortcodeCharacters]{1,$maxEmoteShortcodeBytes}\$',
);

/// Matches runs which may be kept while editing a stable shortcode.
final RegExp emoteShortcodeAllowedCharacters = RegExp(
  '[$emoteShortcodeCharacters]+',
);

/// Matches a single character which may not appear in a stable shortcode.
final RegExp emoteShortcodeForbiddenCharacter = RegExp(
  '[^$emoteShortcodeCharacters]',
);

/// Converts an arbitrary historical/file-system name into a valid stable
/// MSC2545 shortcode while keeping already-valid names unchanged.
String sanitizeEmoteShortcode(String input, {String fallback = 'emote'}) {
  var shortcode = input.replaceAll(emoteShortcodeForbiddenCharacter, '_');
  if (shortcode.length > maxEmoteShortcodeBytes) {
    shortcode = shortcode.substring(0, maxEmoteShortcodeBytes);
  }
  if (shortcode.isEmpty) {
    shortcode = fallback;
  }
  return shortcode;
}

/// Returns a stable shortcode which does not collide with [used].
///
/// Collision suffixes are included in the 100-byte limit so migration never
/// produces an event a conforming homeserver is allowed to reject for its key.
String uniqueEmoteShortcode(String input, Set<String> used) {
  final base = sanitizeEmoteShortcode(input);
  if (used.add(base)) return base;

  var index = 2;
  while (true) {
    final suffix = '_$index';
    final maxBaseLength = maxEmoteShortcodeBytes - suffix.length;
    final prefix = base.length > maxBaseLength
        ? base.substring(0, maxBaseLength)
        : base;
    final candidate = '$prefix$suffix';
    if (used.add(candidate)) return candidate;
    index++;
  }
}
