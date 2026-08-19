/// Characters allowed in the shortcode of a custom emote or sticker.
///
/// Matrix itself puts no restriction on shortcodes, but they have to survive
/// the `:code:` markdown syntax, so whitespace and the delimiters themselves
/// are excluded. Everything from U+00C0 upwards is allowed, which covers
/// Chinese and every other non-latin script - the previous `[-\w]` only ever
/// accepted ASCII.
///
/// Deliberately expressed with plain code unit ranges rather than `\p{L}`:
/// the markdown parser of the matrix SDK builds its regexes without the
/// unicode flag, and both sides have to accept exactly the same codes.
/// Otherwise the app would happily store a shortcode that never renders as an
/// image once the message is sent.
const String emoteShortcodeCharacters = r'-\w\u00c0-\uffff';

/// Matches a shortcode that is valid as a whole.
final RegExp emoteShortcodePattern = RegExp('^[$emoteShortcodeCharacters]+\$');

/// Matches the runs of a string that may be kept in a shortcode.
///
/// Meant for `FilteringTextInputFormatter.allow`, which drops everything that
/// does not match instead of rejecting the whole input.
final RegExp emoteShortcodeAllowedCharacters = RegExp(
  '[$emoteShortcodeCharacters]+',
);

/// Matches a single character that may not appear in a shortcode.
final RegExp emoteShortcodeForbiddenCharacter = RegExp(
  '[^$emoteShortcodeCharacters]',
);
