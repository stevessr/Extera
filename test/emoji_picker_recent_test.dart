import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/utils/emoji_picker_recent.dart';
import 'package:extera_next/widgets/emoji_picker.dart';

void main() {
  test('resolves standard and custom recent emoji from indexes', () {
    final categories = [
      const CustomCategory(
        id: 'pack',
        name: 'Pack',
        icon: SizedBox.shrink(),
        emojis: {'party_parrot': 'mxc://example/parrot'},
      ),
    ];

    final resolved = buildRecentPickerEmojis(
      recent: const [
        'cracking face',
        'mxc://example/parrot',
        'unknown-history-value',
      ],
      customCategories: categories,
    );

    expect(resolved[0].type, PickerEmojiType.standard);
    expect(resolved[0].standardEmoji?.name, 'cracking face');

    expect(resolved[1].type, PickerEmojiType.custom);
    expect(resolved[1].customId, 'party_parrot');
    expect(resolved[1].categoryId, 'pack');

    expect(resolved[2].type, PickerEmojiType.custom);
    expect(resolved[2].customData, 'unknown-history-value');
  });
}
