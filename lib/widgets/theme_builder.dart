import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/utils/color_value.dart';

class ThemeBuilder extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    ThemeMode themeMode,
    Color? primaryColor,
    DynamicSchemeVariant schemeVariant,
    bool pureBlack,
    bool notoEmoji,
    bool unicodeFallback,
  )
  builder;

  final String themeModeSettingsKey;
  final String primaryColorSettingsKey;
  final String pureBlackSettingsKey;
  final String notoEmojiSettingsKey;
  final String unicodeFallbackSettingsKey;
  final String schemeVariantSettingsKey;

  const ThemeBuilder({
    required this.builder,
    this.themeModeSettingsKey = 'xyz.extera.next.themeMode',
    this.primaryColorSettingsKey = 'xyz.extera.next.colorSchemeSeed',
    this.pureBlackSettingsKey = 'xyz.extera.next.pureBlack',
    this.notoEmojiSettingsKey = 'xyz.extera.next.notoEmojiFont',
    this.unicodeFallbackSettingsKey = 'xyz.extera.next.unicode18Fallback',
    this.schemeVariantSettingsKey = 'xyz.extera.next.schemeVariant',
    super.key,
  });

  @override
  State<ThemeBuilder> createState() => ThemeController();
}

class ThemeController extends State<ThemeBuilder> {
  SharedPreferences? _sharedPreferences;
  ThemeMode? _themeMode;
  Color? _primaryColor;
  bool? _pureBlack;
  bool? _notoEmoji;
  bool? _unicodeFallback;
  DynamicSchemeVariant? _variant;

  ThemeMode get themeMode => _themeMode ?? ThemeMode.system;

  Color? get primaryColor => _primaryColor;

  bool get pureBlack => _pureBlack ?? false;

  bool get notoEmoji => _notoEmoji ?? false;

  // Stay disabled until the persisted preference has been read. This avoids a
  // one-frame font probe for users who explicitly turned fallback off.
  bool get unicodeFallback => _unicodeFallback ?? false;

  DynamicSchemeVariant get variant =>
      _variant ?? DynamicSchemeVariant.tonalSpot;

  static ThemeController of(BuildContext context) =>
      Provider.of<ThemeController>(context, listen: false);

  void _loadData(_) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();

    final rawThemeMode = preferences.getString(widget.themeModeSettingsKey);
    final rawColor = preferences.getInt(widget.primaryColorSettingsKey);
    final rawPureBlack = preferences.getBool(widget.pureBlackSettingsKey);
    final rawNotoEmoji =
        preferences.getBool(widget.notoEmojiSettingsKey) ??
        preferences.getBool('xyz.extera.next.twemojiFont');
    final rawUnicodeFallback =
        preferences.getBool(widget.unicodeFallbackSettingsKey) ?? true;
    final rawVariant =
        preferences.getInt(widget.schemeVariantSettingsKey) ??
        DynamicSchemeVariant.values.indexOf(.tonalSpot);

    if (!mounted) return;
    setState(() {
      _themeMode = ThemeMode.values.singleWhereOrNull(
        (value) => value.name == rawThemeMode,
      );
      _primaryColor = rawColor == null ? null : Color(rawColor);
      _pureBlack = rawPureBlack;
      _notoEmoji = rawNotoEmoji;
      _unicodeFallback = rawUnicodeFallback;
      _variant = .values[rawVariant];
    });
  }

  Future<void> setThemeMode(ThemeMode newThemeMode) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setString(widget.themeModeSettingsKey, newThemeMode.name);
    if (!mounted) return;
    setState(() {
      _themeMode = newThemeMode;
    });
  }

  Future<void> setPrimaryColor(Color? newPrimaryColor) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    if (newPrimaryColor == null) {
      await preferences.remove(widget.primaryColorSettingsKey);
    } else {
      await preferences.setInt(
        widget.primaryColorSettingsKey,
        newPrimaryColor.hexValue,
      );
    }
    if (!mounted) return;
    setState(() {
      _primaryColor = newPrimaryColor;
    });
  }

  Future<void> setSchemeVariant(DynamicSchemeVariant? newVariant) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    if (newVariant == null) {
      await preferences.remove(widget.schemeVariantSettingsKey);
    } else {
      await preferences.setInt(
        widget.schemeVariantSettingsKey,
        DynamicSchemeVariant.values.indexOf(newVariant),
      );
    }
    if (!mounted) return;
    setState(() {
      _variant = newVariant;
    });
  }

  Future<void> setPureBlack(bool newPureBlack) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setBool(widget.pureBlackSettingsKey, newPureBlack);
    if (!mounted) return;
    setState(() {
      _pureBlack = newPureBlack;
    });
  }

  Future<void> setNotoEmoji(bool newNotoEmoji) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setBool(widget.notoEmojiSettingsKey, newNotoEmoji);
    await preferences.remove('xyz.extera.next.twemojiFont');
    refreshTypography(notoEmoji: newNotoEmoji);
  }

  /// Forces MaterialApp to rebuild its ThemeData after font settings change.
  ///
  /// Font preferences live outside ThemeController, so rebuilding only the
  /// settings page leaves existing routes with the old TextTheme until another
  /// theme change happens. Keeping the refresh here makes UI, chat and overlay
  /// routes switch typography in the same frame.
  void refreshTypography({bool? notoEmoji}) {
    if (!mounted) return;
    setState(() {
      if (notoEmoji != null) _notoEmoji = notoEmoji;
    });
  }

  Future<void> setUnicodeFallback(bool enabled) async {
    final preferences = _sharedPreferences ??=
        await SharedPreferences.getInstance();
    await preferences.setBool(widget.unicodeFallbackSettingsKey, enabled);
    if (!mounted) return;
    setState(() {
      _unicodeFallback = enabled;
    });
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback(_loadData);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Provider(
      create: (_) => this,
      child: DynamicColorBuilder(
        builder: (light, _) => widget.builder(
          context,
          themeMode,
          primaryColor ?? light?.primary,
          variant,
          pureBlack,
          notoEmoji,
          unicodeFallback,
        ),
      ),
    );
  }
}
