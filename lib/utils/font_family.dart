const _systemFontFamily = 'SystemFont';
const _notoEmojiFontFamily = 'Noto Color Emoji';

String? resolveFontFamily({
  required bool useSystemFont,
  required String configuredFont,
}) {
  if (useSystemFont) return _systemFontFamily;
  final font = configuredFont.trim();
  return font.isEmpty ? null : font;
}

List<String>? resolveFontFallbacks({
  required String configuredFallbacks,
  String? primaryFont,
  bool includeNotoEmoji = false,
}) {
  final fallbacks = <String>[];

  void add(String family) {
    final normalized = family.trim();
    if (normalized.isEmpty ||
        normalized == primaryFont ||
        fallbacks.contains(normalized)) {
      return;
    }
    fallbacks.add(normalized);
  }

  if (includeNotoEmoji) add(_notoEmojiFontFamily);
  for (final family in configuredFallbacks.split(',')) {
    add(family);
  }

  return fallbacks.isEmpty ? null : fallbacks;
}
