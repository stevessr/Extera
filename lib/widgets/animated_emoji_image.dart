import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:visibility_detector/visibility_detector.dart';

import 'package:extera_next/config/animated_emoji_config.dart';
import 'package:extera_next/utils/animated_emoji.dart';
import 'package:extera_next/utils/animated_emoji_atlas.dart';

/// Renders one emoji from the process-wide shared sprite-atlas cache.
///
/// The expensive Lottie traversal happens only once for each codepoint +
/// physical-size bucket. All widget instances then share one texture and one
/// process-wide animation clock.
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
  late final Key _visibilityDetectorKey = UniqueKey();

  AnimatedEmojiAtlasHandle? _atlasHandle;
  String? _requestedCodepoint;
  int? _requestedRasterSize;
  int _loadGeneration = 0;

  bool _isVisible = true;
  bool _tickerModeEnabled = true;
  bool _clockRetained = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerModeEnabled = TickerMode.valuesOf(context).enabled;
    _ensureAtlasForCurrentMetrics();
    _syncClockActivity();
  }

  @override
  void didUpdateWidget(AnimatedEmojiImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.codepoint != widget.codepoint ||
        oldWidget.fontSize != widget.fontSize) {
      _ensureAtlasForCurrentMetrics();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _setClockRetained(false);
    _atlasHandle?.release();
    _atlasHandle = null;
    super.dispose();
  }

  int _targetRasterSize() {
    final devicePixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1;
    final logicalSize = widget.fontSize * 1.3;
    return animatedEmojiAtlasRasterSizeFor(logicalSize * devicePixelRatio);
  }

  void _ensureAtlasForCurrentMetrics() {
    final rasterSize = _targetRasterSize();
    if (_requestedCodepoint == widget.codepoint &&
        _requestedRasterSize == rasterSize) {
      return;
    }

    _requestedCodepoint = widget.codepoint;
    _requestedRasterSize = rasterSize;
    final generation = ++_loadGeneration;

    _setClockRetained(false);
    _atlasHandle?.release();
    _atlasHandle = null;

    AnimatedEmojiAtlasPool.instance
        .acquire(
          codepoint: widget.codepoint,
          rasterSize: rasterSize,
          assetPath: animatedEmojiAssetPath(widget.codepoint),
          networkUri: animatedEmojiUrl(widget.codepoint),
        )
        .then((handle) {
          if (!mounted || generation != _loadGeneration) {
            handle?.release();
            return;
          }
          setState(() => _atlasHandle = handle);
          _syncClockActivity();
        });
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final visible = info.visibleFraction > 0;
    if (visible == _isVisible || !mounted) return;
    setState(() => _isVisible = visible);
    _syncClockActivity();
  }

  void _syncClockActivity() {
    final shouldRetain =
        _atlasHandle != null && _isVisible && _tickerModeEnabled;
    _setClockRetained(shouldRetain);
  }

  void _setClockRetained(bool retained) {
    if (_clockRetained == retained) return;
    _clockRetained = retained;
    if (retained) {
      AnimatedEmojiClock.instance.retain();
    } else {
      AnimatedEmojiClock.instance.release();
    }
  }

  TextStyle get _fallbackStyle =>
      (widget.style ?? const TextStyle()).copyWith(fontSize: widget.fontSize);

  @override
  Widget build(BuildContext context) {
    final handle = _atlasHandle;
    if (handle == null) {
      return Text(widget.emoji, style: _fallbackStyle);
    }

    final size = widget.fontSize * 1.3;
    final playing = _isVisible && _tickerModeEnabled;

    return VisibilityDetector(
      key: _visibilityDetectorKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: Semantics(
        label: widget.emoji,
        image: true,
        child: SizedBox.square(
          dimension: size,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _AnimatedEmojiAtlasPainter(
                atlas: handle.atlas,
                clock: AnimatedEmojiClock.instance,
                playing: playing,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedEmojiAtlasPainter extends CustomPainter {
  final AnimatedEmojiAtlas atlas;
  final AnimatedEmojiClock clock;
  final bool playing;

  _AnimatedEmojiAtlasPainter({
    required this.atlas,
    required this.clock,
    required this.playing,
  }) : super(repaint: playing ? clock : null);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = atlas.frameIndexFor(clock.elapsed);
    final paint = Paint()..filterQuality = ui.FilterQuality.low;
    canvas.drawImageRect(
      atlas.image,
      atlas.sourceRect(frame),
      Offset.zero & size,
      paint,
    );
  }

  @override
  bool shouldRepaint(_AnimatedEmojiAtlasPainter oldDelegate) =>
      oldDelegate.atlas != atlas || oldDelegate.playing != playing;
}
