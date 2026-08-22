import 'dart:async';

import 'package:flutter/services.dart';

import 'package:extera_next/config/unicode_fallback_fonts.dart';

bool _unicodeFallbackFontsLoaded = false;

/// Registers the bundled Unicode Font Set families with the engine at
/// runtime. These fonts are intentionally NOT declared under `fonts:` in
/// pubspec.yaml: the web/wasm engine fetches every FontManifest entry during
/// startup, which would download all ~95MB of chunks even when the fallback
/// is disabled. Declared as plain assets instead, they are only fetched here.
///
/// Call when [AppSettings.unicode18Fallback] is enabled — on app start or
/// when the user flips the toggle. Text reflows automatically as each family
/// becomes available.
Future<void> loadUnicodeFallbackFonts() async {
  if (_unicodeFallbackFontsLoaded) return;
  _unicodeFallbackFontsLoaded = true;
  await Future.wait([
    for (final (family, asset) in kUnicodeFallbackFontAssets)
      () async {
        final loader = FontLoader(family)..addFont(rootBundle.load(asset));
        await loader.load();
      }(),
  ]);
}
