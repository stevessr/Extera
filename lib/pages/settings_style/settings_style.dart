import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:native_imaging/native_imaging.dart' as native;
import 'package:path_provider/path_provider.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/events/message.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/file_selector.dart';
import 'package:extera_next/utils/wallpaper.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_list_choose_dialog.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/theme_builder.dart';
import 'settings_style_view.dart';

int get _wallpaperMaxDimension => wallpaperMaxDimension;
int get _wallpaperJpegQuality => wallpaperJpegQuality;

Future<Uint8List> _compressWallpaperBytes(Uint8List rawBytes) async {
  try {
    await native.init();

    final codec = await instantiateImageCodec(rawBytes);
    final frame = await codec.getNextFrame();
    final rgbaData = await frame.image.toByteData();
    if (rgbaData == null) return rawBytes;

    final rgba = Uint8List.view(
      rgbaData.buffer,
      rgbaData.offsetInBytes,
      rgbaData.lengthInBytes,
    );

    final width = frame.image.width;
    final height = frame.image.height;

    frame.image.dispose();
    codec.dispose();

    var nativeImg = native.Image.fromRGBA(width, height, rgba);

    // Scale down if either dimension exceeds the limit.
    if (width > _wallpaperMaxDimension || height > _wallpaperMaxDimension) {
      final fit = applyBoxFit(
        BoxFit.scaleDown,
        Size(width.toDouble(), height.toDouble()),
        Size(
          _wallpaperMaxDimension.toDouble(),
          _wallpaperMaxDimension.toDouble(),
        ),
      ).destination;
      final newW = fit.width.round();
      final newH = fit.height.round();

      final scaled = nativeImg.resample(newW, newH, native.Transform.lanczos);
      nativeImg.free();
      nativeImg = scaled;
    }

    final compressed = await nativeImg.toJpeg(_wallpaperJpegQuality);
    nativeImg.free();
    return compressed;
  } catch (e, s) {
    Logs().e('Failed to compress wallpaper image', e, s);
    return rawBytes;
  }
}

class SettingsStyle extends StatefulWidget {
  const SettingsStyle({super.key});

  @override
  SettingsStyleController createState() => SettingsStyleController();
}

class SettingsStyleController extends State<SettingsStyle> {
  void setChatColor(Color? color) async {
    ThemeController.of(context).setPrimaryColor(color);
  }

  String? _wallpaperPath;
  String? get wallpaperPath => _wallpaperPath;

  @override
  void initState() {
    super.initState();
    _loadWallpaperConfig();
    _loadMessageStyleSetting();
  }

  void _loadMessageStyleSetting() {
    _messageStyle = switch (AppSettings.messageStyle.value) {
      'bubbles' => .bubbles,
      'bubbles_legacy' => .bubblesLegacy,
      'modern' => .modern,
      _ => .bubbles,
    };
  }

  Future<void> _loadWallpaperConfig() async {
    final path = AppSettings.wallpaperPath.value;
    setState(() {
      _wallpaperPath = path.isEmpty ? null : path;
      _wallpaperOpacity = AppSettings.wallpaperOpacity.value;
      _wallpaperBlur = AppSettings.wallpaperBlur.value;
    });
  }

  void setWallpaper() async {
    final picked = await selectFiles(context, type: FileType.image);
    final pickedFile = picked.firstOrNull;
    if (pickedFile == null) return;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        // Read the original file bytes.
        final rawBytes = await pickedFile.readAsBytes();
        // Compress and resize the image before saving.
        final compressedBytes = await _compressWallpaperBytes(rawBytes);

        // Web has no writable file system: keep the wallpaper in IndexedDB
        // instead of pointing at a file on disk.
        if (kIsWeb) {
          final marker = await setWebWallpaperBytes(compressedBytes);
          await AppSettings.wallpaperPath.setItem(marker);
          setState(() {
            _wallpaperPath = marker;
          });
          return;
        }

        final dir = await getApplicationDocumentsDirectory();
        final fileName =
            'wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg'; // always store as JPEG
        final fullPath = '${dir.path}/$fileName';
        final file = File(fullPath);
        await file.writeAsBytes(compressedBytes);
        await AppSettings.wallpaperPath.setItem(fullPath);
        setState(() {
          _wallpaperPath = fullPath;
        });
      },
    );
  }

  double get wallpaperOpacity => _wallpaperOpacity ?? 0.5;

  double? _wallpaperOpacity;

  void setSchemeVariant() async {
    final theme = Theme.of(context);
    final paletteNames = {
      DynamicSchemeVariant.tonalSpot: L10n.of(context).palette_tonalSpot,
      DynamicSchemeVariant.fidelity: L10n.of(context).palette_fidelity,
      DynamicSchemeVariant.monochrome: L10n.of(context).palette_monochrome,
      DynamicSchemeVariant.neutral: L10n.of(context).palette_neutral,
      DynamicSchemeVariant.vibrant: L10n.of(context).palette_vibrant,
      DynamicSchemeVariant.expressive: L10n.of(context).palette_expressive,
      DynamicSchemeVariant.content: L10n.of(context).palette_content,
      DynamicSchemeVariant.rainbow: L10n.of(context).palette_rainbow,
      DynamicSchemeVariant.fruitSalad: L10n.of(context).palette_fruitSalad,
    };

    await showAdaptiveBottomSheet(
      context: context,
      builder: (context) {
        return Scaffold(
          appBar: AppBar(title: Text(L10n.of(context).colorPalette)),
          body: Padding(
            padding: const .all(8),
            child: Material(
              color: theme.colorScheme.surfaceContainerHigh,
              clipBehavior: .hardEdge,
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                children: [
                  for (final value in DynamicSchemeVariant.values)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: Icon(
                          Icons.palette_outlined,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(paletteNames[value]!),
                      selected: ThemeController.of(context).variant == value,
                      trailing: ThemeController.of(context).variant == value
                          ? const Icon(Icons.check_circle)
                          : null,
                      onTap: () {
                        ThemeController.of(context).setSchemeVariant(value);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void saveWallpaperOpacity(double opacity) async {
    await AppSettings.wallpaperOpacity.setItem(opacity);
    setState(() {
      _wallpaperOpacity = opacity;
    });
  }

  void updateWallpaperOpacity(double opacity) {
    setState(() {
      _wallpaperOpacity = opacity;
    });
  }

  double get wallpaperBlur => _wallpaperBlur ?? 0.0;
  double? _wallpaperBlur;

  void saveWallpaperBlur(double blur) async {
    await AppSettings.wallpaperBlur.setItem(blur);
    setState(() {
      _wallpaperBlur = blur;
    });
  }

  void updateWallpaperBlur(double blur) {
    setState(() {
      _wallpaperBlur = blur;
    });
  }

  void deleteChatWallpaper() async {
    final currentPath = _wallpaperPath;
    if (kIsWeb) {
      await clearWebWallpaperBytes();
    } else if (currentPath != null && !currentPath.startsWith('data:')) {
      // Delete the local wallpaper file if it exists.
      try {
        final file = File(currentPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    await AppSettings.wallpaperPath.setItem('');
    await AppSettings.wallpaperOpacity.setItem(0.5);
    await AppSettings.wallpaperBlur.setItem(0.0);
    setState(() {
      _wallpaperPath = null;
      _wallpaperOpacity = 0.5;
      _wallpaperBlur = 0.0;
    });
  }

  ThemeMode get currentTheme => ThemeController.of(context).themeMode;
  Color? get currentColor => ThemeController.of(context).primaryColor;

  void switchTheme(ThemeMode? newTheme) {
    if (newTheme == null) return;
    switch (newTheme) {
      case ThemeMode.light:
        ThemeController.of(context).setThemeMode(ThemeMode.light);
        break;
      case ThemeMode.dark:
        ThemeController.of(context).setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.system:
        ThemeController.of(context).setThemeMode(ThemeMode.system);
        break;
    }
    setState(() {});
  }

  void changeFontSizeFactor(double d) {
    AppSettings.fontSizeFactor.setItem(d);
    setState(() {});
  }

  void changeAvatarBorderRadius(double d) {
    AppSettings.avatarBorderRadius.setItem(d);
    setState(() {});
  }

  void changeStickerScale(double d) {
    AppSettings.stickerScale.setItem(d);
    setState(() {});
  }

  MessageLayout _messageStyle = .bubbles;
  MessageLayout get messageStyle => _messageStyle;

  void setMessageStyle(MessageLayout value) {
    setState(() {
      AppSettings.messageStyle.setItem(switch (value) {
        .bubbles => 'bubbles',
        .bubblesLegacy => 'bubbles_legacy',
        .modern => 'modern',
      });
      _messageStyle = value;
    });
  }

  bool get showSeconds => AppSettings.showSeconds.value;

  void toggleShowSeconds(bool value) {
    AppSettings.showSeconds.setItem(value);
    setState(() {});
  }

  void editUIFont() async {
    final newFont = await showTextInputDialog(
      context: context,
      title: L10n.of(context).uiFont,
      maxLines: 1,
      initialText: AppSettings.uiFont.value,
    );
    if (newFont == null) return;
    AppSettings.uiFont.setItem(newFont);
    setState(() {});
  }

  void editMonospaceFont() async {
    final newFont = await showTextInputDialog(
      context: context,
      title: L10n.of(context).monospaceFont,
      maxLines: 1,
      initialText: AppSettings.monospaceFont.value,
    );
    if (newFont == null) return;
    AppSettings.monospaceFont.setItem(newFont);
    setState(() {});
  }

  void editChatFont() async {
    final newFont = await showTextInputDialog(
      context: context,
      title: L10n.of(context).chatFont,
      maxLines: 1,
      initialText: AppSettings.chatFont.value,
    );
    if (newFont == null) return;
    AppSettings.chatFont.setItem(newFont);
    setState(() {});
  }

  void editUIFallbackFonts() async {
    final newFonts = await showListChooseDialog(
      context: context,
      title: L10n.of(context).uiFontFallback,
      initialItems: AppSettings.fallbackFonts.value.split(','),
    );
    if (newFonts == null) return;
    AppSettings.fallbackFonts.setItem(newFonts.join(','));
    setState(() {});
  }

  void editMonospaceFallbackFonts() async {
    final newFonts = await showListChooseDialog(
      context: context,
      title: L10n.of(context).monospaceFontFallback,
      initialItems: AppSettings.monospaceFallbackFonts.value.split(','),
    );
    if (newFonts == null) return;
    AppSettings.monospaceFallbackFonts.setItem(newFonts.join(','));
    setState(() {});
  }

  void editChatFallbackFonts() async {
    final newFonts = await showListChooseDialog(
      context: context,
      title: L10n.of(context).chatFontFallback,
      initialItems: AppSettings.chatFallbackFonts.value.split(','),
    );
    if (newFonts == null) return;
    AppSettings.chatFallbackFonts.setItem(newFonts.join(','));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsStyleView(this);
}
