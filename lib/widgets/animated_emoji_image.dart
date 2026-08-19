import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/utils/animated_emoji.dart';

/// Renders one emoji as the Lottie animation Google ships for it.
///
/// While the animation is loading, and whenever it cannot be loaded, the plain
/// emoji glyph is rendered instead, so the text never jumps or goes blank.
class AnimatedEmojiImage extends StatefulWidget {
  final String emoji;

  /// Codepoint of the animation, as returned by [animatedEmojiCodepoint].
  final String codepoint;

  final double fontSize;
  final TextStyle? style;

  const AnimatedEmojiImage({
    required this.emoji,
    required this.codepoint,
    required this.fontSize,
    this.style,
    super.key,
  });

  @override
  State<AnimatedEmojiImage> createState() => _AnimatedEmojiImageState();
}

class _AnimatedEmojiImageState extends State<AnimatedEmojiImage> {
  /// Emoji repeat a lot within a chat, so hold on to the parsed animations for
  /// the lifetime of the process.
  static final Map<String, LottieComposition> _compositions = {};

  /// Never load and parse the same emoji twice at once.
  static final Map<String, Future<LottieComposition?>> _pending = {};

  LottieComposition? _composition;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AnimatedEmojiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.codepoint != widget.codepoint) _load();
  }

  void _load() {
    final codepoint = widget.codepoint;

    final cached = _compositions[codepoint];
    if (cached != null) {
      _composition = cached;
      return;
    }

    _composition = null;
    (_pending[codepoint] ??= _resolve(codepoint)).then((composition) {
      if (composition == null || !mounted || widget.codepoint != codepoint) {
        return;
      }
      setState(() => _composition = composition);
    });
  }

  static Future<LottieComposition?> _resolve(String codepoint) async {
    try {
      final composition =
          await _fromAsset(codepoint) ?? await _fromNetwork(codepoint);
      if (composition != null) _compositions[codepoint] = composition;
      return composition;
    } catch (e, s) {
      Logs().d('Unable to load animated emoji $codepoint', e, s);
      return null;
    } finally {
      _pending.remove(codepoint);
    }
  }

  /// The animations are downloaded into the bundle at build time.
  static Future<LottieComposition?> _fromAsset(String codepoint) async {
    try {
      final data = await rootBundle.load(animatedEmojiAssetPath(codepoint));
      return await LottieComposition.fromByteData(data);
    } catch (_) {
      // Not bundled, e.g. because the download step was skipped.
      return null;
    }
  }

  static Future<LottieComposition?> _fromNetwork(String codepoint) async {
    final url = animatedEmojiUrl(codepoint).toString();
    final Uint8List bytes;
    if (kIsWeb) {
      // No file system on web, but the browser cache already persists the
      // response for us.
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      bytes = response.bodyBytes;
    } else {
      final file = await DefaultCacheManager().getSingleFile(url);
      bytes = await file.readAsBytes();
    }
    return LottieComposition.fromBytes(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final composition = _composition;
    if (composition == null) {
      return Text(widget.emoji, style: widget.style);
    }

    // Emoji glyphs are drawn slightly larger than the font size.
    final size = widget.fontSize * 1.3;

    return Lottie(
      composition: composition,
      width: size,
      height: size,
      // Emoji are tiny and repeat a lot, which is exactly the case the raster
      // cache is meant for: every frame is rasterized once and then reused.
      renderCache: RenderCache.raster,
    );
  }
}
