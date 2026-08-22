import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:extera_next/config/unicode_fallback_fonts.dart';

/// Finds code points that the engine's current platform fallback cannot draw.
abstract interface class UnicodeGlyphCoverageProbe {
  Future<Set<int>> missingCodePoints(Set<int> codePoints);
}

typedef UnicodeFontAssetLoader =
    Future<void> Function(UnicodeFallbackFontAsset asset);

final List<(int, int, int)> _unicodeFallbackFontRangeIndex =
    _decodeUnicodeFallbackFontRangeIndex();

List<(int, int, int)> _decodeUnicodeFallbackFontRangeIndex() {
  final bytes = base64Decode(kUnicodeFallbackFontRangeIndexBase64);
  final ranges = <(int, int, int)>[];
  var cursor = 0;
  var previousEnd = -1;

  int readVarint() {
    var value = 0;
    var shift = 0;
    while (cursor < bytes.length) {
      final byte = bytes[cursor++];
      value |= (byte & 0x7F) << shift;
      if ((byte & 0x80) == 0) return value;
      shift += 7;
      if (shift > 28) throw const FormatException('Invalid font range index');
    }
    throw const FormatException('Truncated font range index');
  }

  while (cursor < bytes.length) {
    final start = previousEnd + 1 + readVarint();
    final end = start + readVarint();
    final assetIndex = readVarint();
    ranges.add((start, end, assetIndex));
    previousEnd = end;
  }
  return ranges;
}

@visibleForTesting
List<(int, int, int)> get debugUnicodeFallbackFontRangeIndex =>
    _unicodeFallbackFontRangeIndex;

/// Looks up the tree-shaken asset containing [codePoint] without touching the
/// asset bundle. The generated ranges are sorted and do not overlap.
@visibleForTesting
int? unicodeFallbackAssetIndexForCodePoint(int codePoint) {
  final ranges = _unicodeFallbackFontRangeIndex;
  var low = 0;
  var high = ranges.length - 1;
  while (low <= high) {
    final middle = low + ((high - low) >> 1);
    final range = ranges[middle];
    if (codePoint < range.$1) {
      high = middle - 1;
    } else if (codePoint > range.$2) {
      low = middle + 1;
    } else {
      return range.$3;
    }
  }
  return null;
}

/// Loads Unicode Font Set chunks only after both of these conditions hold:
///
///  * a code point is present in visible text; and
///  * the running engine/platform renders that code point as its missing-glyph
///    sentinel.
///
/// Requests arriving in the same frame are batched, system coverage decisions
/// are cached by code point, and each font asset is registered at most once.
class UnicodeFontLoader {
  UnicodeFontLoader({
    UnicodeGlyphCoverageProbe? coverageProbe,
    UnicodeFontAssetLoader? fontAssetLoader,
    this.maxConcurrentLoads = 3,
  }) : assert(maxConcurrentLoads > 0),
       _coverageProbe = coverageProbe ?? CanvasUnicodeGlyphCoverageProbe(),
       _fontAssetLoader = fontAssetLoader ?? _loadBundledFont;

  static final UnicodeFontLoader instance = UnicodeFontLoader();

  final UnicodeGlyphCoverageProbe _coverageProbe;
  final UnicodeFontAssetLoader _fontAssetLoader;
  final int maxConcurrentLoads;

  final Set<int> _queuedCodePoints = <int>{};
  final Map<int, bool> _systemCoverage = <int, bool>{};
  final Set<int> _loadedAssetIndexes = <int>{};
  Future<void>? _drainFuture;

  Future<void> ensureFontsForText(String text) =>
      ensureFontsForCodePoints(text.runes);

  Future<void> ensureFontsForCodePoints(Iterable<int> codePoints) {
    for (final codePoint in codePoints) {
      if (_shouldIgnore(codePoint)) continue;
      final assetIndex = unicodeFallbackAssetIndexForCodePoint(codePoint);
      if (assetIndex == null || _loadedAssetIndexes.contains(assetIndex)) {
        continue;
      }
      _queuedCodePoints.add(codePoint);
    }

    final running = _drainFuture;
    if (_queuedCodePoints.isEmpty) return running ?? Future<void>.value();
    if (running != null) return running;

    final future = _drain();
    _drainFuture = future;
    return future;
  }

  Future<void> _drain() async {
    try {
      while (_queuedCodePoints.isNotEmpty) {
        final batch = Set<int>.of(_queuedCodePoints);
        _queuedCodePoints.clear();
        await _processBatch(batch);
      }
    } finally {
      _drainFuture = null;
    }
  }

  Future<void> _processBatch(Set<int> codePoints) async {
    final unknown = <int>{};
    final missing = <int>{};

    for (final codePoint in codePoints) {
      final assetIndex = unicodeFallbackAssetIndexForCodePoint(codePoint);
      if (assetIndex == null || _loadedAssetIndexes.contains(assetIndex)) {
        continue;
      }
      switch (_systemCoverage[codePoint]) {
        case true:
          break;
        case false:
          missing.add(codePoint);
        case null:
          unknown.add(codePoint);
      }
    }

    if (unknown.isNotEmpty) {
      Set<int> newlyMissing;
      try {
        newlyMissing = await _coverageProbe.missingCodePoints(unknown);
      } catch (error, stackTrace) {
        // A probe failure must not turn real text into tofu. Fall back to
        // loading only the exact chunks requested by this visible batch.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'Unicode font fallback',
            context: ErrorDescription('while probing platform glyph coverage'),
          ),
        );
        newlyMissing = unknown;
      }
      for (final codePoint in unknown) {
        final isMissing = newlyMissing.contains(codePoint);
        _systemCoverage[codePoint] = !isMissing;
        if (isMissing) missing.add(codePoint);
      }
    }

    final assetsToLoad = <int>{
      for (final codePoint in missing)
        if (unicodeFallbackAssetIndexForCodePoint(codePoint)
            case final int assetIndex)
          if (!_loadedAssetIndexes.contains(assetIndex)) assetIndex,
    }.toList()..sort();

    var nextAsset = 0;
    Future<void> worker() async {
      while (nextAsset < assetsToLoad.length) {
        final assetIndex = assetsToLoad[nextAsset++];
        await _loadAsset(assetIndex);
      }
    }

    await Future.wait<void>([
      for (
        var workerIndex = 0;
        workerIndex < maxConcurrentLoads && workerIndex < assetsToLoad.length;
        workerIndex++
      )
        worker(),
    ]);
  }

  Future<void> _loadAsset(int assetIndex) async {
    if (_loadedAssetIndexes.contains(assetIndex)) return;
    final asset = kUnicodeFallbackFontAssets[assetIndex];
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _fontAssetLoader(asset);
        _loadedAssetIndexes.add(assetIndex);
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }

    FlutterError.reportError(
      FlutterErrorDetails(
        exception: lastError!,
        stack: lastStackTrace,
        library: 'Unicode font fallback',
        context: ErrorDescription('while loading ${asset.asset}'),
      ),
    );
  }

  static Future<void> _loadBundledFont(UnicodeFallbackFontAsset asset) async {
    final loader = FontLoader(asset.family)
      ..addFont(rootBundle.load(asset.asset));
    await loader.load();
  }

  static bool _shouldIgnore(int codePoint) {
    // Every Flutter platform font covers printable ASCII. Control, formatting,
    // variation-selector, and tag characters do not require standalone glyphs.
    if (codePoint <= 0x7E) return true;
    if (codePoint >= 0x7F && codePoint <= 0x9F) return true;
    if (codePoint >= 0x200B && codePoint <= 0x200F) return true;
    if (codePoint >= 0x202A && codePoint <= 0x202E) return true;
    if (codePoint >= 0x2060 && codePoint <= 0x206F) return true;
    if (codePoint >= 0xFE00 && codePoint <= 0xFE0F) return true;
    if (codePoint >= 0xFDD0 && codePoint <= 0xFDEF) return true;
    if ((codePoint & 0xFFFF) >= 0xFFFE) return true;
    if (codePoint >= 0xE0000 && codePoint <= 0xE007F) return true;
    if (codePoint >= 0xE0100 && codePoint <= 0xE01EF) return true;
    return false;
  }

  @visibleForTesting
  Set<int> get debugLoadedAssetIndexes =>
      Set<int>.unmodifiable(_loadedAssetIndexes);
}

/// Raster-probes the same engine that paints the app. A genuinely unresolved
/// scalar produces the same .notdef bitmap as a noncharacter sentinel; native
/// platform fallback and already-registered web fallback fonts are therefore
/// honored before a bundled chunk is requested.
class CanvasUnicodeGlyphCoverageProbe implements UnicodeGlyphCoverageProbe {
  static const int _sentinel = 0xFDD0;
  static const String _probeFamily = 'Extera Missing Glyph Probe';
  static const String _probeAsset = 'assets/font/GlyphCoverageProbe.ttf';
  static const int _cellSize = 72;
  static const int _columns = 8;
  static const int _batchSize = _columns * _columns - 1;
  static Future<void>? _probeFontLoad;

  @override
  Future<Set<int>> missingCodePoints(Set<int> codePoints) async {
    await (_probeFontLoad ??= _loadProbeFont());
    final sorted = codePoints.toList()..sort();
    final missing = <int>{};
    for (var offset = 0; offset < sorted.length; offset += _batchSize) {
      final end = (offset + _batchSize).clamp(0, sorted.length);
      final batch = sorted.sublist(offset, end);
      missing.addAll(await _probeBatch(batch));
    }
    return missing;
  }

  Future<Set<int>> _probeBatch(List<int> codePoints) async {
    final probes = <int>[_sentinel, ...codePoints];
    final rows = (probes.length + _columns - 1) ~/ _columns;
    final width = _columns * _cellSize;
    final height = rows * _cellSize;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paragraphs = <ui.Paragraph>[];

    for (var index = 0; index < probes.length; index++) {
      final paragraph = _buildParagraph(probes[index]);
      paragraphs.add(paragraph);
      final column = index % _columns;
      final row = index ~/ _columns;
      final cell = ui.Rect.fromLTWH(
        column * _cellSize.toDouble(),
        row * _cellSize.toDouble(),
        _cellSize.toDouble(),
        _cellSize.toDouble(),
      );
      canvas
        ..save()
        ..clipRect(cell)
        ..drawParagraph(paragraph, cell.topLeft + const ui.Offset(8, 4))
        ..restore();
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      for (final paragraph in paragraphs) {
        paragraph.dispose();
      }
      image.dispose();
      picture.dispose();
      throw StateError('The engine returned no pixels for the glyph probe.');
    }

    final pixels = Uint8List.sublistView(data);
    final sentinelHash = _cellHash(pixels, width, 0);
    final missing = <int>{};
    for (var index = 1; index < probes.length; index++) {
      if (_cellHash(pixels, width, index) == sentinelHash &&
          _cellsEqual(pixels, width, 0, index)) {
        missing.add(probes[index]);
      }
    }

    for (final paragraph in paragraphs) {
      paragraph.dispose();
    }
    image.dispose();
    picture.dispose();
    return missing;
  }

  static ui.Paragraph _buildParagraph(int codePoint) {
    final builder =
        ui.ParagraphBuilder(
          ui.ParagraphStyle(textDirection: ui.TextDirection.ltr),
        )..pushStyle(
          ui.TextStyle(
            color: const ui.Color(0xFF000000),
            fontFamily: _probeFamily,
            fontSize: 48,
          ),
        );
    builder.addText(String.fromCharCode(codePoint));
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: _cellSize - 16));
    return paragraph;
  }

  static Future<void> _loadProbeFont() async {
    // This 1KB font maps only the sentinel. Its sentinel and .notdef outlines
    // are identical, so the comparison is deterministic while platform
    // fallback still gets a chance to resolve every real character first.
    final loader = FontLoader(_probeFamily)
      ..addFont(rootBundle.load(_probeAsset));
    await loader.load();
  }

  static int _cellHash(Uint8List pixels, int imageWidth, int cellIndex) {
    final cellX = (cellIndex % _columns) * _cellSize;
    final cellY = (cellIndex ~/ _columns) * _cellSize;
    var hash = 0x811C9DC5;
    for (var y = 0; y < _cellSize; y++) {
      var offset = ((cellY + y) * imageWidth + cellX) * 4;
      final end = offset + _cellSize * 4;
      for (; offset < end; offset++) {
        hash = ((hash ^ pixels[offset]) * 0x01000193) & 0xFFFFFFFF;
      }
    }
    return hash;
  }

  static bool _cellsEqual(
    Uint8List pixels,
    int imageWidth,
    int firstCell,
    int secondCell,
  ) {
    final firstX = (firstCell % _columns) * _cellSize;
    final firstY = (firstCell ~/ _columns) * _cellSize;
    final secondX = (secondCell % _columns) * _cellSize;
    final secondY = (secondCell ~/ _columns) * _cellSize;
    for (var y = 0; y < _cellSize; y++) {
      var first = ((firstY + y) * imageWidth + firstX) * 4;
      var second = ((secondY + y) * imageWidth + secondX) * 4;
      final end = first + _cellSize * 4;
      for (; first < end; first++, second++) {
        if (pixels[first] != pixels[second]) return false;
      }
    }
    return true;
  }
}
