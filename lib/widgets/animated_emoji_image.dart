import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';
import 'package:matrix/matrix.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:extera_next/utils/animated_emoji.dart';
import 'package:extera_next/utils/platform_infos.dart';

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

class _AnimatedEmojiImageState extends State<AnimatedEmojiImage>
    with WidgetsBindingObserver {
  /// Emoji repeat a lot within a chat, so hold on to the parsed animations for
  /// the lifetime of the process.
  static final Map<String, LottieComposition> _compositions = {};

  /// Never load and parse the same emoji twice at once.
  static final Map<String, Future<LottieComposition?>> _pending = {};

  LottieComposition? _composition;

  /// Stable across rebuilds so the visibility detector does not mistake a
  /// rebuilt widget for a different child.
  late final Key _visibilityDetectorKey = UniqueKey();

  /// Whether any part of the emoji intersects the viewport.
  bool _isVisible = true;

  /// Whether the app is foregrounded; hidden tabs must not decode frames.
  bool _appResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(AnimatedEmojiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.codepoint != widget.codepoint) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final playing = switch (state) {
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached => false,
      _ => true,
    };
    if (playing != _appResumed && mounted) {
      setState(() => _appResumed = playing);
    }
  }

  /// Pauses frame decoding while the emoji is scrolled out of the viewport
  /// and resumes when it comes back. Only transitions trigger rebuilds.
  void _onVisibilityChanged(VisibilityInfo info) {
    final visible = info.visibleFraction > 0;
    if (visible != _isVisible && mounted) {
      setState(() => _isVisible = visible);
    }
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

    return VisibilityDetector(
      key: _visibilityDetectorKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: Lottie(
        composition: composition,
        width: size,
        height: size,
        // Emoji are tiny and repeat a lot, which is exactly the case a render
        // cache is meant for: every frame is rasterized/recorded once and reused.
        //
        // The raster cache keys frames by their on-screen size, which it derives
        // from `RenderBox.localToGlobal` × device pixel ratio. For these inline
        // emoji (WidgetSpan children) that size is non-finite on the Web engine,
        // and dart2wasm throws `Infinity or NaN toInt` while building the cache
        // key. The drawing-commands cache keys on `Size.zero` instead, so it is
        // safe on Web while still sparing the per-frame composition walk.
        renderCache: PlatformInfos.isWeb
            ? RenderCache.drawingCommands
            : RenderCache.raster,
        // Off-screen or backgrounded emoji keep their last painted frame
        // instead of burning CPU on invisible animation frames.
        animate: _isVisible && _appResumed,
      ),
    );
  }
}
