import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

/// KaTeX font families bundled by flutter_math_fork, mapped to the TTF files
/// that make up each family.
///
/// The package declares these under `flutter.fonts`, so a plain build lists
/// them in FontManifest.json and the engine loads all of them at startup.
/// The release pipeline strips those entries
/// (scripts/strip-katex-manifest.py); this loader registers the same
/// families on demand when the first LaTeX span renders instead.
const Map<String, List<String>> _kaTeXFontFiles = {
  'KaTeX_Main': [
    'KaTeX_Main-Regular.ttf',
    'KaTeX_Main-Italic.ttf',
    'KaTeX_Main-Bold.ttf',
    'KaTeX_Main-BoldItalic.ttf',
  ],
  'KaTeX_Math': [
    'KaTeX_Math-Italic.ttf',
    'KaTeX_Math-BoldItalic.ttf',
  ],
  'KaTeX_AMS': [
    'KaTeX_AMS-Regular.ttf',
  ],
  'KaTeX_Caligraphic': [
    'KaTeX_Caligraphic-Regular.ttf',
    'KaTeX_Caligraphic-Bold.ttf',
  ],
  'KaTeX_Fraktur': [
    'KaTeX_Fraktur-Regular.ttf',
    'KaTeX_Fraktur-Bold.ttf',
  ],
  'KaTeX_SansSerif': [
    'KaTeX_SansSerif-Regular.ttf',
    'KaTeX_SansSerif-Bold.ttf',
    'KaTeX_SansSerif-Italic.ttf',
  ],
  'KaTeX_Script': [
    'KaTeX_Script-Regular.ttf',
  ],
  'KaTeX_Typewriter': [
    'KaTeX_Typewriter-Regular.ttf',
  ],
  'KaTeX_Size1': [
    'KaTeX_Size1-Regular.ttf',
  ],
  'KaTeX_Size2': [
    'KaTeX_Size2-Regular.ttf',
  ],
  'KaTeX_Size3': [
    'KaTeX_Size3-Regular.ttf',
  ],
  'KaTeX_Size4': [
    'KaTeX_Size4-Regular.ttf',
  ],
};

const String _fontAssetBase =
    'packages/flutter_math_fork/lib/katex_fonts/fonts';

/// Family prefix as it appears in FontManifest.json entries.
const String _manifestFamilyPrefix = '"packages/flutter_math_fork/KaTeX_';

Future<void>? _loaded;

/// Registers every KaTeX family on first call; later calls reuse the same
/// future. Never throws: if registration fails the math still renders with
/// fallback fonts instead of crashing the message list.
Future<void> ensureKaTeXFontsLoaded() => _loaded ??= _load();

Future<void> _load() async {
  try {
    if (await _registeredByEngine()) return;
    await Future.wait(_kaTeXFontFiles.entries.map(_registerFamily));
  } catch (e, s) {
    Logs().d('Failed to load KaTeX fonts', e, s);
  }
}

/// Builds that did not run the strip script (debug sessions, CI compile
/// checks) register the fonts through FontManifest.json already; loading
/// them again would add every typeface to its family a second time.
Future<bool> _registeredByEngine() async {
  try {
    final manifest = await rootBundle.loadString('FontManifest.json');
    return manifest.contains(_manifestFamilyPrefix);
  } catch (_) {
    return false;
  }
}

Future<void> _registerFamily(MapEntry<String, List<String>> family) async {
  final loader = FontLoader(family.key);
  for (final file in family.value) {
    loader.addFont(rootBundle.load('$_fontAssetBase/$file'));
  }
  await loader.load();
}
