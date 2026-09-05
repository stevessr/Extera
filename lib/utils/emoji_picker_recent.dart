import 'package:extera_next/config/emoji_data.dart';
import 'package:extera_next/widgets/emoji_picker.dart';

/// Converts persisted recent-emoji values to picker models without repeatedly
/// scanning the full Unicode table or every image pack for each recent item.
List<PickerEmoji> buildRecentPickerEmojis({
  required Iterable<String> recent,
  required Iterable<CustomCategory> customCategories,
}) {
  final customByData = <String, PickerEmoji>{};

  // Build one URL/data -> picker model index for all custom packs. The old
  // callers nested over every pack and every image separately for each recent.
  for (final category in customCategories) {
    for (final entry in category.emojis.entries) {
      customByData.putIfAbsent(
        entry.value,
        () => PickerEmoji.custom(
          name: entry.key,
          customData: entry.value,
          categoryId: category.id,
        ),
      );
    }
  }

  PickerEmoji resolve(String value) {
    final custom = customByData[value];
    if (custom != null) return custom;

    final standard = EmojiData.lookup(value);
    if (standard != null) return PickerEmoji.standard(standard);

    // Keep unknown historical values visible instead of dropping them.
    return PickerEmoji.custom(name: value, customData: value, categoryId: null);
  }

  // Keep the runtime element type explicit for dart2js release builds.
  return List<PickerEmoji>.unmodifiable(recent.map<PickerEmoji>(resolve));
}
