import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:android_system_font/android_system_font.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/config/routes.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/download_manager/download_manager.dart';
import 'package:extera_next/widgets/app_lock.dart';
import 'package:extera_next/widgets/background_audio_player.dart';
import 'package:extera_next/widgets/theme_builder.dart';
import 'package:extera_next/widgets/unicode_font_fallback_scope.dart';
import '../config/app_config.dart';
import '../utils/custom_scroll_behaviour.dart';
import '../utils/platform_infos.dart';
import 'matrix.dart';

class FluffyChatApp extends StatefulWidget {
  final Widget? testWidget;
  final List<Client> clients;
  final String? pincode;
  final SharedPreferences store;

  const FluffyChatApp({
    super.key,
    this.testWidget,
    required this.clients,
    required this.store,
    this.pincode,
  });

  /// getInitialLink may rereturn the value multiple times if this view is
  /// opened multiple times for example if the user logs out after they logged
  /// in with qr code or magic link.
  static bool gotInitialLink = false;

  // Router must be outside of build method so that hot reload does not reset
  // the current path.
  static final GoRouter router = GoRouter(
    routes: AppRoutes.routes,
    debugLogDiagnostics: true,
  );

  @override
  State<FluffyChatApp> createState() => _FluffyChatAppState();
}

class _FluffyChatAppState extends State<FluffyChatApp> {
  final _androidSystemFontPlugin = AndroidSystemFont();

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  static Future<ByteData> _readFileBytes(String path) async {
    final bytes = await File(path).readAsBytes();
    return ByteData.view(bytes.buffer);
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    // android_system_font only registers a native Android implementation.
    // Calling it on the web falls back to a MethodChannel and produces a
    // MissingPluginException during the first frame.
    if (!PlatformInfos.isAndroid) return;

    try {
      final fontFilePath = await _androidSystemFontPlugin.getFilePath();
      if (!mounted || fontFilePath == null || fontFilePath.isEmpty) return;

      final fontLoader = FontLoader('SystemFont');
      fontLoader.addFont(_readFileBytes(fontFilePath));
      await fontLoader.load();

      // ThemeData may already have been built while SystemFont was still
      // unavailable, causing Flutter to render the whole UI with a fallback
      // font. Rebuild after registration so every SystemFont user resolves to
      // the actual Android system font instead of keeping the first-frame
      // fallback for the lifetime of the app.
      if (mounted) setState(() {});
    } on PlatformException {
      // The system font is optional; keep the app usable if Android does not
      // expose a readable font path.
    } on MissingPluginException {
      // The system font is optional; keep the app usable if the plugin was not
      // registered by the Android embedding.
    } on FileSystemException {
      // The system font is optional; keep the app usable if the path becomes
      // unavailable while the font is loading.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeBuilder(
      builder:
          (
            context,
            themeMode,
            primaryColor,
            schemeVariant,
            pureBlack,
            notoEmoji,
            unicodeFallback,
          ) => MaterialApp.router(
            title: AppConfig.applicationName,
            themeMode: themeMode,
            theme: FluffyThemes.buildTheme(
              context,
              Brightness.light,
              primaryColor,
              schemeVariant,
              pureBlack,
              notoEmoji,
            ),
            darkTheme: FluffyThemes.buildTheme(
              context,
              Brightness.dark,
              primaryColor,
              schemeVariant,
              pureBlack,
              notoEmoji,
            ),
            scrollBehavior: CustomScrollBehavior(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            routerConfig: FluffyChatApp.router,
            builder: (context, child) => UnicodeFontFallbackScope(
              enabled: unicodeFallback,
              child: AppLockWidget(
                pincode: widget.pincode,
                clients: widget.clients,
                // Need a navigator above the Matrix widget for
                // displaying dialogs
                child: DownloadManager(
                  child: BackgroundAudioPlayer(
                    child: Matrix(
                      clients: widget.clients,
                      store: widget.store,
                      child: widget.testWidget ?? child,
                    ),
                  ),
                ),
              ),
            ),
          ),
    );
  }
}
