import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

/// Noto Color Emoji ships as a plain 10.7 MB asset. It used to be declared
/// under `flutter.fonts`, so FontManifest.json listed it and the Web engine
/// preloaded the whole file at startup for every user — even with the
/// emoji-fallback setting disabled (the default). This loader registers the
/// family on demand instead, mirroring lib/utils/katex_fonts.dart.
const String _fontFamily = 'Noto Color Emoji';
const String _fontAsset = 'assets/font/NotoColorEmoji.ttf';
const String _manifestFamily = '"$_fontFamily"';

Future<void>? _loaded;

/// Registers the emoji family on first call; later calls reuse the same
/// future. Never throws: if registration fails text still renders with
/// fallback fonts instead of crashing the app.
Future<void> ensureNotoEmojiFontLoaded() => _loaded ??= _load();

Future<void> _load() async {
  try {
    if (await _registeredByEngine()) return;
    final loader = FontLoader(_fontFamily);
    loader.addFont(rootBundle.load(_fontAsset));
    await loader.load();
  } catch (e, s) {
    Logs().d('Failed to load Noto Color Emoji font', e, s);
  }
}

/// Builds that kept the pubspec declaration (debug sessions, CI compile
/// checks) register the font through FontManifest.json already; loading
/// it again would add the typeface to its family a second time.
Future<bool> _registeredByEngine() async {
  try {
    final manifest = await rootBundle.loadString('FontManifest.json');
    return manifest.contains(_manifestFamily);
  } catch (_) {
    return false;
  }
}
