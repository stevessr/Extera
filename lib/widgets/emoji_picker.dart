import 'package:flutter/material.dart';

import 'package:emojis/emoji.dart';

import 'package:extera_next/config/emoji_data.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/animated_emoji.dart';

// ==========================================
// 1. Data Models
// ==========================================

/// Defines the type of emoji content
enum PickerEmojiType { standard, custom }

/// A unified wrapper for both Standard (Unicode) and Custom (Image/Asset) emojis.
class PickerEmoji {
  static final Map<Emoji, PickerEmoji> _standardCache = {};

  final PickerEmojiType type;

  // Standard Data
  final Emoji? standardEmoji; // From package

  // Custom Data
  final String? customData; // The Value from the Map (e.g., URL)
  final String? customId; // The Key from the Map (e.g., unique name)
  final String? categoryId; // To link back to CustomCategory.id

  // Common Data for UI/Search
  final String displayName;
  final List<String> keywords;

  /// Normalized once instead of lower-casing every keyword for every keystroke.
  final String searchText;

  /// Stable de-duplication key reused by search instead of allocating one on
  /// every keystroke.
  final String searchIdentity;

  /// Skin-tone variants are searchable through their base emoji and shown only
  /// in the long-press variation menu, not as duplicate grid cells.
  final bool isSkinToneVariation;
  final String? variationBaseName;

  factory PickerEmoji.standard(Emoji emoji) => _standardCache.putIfAbsent(
    emoji,
    () => PickerEmoji._standard(emoji),
  );

  PickerEmoji._standard(Emoji emoji)
    : type = PickerEmojiType.standard,
      standardEmoji = emoji,
      customData = null,
      customId = null,
      categoryId = null,
      displayName = emoji.char,
      keywords = emoji.keywords,
      searchText = '${emoji.char}\u0000${emoji.keywords.join('\u0000')}'
          .toLowerCase(),
      searchIdentity = '${PickerEmojiType.standard.index}:${emoji.char}',
      isSkinToneVariation =
          emoji.name.contains(':') && emoji.name.contains('skin tone'),
      variationBaseName =
          emoji.name.contains(':') && emoji.name.contains('skin tone')
          ? emoji.name.split(':').first.trim()
          : null;

  PickerEmoji.custom({
    required String name,
    required this.customData,
    required this.categoryId,
  }) : type = PickerEmojiType.custom,
       standardEmoji = null,
       customId = name,
       displayName = name,
       keywords = [name],
       searchText = name.toLowerCase(),
       searchIdentity = '${PickerEmojiType.custom.index}:$name',
       isSkinToneVariation = false,
       variationBaseName = null;
}

class CustomCategory {
  final String id;
  final String name;
  final Widget icon;

  /// Key: Name/Search term, Value: Data (URL, Path, Identifier)
  final Map<String, String> emojis;

  const CustomCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.emojis,
  });
}

// ==========================================
// 2. Configuration & Callbacks
// ==========================================

/// Updated callback: returns the wrapper so you can handle both types
typedef EmojiSelectionCallback =
    void Function(Category? category, PickerEmoji emoji);

/// Builder for rendering custom emoji tiles
typedef CustomEmojiBuilder =
    Widget Function(BuildContext context, String emojiData, double size);

// Standard Categories
enum Category {
  smileys(Icons.sentiment_satisfied_alt, [
    EmojiGroup.smileysEmotion,
    EmojiGroup.peopleBody,
  ]),
  animals(Icons.pets, [EmojiGroup.animalsNature]),
  food(Icons.fastfood, [EmojiGroup.foodDrink]),
  activities(Icons.sports_soccer, [EmojiGroup.activities]),
  travel(Icons.directions_car, [EmojiGroup.travelPlaces]),
  objects(Icons.lightbulb_outline, [EmojiGroup.objects, EmojiGroup.component]),
  symbols(Icons.emoji_symbols, [EmojiGroup.symbols]),
  flags(Icons.flag, [EmojiGroup.flags]);

  final IconData icon;
  final List<EmojiGroup> groups;

  const Category(this.icon, this.groups);

  static Category fromEmojiGroup(EmojiGroup group) {
    for (final cat in Category.values) {
      if (cat.groups.contains(group)) return cat;
    }
    return Category.symbols;
  }
}

/// Immutable process-wide index for Unicode emoji data.
///
/// [EmojiData.all] does not change while the app is running, so rebuilding
/// wrappers, variation maps and category filters for every picker instance is
/// pure duplicate work. This top-level final is lazily initialized on first
/// access (after the picker route animation settles) and reused afterwards.
class _StandardEmojiIndex {
  final List<PickerEmoji> all;
  final Map<Category, List<PickerEmoji>> byCategory;
  final Map<String, List<PickerEmoji>> variationsByBaseName;

  const _StandardEmojiIndex._({
    required this.all,
    required this.byCategory,
    required this.variationsByBaseName,
  });

  factory _StandardEmojiIndex.build() {
    final all = <PickerEmoji>[];
    final byCategory = <Category, List<PickerEmoji>>{
      for (final category in Category.values) category: <PickerEmoji>[],
    };
    final variations = <String, List<PickerEmoji>>{};
    final baseByName = <String, PickerEmoji>{};

    // One pass over the full Unicode table. The previous implementation made
    // two full passes on every picker open, then filtered the full list again
    // on every category switch.
    for (final emoji in EmojiData.all()) {
      final pickerEmoji = PickerEmoji.standard(emoji);
      all.add(pickerEmoji);

      if (pickerEmoji.isSkinToneVariation) {
        variations
            .putIfAbsent(
              pickerEmoji.variationBaseName!,
              () => <PickerEmoji>[],
            )
            .add(pickerEmoji);
        continue;
      }

      baseByName[emoji.name] = pickerEmoji;
      byCategory[Category.fromEmojiGroup(emoji.emojiGroup)]!.add(pickerEmoji);
    }

    // Variation lists are tiny compared with the full emoji table, so attach
    // each base emoji after the single main scan instead of rescanning all data.
    for (final entry in variations.entries) {
      final base = baseByName[entry.key];
      if (base != null) entry.value.insert(0, base);
    }

    return _StandardEmojiIndex._(
      all: List.unmodifiable(all),
      byCategory: Map.unmodifiable({
        for (final entry in byCategory.entries)
          entry.key: List.unmodifiable(entry.value),
      }),
      variationsByBaseName: Map.unmodifiable({
        for (final entry in variations.entries)
          entry.key: List.unmodifiable(entry.value),
      }),
    );
  }
}

final _standardEmojiIndex = _StandardEmojiIndex.build();

// Internal Tab Abstraction
abstract class _PickerTab {
  Widget get icon;
  String get name;
}

class _StandardTab extends _PickerTab {
  final Category category;
  _StandardTab(this.category);
  @override
  Widget get icon => Icon(category.icon, size: 22);

  @override
  String get name => category.name;
}

class _CustomTab extends _PickerTab {
  final CustomCategory category;
  _CustomTab(this.category);
  @override
  Widget get icon => category.icon;

  @override
  String get name => category.name;
}

class _RecentTab extends _PickerTab {
  _RecentTab();
  @override
  Widget get icon => const Icon(Icons.history, size: 22);

  @override
  String get name => 'Recent';
}

// ==========================================
// 3. Main Widget
// ==========================================

class MatrixEmojiPicker extends StatefulWidget {
  final EmojiSelectionCallback onEmojiSelected;
  final VoidCallback onBackspacePressed;

  /// A list of recent `PickerEmoji` items to show in the "Recent" tab.
  final List<PickerEmoji> recentEmojis;

  final List<CustomCategory> customCategories;

  /// Required to render custom emojis.
  /// [emojiData] is the value from your CustomCategory map.
  final CustomEmojiBuilder? customEmojiBuilder;

  const MatrixEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    required this.onBackspacePressed,
    this.recentEmojis = const [],
    this.customCategories = const [],
    this.customEmojiBuilder,
  });

  @override
  MatrixEmojiPickerState createState() => MatrixEmojiPickerState();
}

class MatrixEmojiPickerState extends State<MatrixEmojiPicker>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();

  List<PickerEmoji> _searchableEmojis = const [];
  List<PickerEmoji> _displayedEmojis = const [];
  Map<String, List<PickerEmoji>> _customByCategoryId = const {};
  Set<String> _customSearchIdentities = const {};

  late List<_PickerTab> _tabs;
  late TabController _tabController;
  int _selectedTabIndex = 0;
  bool _isLoading = true;
  bool _initialLoadStarted = false;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _initTabs();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAfterRouteTransition();
    });
  }

  void _loadAfterRouteTransition() {
    if (!mounted || _initialLoadStarted) return;

    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      _initialLoadStarted = true;
      _loadEmojis();
      return;
    }

    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _routeAnimation = animation;
    _routeAnimation?.addStatusListener(_handleRouteAnimationStatus);
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;

    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _routeAnimation = null;
    if (!mounted || _initialLoadStarted) return;

    _initialLoadStarted = true;
    _loadEmojis();
  }

  void _initTabs() {
    _tabs = [
      _RecentTab(),
      ...Category.values.map((c) => _StandardTab(c)),
      ...widget.customCategories.map((c) => _CustomTab(c)),
    ];

    // Reset index if out of bounds (e.g. if categories removed)
    if (_selectedTabIndex >= _tabs.length) {
      _selectedTabIndex = 0;
    }

    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: _selectedTabIndex,
    );
  }

  @override
  void didUpdateWidget(MatrixEmojiPicker oldWidget) {
    super.didUpdateWidget(oldWidget);

    final customCategoriesChanged =
        widget.customCategories != oldWidget.customCategories;
    if (customCategoriesChanged) {
      _tabController.dispose();
      _initTabs();
      if (_initialLoadStarted) _loadEmojis();
      return;
    }

    // Recent changes do not invalidate the expensive standard/custom indexes.
    // Only recalculate the current result set when it can affect the screen.
    if (widget.recentEmojis != oldWidget.recentEmojis &&
        _initialLoadStarted) {
      setState(_calculateDisplayedEmojis);
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadEmojis() {
    // Accessing the lazily initialized standard index is the only standard-data
    // work here. After the first picker instance, this is just a cached lookup.
    final standardIndex = _standardEmojiIndex;
    final custom = <PickerEmoji>[];
    final customByCategoryId = <String, List<PickerEmoji>>{};

    for (final category in widget.customCategories) {
      final categoryEmojis = <PickerEmoji>[];
      for (final entry in category.emojis.entries) {
        final emoji = PickerEmoji.custom(
          name: entry.key,
          customData: entry.value,
          categoryId: category.id,
        );
        categoryEmojis.add(emoji);
        custom.add(emoji);
      }
      customByCategoryId[category.id] = List.unmodifiable(categoryEmojis);
    }

    final searchable = custom.isEmpty
        ? standardIndex.all
        : List<PickerEmoji>.unmodifiable([...standardIndex.all, ...custom]);
    final customIdentities = custom.isEmpty
        ? const <String>{}
        : Set<String>.unmodifiable(custom.map((emoji) => emoji.searchIdentity));

    if (!mounted) return;
    setState(() {
      _customByCategoryId = Map.unmodifiable(customByCategoryId);
      _customSearchIdentities = customIdentities;
      _searchableEmojis = searchable;
      _isLoading = false;
      _calculateDisplayedEmojis();
    });
  }

  // Pure logic function to filter emojis based on current state
  void _calculateDisplayedEmojis() {
    final searchText = _searchController.text.trim().toLowerCase();
    final currentTab = _tabs[_selectedTabIndex];

    if (searchText.isNotEmpty) {
      final results = <PickerEmoji>[];

      for (final emoji in _searchableEmojis) {
        if (!emoji.isSkinToneVariation &&
            emoji.searchText.contains(searchText)) {
          results.add(emoji);
        }
      }

      // Every standard recent already exists in the process-wide standard
      // index. For custom recent values, only add entries not present in the
      // currently loaded custom packs. This avoids rebuilding/copying a full
      // identity set on every search keystroke.
      for (final recent in widget.recentEmojis) {
        final alreadyIndexed = recent.type == PickerEmojiType.standard ||
            _customSearchIdentities.contains(recent.searchIdentity);
        if (!alreadyIndexed &&
            !recent.isSkinToneVariation &&
            recent.searchText.contains(searchText)) {
          results.add(recent);
        }
      }

      _displayedEmojis = List.unmodifiable(results);
      return;
    }

    if (currentTab is _StandardTab) {
      // O(1) category lookup instead of filtering the full emoji table on every
      // tab switch.
      _displayedEmojis =
          _standardEmojiIndex.byCategory[currentTab.category] ?? const [];
    } else if (currentTab is _CustomTab) {
      _displayedEmojis =
          _customByCategoryId[currentTab.category.id] ?? const [];
    } else if (currentTab is _RecentTab) {
      _displayedEmojis = widget.recentEmojis;
    }
  }

  void _onTabTapped(int index) {
    setState(() {
      _selectedTabIndex = index;
      _searchController.clear(); // Clear search to show category contents
      _calculateDisplayedEmojis();
    });
  }

  void _onSearchChanged() {
    setState(() {
      _calculateDisplayedEmojis();
    });
  }

  // ... _handleEmojiTap and _showSkinToneMenu remain the same ...
  void _handleEmojiTap(PickerEmoji emoji) {
    Category? cat;
    if (emoji.type == PickerEmojiType.standard) {
      cat = Category.fromEmojiGroup(emoji.standardEmoji!.emojiGroup);
    }
    widget.onEmojiSelected(cat, emoji);
  }

  void _showSkinToneMenu(
    BuildContext context,
    PickerEmoji baseEmoji,
    Offset globalPosition,
  ) {
    if (baseEmoji.type != PickerEmojiType.standard) return;
    var lookupName = baseEmoji.standardEmoji!.name;
    if (lookupName.contains(':')) {
      lookupName = lookupName.split(':')[0].trim();
    }
    final variations = _standardEmojiIndex.variationsByBaseName[lookupName];
    if (variations == null || variations.isEmpty) return;

    // ... Menu showing logic same as before ...
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition - const Offset(0, 50), globalPosition),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: Theme.of(context).cardColor,
      items: [
        PopupMenuItem(
          enabled: true,
          padding: .zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: variations.map((v) {
                  return InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _handleEmojiTap(v);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: AnimatedEmojiText(
                        v.displayName,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // --- Search Bar ---
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => _onSearchChanged(), // Updated handler
                    decoration: InputDecoration(
                      hintText: L10n.of(context).search,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: widget.onBackspacePressed,
                icon: const Icon(Icons.backspace_outlined),
                color: Colors.grey[700],
              ),
            ],
          ),
        ),

        // --- Category Tab Bar ---
        Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: theme.colorScheme.secondary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: theme.colorScheme.secondary,
            padding: .zero,
            tabAlignment: .start,
            onTap: _onTabTapped,
            tabs: _tabs.map((tab) {
              return Tooltip(
                message: tab.name,
                child: Tab(icon: tab.icon),
              );
            }).toList(),
          ),
        ),

        // --- Grid Area ---
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _displayedEmojis.isEmpty
              ? Center(child: Text(L10n.of(context).nothingFound))
              : CustomScrollView(
                  // Add a Key based on tab index to force scroll position reset on tab switch
                  key: ValueKey(_selectedTabIndex),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(6.0),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 8,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                              childAspectRatio: 1.0,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return _buildEmojiTile(_displayedEmojis[index]);
                        }, childCount: _displayedEmojis.length),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildEmojiTile(PickerEmoji emoji) {
    Widget content;
    if (emoji.type == PickerEmojiType.custom) {
      if (widget.customEmojiBuilder != null && emoji.customData != null) {
        content = widget.customEmojiBuilder!(context, emoji.customData!, 28);
      } else {
        content = const Icon(Icons.error_outline, size: 20);
      }
    } else {
      content = AnimatedEmojiText(
        emoji.displayName,
        style: const TextStyle(fontSize: 28),
      );
    }

    final hasVariations =
        emoji.type == PickerEmojiType.standard &&
        _standardEmojiIndex.variationsByBaseName.containsKey(
          emoji.standardEmoji!.name,
        );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _handleEmojiTap(emoji),
        onLongPress: hasVariations ? () {} : null,
        child: GestureDetector(
          onLongPressStart: (details) {
            if (hasVariations) {
              _showSkinToneMenu(context, emoji, details.globalPosition);
            }
          },
          child: Stack(
            children: [
              Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: content),
              ),
              if (hasVariations)
                Positioned(
                  bottom: 2,
                  right: 2,
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
}
