import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart' deferred as lottie;

import 'package:extera_next/config/animated_emoji_config.dart';

class AnimatedEmojiAtlas {
  final ui.Image image;
  final int tileSize;
  final int columns;
  final int frameCount;
  final Duration duration;

  const AnimatedEmojiAtlas({
    required this.image,
    required this.tileSize,
    required this.columns,
    required this.frameCount,
    required this.duration,
  });

  int get estimatedBytes => image.width * image.height * 4;

  ui.Rect sourceRect(int frameIndex) {
    final safeIndex = frameIndex < 0
        ? 0
        : frameIndex >= frameCount
        ? frameCount - 1
        : frameIndex;
    final x = (safeIndex % columns) * tileSize;
    final y = (safeIndex ~/ columns) * tileSize;
    return ui.Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      tileSize.toDouble(),
      tileSize.toDouble(),
    );
  }

  int frameIndexFor(Duration elapsed) {
    if (frameCount <= 1 || duration <= Duration.zero) return 0;
    final durationUs = duration.inMicroseconds;
    final phaseUs = elapsed.inMicroseconds % durationUs;
    final index = phaseUs * frameCount ~/ durationUs;
    return index >= frameCount ? frameCount - 1 : index;
  }

  void dispose() => image.dispose();
}

class AnimatedEmojiAtlasHandle {
  final AnimatedEmojiAtlas atlas;
  final void Function() _release;
  bool _released = false;

  AnimatedEmojiAtlasHandle(this.atlas, this._release);

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}

class _AtlasCacheEntry {
  final AnimatedEmojiAtlas atlas;
  int refCount;

  _AtlasCacheEntry(this.atlas, {this.refCount = 0});
}

/// Process-wide sprite-atlas cache for animated emoji.
///
/// A Lottie composition is parsed once per codepoint, and each codepoint +
/// physical-size bucket is rasterized once into a single texture containing all
/// sampled frames. Every visible instance then performs only one drawImageRect
/// per animation frame.
class AnimatedEmojiAtlasPool {
  static final AnimatedEmojiAtlasPool instance = AnimatedEmojiAtlasPool._();

  AnimatedEmojiAtlasPool._();

  final Map<String, dynamic> _compositions = {};
  final Map<String, Future<dynamic>> _compositionPending = {};
  final Map<String, _AtlasCacheEntry> _entries = {};
  final Map<String, Future<AnimatedEmojiAtlas?>> _atlasPending = {};

  int _estimatedBytes = 0;

  Future<AnimatedEmojiAtlasHandle?> acquire({
    required String codepoint,
    required int rasterSize,
    required String assetPath,
    required Uri networkUri,
  }) async {
    final key = '$codepoint@$rasterSize';
    final cached = _entries.remove(key);
    if (cached != null) {
      cached.refCount++;
      _entries[key] = cached;
      return AnimatedEmojiAtlasHandle(cached.atlas, () => _release(key));
    }

    final pending = _atlasPending[key] ??= _buildAtlas(
      codepoint: codepoint,
      rasterSize: rasterSize,
      assetPath: assetPath,
      networkUri: networkUri,
    );

    final atlas = await pending;
    if (identical(_atlasPending[key], pending)) {
      _atlasPending.remove(key);
    }
    if (atlas == null) return null;

    final raced = _entries.remove(key);
    if (raced != null) {
      raced.refCount++;
      _entries[key] = raced;
      if (!identical(raced.atlas, atlas)) atlas.dispose();
      return AnimatedEmojiAtlasHandle(raced.atlas, () => _release(key));
    }

    final entry = _AtlasCacheEntry(atlas, refCount: 1);
    _entries[key] = entry;
    _estimatedBytes += atlas.estimatedBytes;
    _evictIfNeeded();
    return AnimatedEmojiAtlasHandle(atlas, () => _release(key));
  }

  void _release(String key) {
    final entry = _entries[key];
    if (entry == null) return;
    if (entry.refCount > 0) entry.refCount--;
    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    if (_estimatedBytes <= animatedEmojiAtlasCacheBytes) return;
    for (final key in _entries.keys.toList(growable: false)) {
      final entry = _entries[key];
      if (entry == null || entry.refCount != 0) continue;
      _entries.remove(key);
      _estimatedBytes -= entry.atlas.estimatedBytes;
      entry.atlas.dispose();
      if (_estimatedBytes <= animatedEmojiAtlasCacheBytes) break;
    }
  }

  Future<dynamic> _compositionFor({
    required String codepoint,
    required String assetPath,
    required Uri networkUri,
  }) async {
    final cached = _compositions[codepoint];
    if (cached != null) return cached;

    final existing = _compositionPending[codepoint];
    if (existing != null) return existing;

    final future = _loadComposition(assetPath, networkUri);
    _compositionPending[codepoint] = future;
    try {
      final composition = await future;
      if (composition != null) _compositions[codepoint] = composition;
      return composition;
    } finally {
      if (identical(_compositionPending[codepoint], future)) {
        _compositionPending.remove(codepoint);
      }
    }
  }

  Future<dynamic> _loadComposition(String assetPath, Uri networkUri) async {
    try {
      await lottie.loadLibrary();
      try {
        final data = await rootBundle.load(assetPath);
        return await lottie.LottieComposition.fromByteData(data);
      } catch (_) {
        // Build-time downloads may be intentionally skipped; fall back to the
        // Google-hosted source and keep the platform cache in front of it.
      }

      final Uint8List bytes;
      if (kIsWeb) {
        final response = await http.get(networkUri);
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        bytes = response.bodyBytes;
      } else {
        final file = await DefaultCacheManager().getSingleFile(
          networkUri.toString(),
        );
        bytes = await file.readAsBytes();
      }
      return await lottie.LottieComposition.fromBytes(bytes);
    } catch (error, stackTrace) {
      debugPrint('Unable to load animated emoji atlas source: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<AnimatedEmojiAtlas?> _buildAtlas({
    required String codepoint,
    required int rasterSize,
    required String assetPath,
    required Uri networkUri,
  }) async {
    try {
      final composition = await _compositionFor(
        codepoint: codepoint,
        assetPath: assetPath,
        networkUri: networkUri,
      );
      if (composition == null) return null;

      await lottie.loadLibrary();
      final duration = composition.duration as Duration;
      final compositionFps = (composition.frameRate as num).toDouble();
      final frameCount = animatedEmojiAtlasFrameCountFor(
        duration,
        compositionFps,
      );
      final columns = math.sqrt(frameCount).ceil();
      final rows = (frameCount / columns).ceil();
      final atlasWidth = columns * rasterSize;
      final atlasHeight = rows * rasterSize;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final drawable = lottie.LottieDrawable(composition);

      for (var index = 0; index < frameCount; index++) {
        final progress = frameCount == 1 ? 0.0 : index / frameCount;
        final x = (index % columns) * rasterSize;
        final y = (index ~/ columns) * rasterSize;
        final destination = ui.Rect.fromLTWH(
          x.toDouble(),
          y.toDouble(),
          rasterSize.toDouble(),
          rasterSize.toDouble(),
        );
        drawable.setProgress(progress);
        canvas.save();
        drawable.draw(canvas, destination);
        canvas.restore();
      }

      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(atlasWidth, atlasHeight);
        return AnimatedEmojiAtlas(
          image: image,
          tileSize: rasterSize,
          columns: columns,
          frameCount: frameCount,
          duration: duration,
        );
      } finally {
        picture.dispose();
      }
    } catch (error, stackTrace) {
      debugPrint('Unable to rasterize animated emoji $codepoint: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }
}

/// One ticker drives every animated emoji in the process.
///
/// The stopwatch keeps phase stable when no emoji is active. Notifications are
/// rate-limited so 60/120 Hz displays do not repaint 10/30 fps source material
/// unnecessarily.
class AnimatedEmojiClock extends ChangeNotifier with WidgetsBindingObserver {
  static final AnimatedEmojiClock instance = AnimatedEmojiClock._();

  late final Ticker _ticker;
  final Stopwatch _watch = Stopwatch();
  Duration _lastNotification = Duration.zero;
  int _activeUsers = 0;
  bool _foreground = true;

  AnimatedEmojiClock._() {
    _ticker = Ticker(_onTick);
    WidgetsBinding.instance.addObserver(this);
  }

  Duration get elapsed => _watch.elapsed;

  void retain() {
    _activeUsers++;
    _syncTicker();
  }

  void release() {
    if (_activeUsers > 0) _activeUsers--;
    _syncTicker();
  }

  void _syncTicker() {
    final shouldRun = _activeUsers > 0 && _foreground;
    if (shouldRun) {
      if (!_watch.isRunning) _watch.start();
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
      if (_watch.isRunning) _watch.stop();
    }
  }

  void _onTick(Duration _) {
    final now = _watch.elapsed;
    final minimumInterval = Duration(
      microseconds: Duration.microsecondsPerSecond ~/ animatedEmojiAtlasMaxFps,
    );
    if (now - _lastNotification < minimumInterval) return;
    _lastNotification = now;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = switch (state) {
      AppLifecycleState.paused ||
      AppLifecycleState.hidden ||
      AppLifecycleState.detached => false,
      _ => true,
    };
    _syncTicker();
  }
}
