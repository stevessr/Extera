import 'package:flutter/material.dart';

import 'package:emojis/emoji.dart';

import 'package:extera_next/config/emoji_data.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/animated_emoji.dart';
import 'package:extera_next/widgets/animated_emoji_image.dart';
import 'package:extera_next/widgets/emoji_picker.dart' show Category;

typedef AnimatedEmojiSelectionCallback = Future<void> Function(Emoji emoji);

/// Picker dedicated to the bundled Noto Animated Emoji set.
///
/// Unlike [MatrixEmojiPicker], this deliberately has no recent/custom-image
/// pack tabs: the only content is standard Unicode emoji for which Google
/// publishes an animation, grouped by the same categories as the normal emoji
/// picker.
class AnimatedEmojiPicker extends StatefulWidget {
  final AnimatedEmojiSelectionCallback onEmojiSelected;

  const AnimatedEmojiPicker({
    super.key,
    required this.onEmojiSelected,
  });

  @override
  State<AnimatedEmojiPicker> createState() => _AnimatedEmojiPickerState();
}

class _AnimatedEmojiPickerState extends State<AnimatedEmojiPicker>
    with SingleTickerProviderStateMixin {
  late final Map<Category, List<Emoji>> _grouped;
  late final Map<String, List<Emoji>> _skinToneVariations;
  late final List<Category> _categories;
  late final TabController _tabController;
  int _selectedCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _buildData();
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  void _buildData() {
    final animated = EmojiData.all()
        .where((emoji) => animatedEmojiCodepoint(emoji.char) != null)
        .toList(growable: false);

    _grouped = {for (final category in Category.values) category: <Emoji>[]};
    _skinToneVariations = <String, List<Emoji>>{};

    final baseByName = <String, Emoji>{};
    for (final emoji in animated) {
      if (_isSkinToneVariation(emoji)) {
        final baseName = _baseName(emoji);
        (_skinToneVariations[baseName] ??= <Emoji>[]).add(emoji);
      } else {
        baseByName[emoji.name] = emoji;
        _grouped[Category.fromEmojiGroup(emoji.emojiGroup)]!.add(emoji);
      }
    }

    // If Google only publishes a skin-tone variant for an emoji, keep one
    // representative in the grid instead of silently dropping that family.
    for (final entry in _skinToneVariations.entries) {
      if (baseByName.containsKey(entry.key) || entry.value.isEmpty) continue;
      final representative = entry.value.first;
      _grouped[Category.fromEmojiGroup(representative.emojiGroup)]!.add(
        representative,
      );
    }

    _categories = Category.values
        .where((category) => _grouped[category]!.isNotEmpty)
        .toList(growable: false);
  }

  static bool _isSkinToneVariation(Emoji emoji) =>
      emoji.name.contains(':') && emoji.name.contains('skin tone');

  static String _baseName(Emoji emoji) => emoji.name.contains(':')
      ? emoji.name.split(':').first.trim()
      : emoji.name;

  List<Emoji> _variationsFor(Emoji emoji) {
    final variants = _skinToneVariations[_baseName(emoji)];
    if (variants == null || variants.isEmpty) return const [];

    final result = <Emoji>[];
    if (!_isSkinToneVariation(emoji)) result.add(emoji);
    result.addAll(variants);
    return result;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_categories.isEmpty) {
      return Center(child: Text(L10n.of(context).nothingFound));
    }

    final theme = Theme.of(context);
    final category = _categories[_selectedCategoryIndex];
    final emojis = _grouped[category]!;

    return Column(
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: theme.colorScheme.secondary,
            unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
            indicatorColor: theme.colorScheme.secondary,
            padding: EdgeInsets.zero,
            onTap: (index) {
              setState(() => _selectedCategoryIndex = index);
            },
            tabs: [
              for (final item in _categories)
                Tooltip(
                  message: item.name,
                  child: Tab(icon: Icon(item.icon, size: 22)),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            key: ValueKey(category),
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: emojis.length,
            itemBuilder: (context, index) => _buildTile(emojis[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(Emoji emoji) {
    final codepoint = animatedEmojiCodepoint(emoji.char)!;
    final variations = _variationsFor(emoji);
    final hasVariations = variations.length > 1;

    return Semantics(
      button: true,
      label: emoji.name,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onEmojiSelected(emoji),
          onLongPress: hasVariations
              ? () => _showSkinToneMenu(context, emoji)
              : null,
          child: Stack(
            children: [
              Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedEmojiImage(
                    emoji: emoji.char,
                    codepoint: codepoint,
                    fontSize: 30,
                  ),
                ),
              ),
              if (hasVariations)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSkinToneMenu(BuildContext context, Emoji baseEmoji) async {
    final variations = _variationsFor(baseEmoji);
    if (variations.length <= 1) return;

    final selected = await showModalBottomSheet<Emoji>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final emoji in variations)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).pop(emoji),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: AnimatedEmojiImage(
                      emoji: emoji.char,
                      codepoint: animatedEmojiCodepoint(emoji.char)!,
                      fontSize: 34,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (selected != null) await widget.onEmojiSelected(selected);
  }
}
