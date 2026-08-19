import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// Renders one emoji as the animated WebP Google ships for it.
///
/// While the animation is loading, and whenever it cannot be loaded, the plain
/// emoji glyph is rendered instead, so the text never jumps or goes blank.
class AnimatedEmojiImage extends StatefulWidget {
  final String emoji;
  final Uri url;
  final double fontSize;
  final TextStyle? style;

  const AnimatedEmojiImage({
    required this.emoji,
    required this.url,
    required this.fontSize,
    this.style,
    super.key,
  });

  @override
  State<AnimatedEmojiImage> createState() => _AnimatedEmojiImageState();
}

class _AnimatedEmojiImageState extends State<AnimatedEmojiImage> {
  /// Emoji repeat a lot within a chat, so hold on to the bytes we already
  /// fetched for the lifetime of the process.
  static final Map<String, Uint8List> _memoryCache = {};

  /// Never request the same emoji twice at once.
  static final Map<String, Future<Uint8List?>> _pending = {};

  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AnimatedEmojiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  void _load() {
    final key = widget.url.toString();

    final cached = _memoryCache[key];
    if (cached != null) {
      _bytes = cached;
      return;
    }

    _bytes = null;
    (_pending[key] ??= _fetch(key)).then((bytes) {
      if (bytes == null || !mounted || widget.url.toString() != key) return;
      setState(() => _bytes = bytes);
    });
  }

  static Future<Uint8List?> _fetch(String key) async {
    try {
      final Uint8List bytes;
      if (kIsWeb) {
        // No file system on web, but the browser cache already persists the
        // response for us.
        final response = await http.get(Uri.parse(key));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        bytes = response.bodyBytes;
      } else {
        final file = await DefaultCacheManager().getSingleFile(key);
        bytes = await file.readAsBytes();
      }
      _memoryCache[key] = bytes;
      return bytes;
    } catch (e, s) {
      Logs().d('Unable to load animated emoji $key', e, s);
      return null;
    } finally {
      _pending.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    // Emoji glyphs are drawn slightly larger than the font size.
    final size = widget.fontSize * 1.3;

    if (bytes == null) {
      return Text(widget.emoji, style: widget.style);
    }

    return Image.memory(
      bytes,
      width: size,
      height: size,
      // The source is 512px wide, far more than an inline emoji ever needs.
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) =>
          Text(widget.emoji, style: widget.style),
    );
  }
}
