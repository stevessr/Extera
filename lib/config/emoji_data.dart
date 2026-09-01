import 'package:emojis/emoji.dart';

/// Unicode emoji data used by the standard emoji picker and suggestions.
///
/// The upstream package currently contains Unicode 17.0. The nine new emoji
/// and their skin-tone variants below are from the Unicode 18.0 data set.
abstract final class EmojiData {
  static const unicodeVersion = '18.0';

  static final List<Emoji> _all = List.unmodifiable([
    ...Emoji.all(),
    ..._unicode18,
  ]);

  /// One lazily built lookup table replaces repeated `all().firstWhere(...)`
  /// scans performed by every emoji-picker entry point.
  static final Map<String, Emoji> _lookup = Map.unmodifiable({
    for (final emoji in _all) ...{
      emoji.char: emoji,
      emoji.name: emoji,
      emoji.shortName: emoji,
    },
  });

  static List<Emoji> all() => _all;

  /// Resolves the values stored in recent-emoji history in O(1), whether the
  /// caller persisted a Unicode glyph, full emoji name or short name.
  static Emoji? lookup(String value) => _lookup[value];

  static const _unicode18 = [
    Emoji(
      name: 'cracking face',
      char: '\u{1FAEB}',
      shortName: 'cracking_face',
      emojiGroup: EmojiGroup.smileysEmotion,
      emojiSubgroup: EmojiSubgroup.faceNegative,
      keywords: ['face', 'crack', 'uc18'],
    ),
    Emoji(
      name: 'leftwards thumb sign',
      char: '\u{1FAF9}',
      shortName: 'leftwards_thumb_sign',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'left', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'leftwards thumb sign: light skin tone',
      char: '\u{1FAF9}\u{1F3FB}',
      shortName: 'leftwards_thumb_sign_tone1',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'left', 'skin tone', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'leftwards thumb sign: medium-light skin tone',
      char: '\u{1FAF9}\u{1F3FC}',
      shortName: 'leftwards_thumb_sign_tone2',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'left', 'skin tone', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'leftwards thumb sign: medium skin tone',
      char: '\u{1FAF9}\u{1F3FD}',
      shortName: 'leftwards_thumb_sign_tone3',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'left', 'skin tone', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'leftwards thumb sign: medium-dark skin tone',
      char: '\u{1FAF9}\u{1F3FE}',
      shortName: 'leftwards_thumb_sign_tone4',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'left', 'skin tone', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'leftwards thumb sign: dark skin tone',
      char: '\u{1FAF9}\u{1F3FF}',
      shortName: 'leftwards_thumb_sign_tone5',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'left', 'skin tone', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'rightwards thumb sign',
      char: '\u{1FAFA}',
      shortName: 'rightwards_thumb_sign',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'right', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'rightwards thumb sign: light skin tone',
      char: '\u{1FAFA}\u{1F3FB}',
      shortName: 'rightwards_thumb_sign_tone1',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'right', 'skin tone', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'rightwards thumb sign: medium-light skin tone',
      char: '\u{1FAFA}\u{1F3FC}',
      shortName: 'rightwards_thumb_sign_tone2',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'right', 'skin tone', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'rightwards thumb sign: medium skin tone',
      char: '\u{1FAFA}\u{1F3FD}',
      shortName: 'rightwards_thumb_sign_tone3',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'right', 'skin tone', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'rightwards thumb sign: medium-dark skin tone',
      char: '\u{1FAFA}\u{1F3FE}',
      shortName: 'rightwards_thumb_sign_tone4',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'right', 'skin tone', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'rightwards thumb sign: dark skin tone',
      char: '\u{1FAFA}\u{1F3FF}',
      shortName: 'rightwards_thumb_sign_tone5',
      emojiGroup: EmojiGroup.peopleBody,
      emojiSubgroup: EmojiSubgroup.handFingersClosed,
      keywords: ['hand', 'thumb', 'right', 'skin tone', 'uc18'],
      modifiable: true,
    ),
    Emoji(
      name: 'monarch butterfly',
      char: '\u{1FACC}',
      shortName: 'monarch_butterfly',
      emojiGroup: EmojiGroup.animalsNature,
      emojiSubgroup: EmojiSubgroup.animalBug,
      keywords: ['animal', 'insect', 'butterfly', 'uc18'],
    ),
    Emoji(
      name: 'pickle',
      char: '\u{1FADD}',
      shortName: 'pickle',
      emojiGroup: EmojiGroup.foodDrink,
      emojiSubgroup: EmojiSubgroup.foodVegetable,
      keywords: ['food', 'vegetable', 'uc18'],
    ),
    Emoji(
      name: 'lighthouse',
      char: '\u{1F6D9}',
      shortName: 'lighthouse',
      emojiGroup: EmojiGroup.travelPlaces,
      emojiSubgroup: EmojiSubgroup.transportWater,
      keywords: ['place', 'travel', 'water', 'uc18'],
    ),
    Emoji(
      name: 'meteor',
      char: '\u{1FA8B}',
      shortName: 'meteor',
      emojiGroup: EmojiGroup.travelPlaces,
      emojiSubgroup: EmojiSubgroup.skyWeather,
      keywords: ['space', 'sky', 'uc18'],
    ),
    Emoji(
      name: 'eraser',
      char: '\u{1FA8C}',
      shortName: 'eraser',
      emojiGroup: EmojiGroup.objects,
      emojiSubgroup: EmojiSubgroup.writing,
      keywords: ['object', 'writing', 'uc18'],
    ),
    Emoji(
      name: 'net with handle',
      char: '\u{1FA8D}',
      shortName: 'net_with_handle',
      emojiGroup: EmojiGroup.objects,
      emojiSubgroup: EmojiSubgroup.tool,
      keywords: ['object', 'tool', 'net', 'uc18'],
    ),
  ];
}
