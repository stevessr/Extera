import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/themes.dart';
import 'package:extera_next/utils/client_download_content_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:extera_next/widgets/matrix.dart';

enum MxcImageCacheCategory { general, sticker, userAvatar, roomAvatar }

class MxcImage extends StatefulWidget {
  final Uri? uri;
  final Event? event;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final bool isThumbnail;
  final bool animated;
  final Duration retryDuration;
  final Duration animationDuration;
  final Curve animationCurve;
  final ThumbnailMethod thumbnailMethod;
  final Widget Function(BuildContext context)? placeholder;
  final String? cacheKey;
  final String? cacheName;
  final MxcImageCacheCategory cacheCategory;
  final Client? client;
  final BorderRadius borderRadius;

  const MxcImage({
    this.uri,
    this.event,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.isThumbnail = true,
    this.animated = false,
    this.animationDuration = FluffyThemes.animationDuration,
    this.retryDuration = const Duration(seconds: 2),
    this.animationCurve = FluffyThemes.animationCurve,
    this.thumbnailMethod = ThumbnailMethod.scale,
    this.cacheKey,
    this.client,
    this.borderRadius = BorderRadius.zero,
    this.cacheName,
    this.cacheCategory = MxcImageCacheCategory.general,
    super.key,
  });

  @override
  State<MxcImage> createState() => _MxcImageState();
}

class _MxcImagePlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final Widget Function(BuildContext context)? placeholder;

  const _MxcImagePlaceholder({
    required this.width,
    required this.height,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return placeholder?.call(context) ??
        Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
        );
  }
}

class _MxcImageMemoryCache {
  final int maxBytes;
  final int maxEntries;
  final Map<String, Uint8List> _lru = <String, Uint8List>{};
  int _bytes = 0;

  _MxcImageMemoryCache({required this.maxBytes, required this.maxEntries});

  Uint8List? touch(String key) {
    final data = _lru.remove(key);
    if (data == null) return null;
    _lru[key] = data;
    return data;
  }

  void store(String key, Uint8List data) {
    final previous = _lru.remove(key);
    if (previous != null) {
      _bytes -= previous.length;
    }
    _lru[key] = data;
    _bytes += data.length;
    _evictOverflow();
  }

  void _evictOverflow() {
    while (_lru.length > maxEntries ||
        (_bytes > maxBytes && _lru.isNotEmpty)) {
      final oldestKey = _lru.keys.first;
      final evicted = _lru.remove(oldestKey)!;
      _bytes -= evicted.length;
    }
  }
}

class _MxcImageState extends State<MxcImage> {
  /// General media keeps the existing conservative bound. Stickers and
  /// avatars live in independent protected pools so ordinary timeline media
  /// cannot evict them. Their limits are deliberately much larger and serve
  /// only as hard safety ceilings for unusually large sessions.
  static final Map<MxcImageCacheCategory, _MxcImageMemoryCache>
  _imageDataCaches = <MxcImageCacheCategory, _MxcImageMemoryCache>{
    MxcImageCacheCategory.general: _MxcImageMemoryCache(
      maxBytes: 64 * 1024 * 1024,
      maxEntries: 1024,
    ),
    MxcImageCacheCategory.sticker: _MxcImageMemoryCache(
      maxBytes: 384 * 1024 * 1024,
      maxEntries: 8192,
    ),
    MxcImageCacheCategory.userAvatar: _MxcImageMemoryCache(
      maxBytes: 128 * 1024 * 1024,
      maxEntries: 8192,
    ),
    MxcImageCacheCategory.roomAvatar: _MxcImageMemoryCache(
      maxBytes: 128 * 1024 * 1024,
      maxEntries: 8192,
    ),
  };

  /// Upper bound for [_tryLoad] retries on persistent IO failures.
  static const int _maxLoadAttempts = 4;

  Uint8List? _imageDataNoCache;

  // Incremented whenever the image source changes. Async media requests keep
  // the generation they started with so stale completions cannot populate a
  // newer MxcImage with bytes from the previous grid cell.
  int _loadGeneration = 0;

  MxcImageCacheCategory get _effectiveCacheCategory {
    if (widget.cacheCategory != MxcImageCacheCategory.general) {
      return widget.cacheCategory;
    }
    if (widget.event?.messageType == MessageTypes.Sticker ||
        (widget.cacheKey != null && widget.animated)) {
      return MxcImageCacheCategory.sticker;
    }
    return MxcImageCacheCategory.general;
  }

  String? get _effectiveCacheKey {
    final explicitKey = widget.cacheKey;
    if (explicitKey != null) return explicitKey;
    if (_effectiveCacheCategory != MxcImageCacheCategory.sticker) return null;

    final dimensions = '${widget.width}x${widget.height}';
    final variant = '$dimensions:${widget.isThumbnail}:${widget.animated}';
    final uri = widget.uri;
    if (uri != null) return 'uri:$uri:$variant';

    final event = widget.event;
    if (event == null) return null;
    final contentUrl = event.content['url'];
    if (contentUrl is String && contentUrl.isNotEmpty) {
      return 'event-url:$contentUrl:$variant';
    }
    return 'event:${event.eventId}:$variant';
  }

  _MxcImageMemoryCache get _cache =>
      _imageDataCaches[_effectiveCacheCategory]!;

  Uint8List? get _imageData {
    final cacheKey = _effectiveCacheKey;
    return cacheKey == null ? _imageDataNoCache : _cache.touch(_lruKey(cacheKey));
  }

  set _imageData(Uint8List? data) {
    if (data == null) return;
    final cacheKey = _effectiveCacheKey;
    if (cacheKey == null) {
      _imageDataNoCache = data;
      return;
    }
    _store(cacheKey, data);
  }

  String _lruKey(String cacheKey) =>
      '${widget.cacheName ?? ''}::\u0000$cacheKey';

  void _store(String cacheKey, Uint8List data) {
    _cache.store(_lruKey(cacheKey), data);
  }

  @override
  Widget build(BuildContext context) {
    final data = _imageData;
    final hasData = data != null && data.isNotEmpty;

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: !hasData
          ? _MxcImagePlaceholder(
              width: widget.width,
              height: widget.height,
              placeholder: widget.placeholder,
            )
          : Image.memory(
              data,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              filterQuality: widget.isThumbnail
                  ? FilterQuality.low
                  : FilterQuality.medium,
              errorBuilder: (context, e, s) {
                Logs().d('Unable to render mxc image', e, s);
                return SizedBox(
                  width: widget.width,
                  height: widget.height,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  void initState() {
    super.initState();
    final generation = _loadGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tryLoad(generation);
    });
  }

  @override
  void didUpdateWidget(MxcImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final sourceChanged =
        oldWidget.uri != widget.uri ||
        oldWidget.event != widget.event ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.isThumbnail != widget.isThumbnail ||
        oldWidget.animated != widget.animated ||
        oldWidget.thumbnailMethod != widget.thumbnailMethod ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.cacheName != widget.cacheName ||
        oldWidget.cacheCategory != widget.cacheCategory ||
        oldWidget.client != widget.client;
    if (!sourceChanged) return;

    _loadGeneration++;
    _imageDataNoCache = null;
    final generation = _loadGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _loadGeneration) {
        _tryLoad(generation);
      }
    });
  }

  Future<void> _load(int generation) async {
    if (!mounted) return;
    final client =
        widget.client ?? widget.event?.room.client ?? Matrix.of(context).client;
    final uri = widget.uri;
    final event = widget.event;

    if (uri != null) {
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final width = widget.width;
      final realWidth = width == null ? null : width * devicePixelRatio;
      final height = widget.height;
      final realHeight = height == null ? null : height * devicePixelRatio;

      final remoteData = await client.downloadMxcCached(
        uri,
        width: realWidth,
        height: realHeight,
        thumbnailMethod: widget.thumbnailMethod,
        isThumbnail: widget.isThumbnail,
        animated: widget.animated,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _imageData = remoteData;
      });
    }

    if (event != null) {
      final useThumbnail = widget.isThumbnail && event.hasThumbnail;
      if (!useThumbnail &&
          !{
            MessageTypes.Image,
            MessageTypes.Sticker,
          }.contains(event.messageType)) {
        Logs().e('Event of type ${event.messageType} has no thumbnail!');
      }
      final data = await event.downloadAndDecryptAttachment(
        getThumbnail: useThumbnail,
      );
      if (generation != _loadGeneration) return;
      if (data.detectFileType is MatrixImageFile) {
        if (!mounted || generation != _loadGeneration) return;
        setState(() {
          _imageData = data.bytes;
        });
        return;
      }
    }
  }

  Future<void> _tryLoad(int generation, [int attempt = 0]) async {
    if (!mounted || generation != _loadGeneration || _imageData != null) {
      return;
    }
    try {
      await _load(generation);
    } catch (error, stackTrace) {
      // Media failures are not limited to dart:io IOException: HTTP status
      // errors, Matrix media errors and cache/database failures can all be
      // transient. Retry all load failures, but keep the existing hard bound.
      Logs().d(
        'Unable to load mxc image (attempt ${attempt + 1})',
        error,
        stackTrace,
      );
      if (attempt >= _maxLoadAttempts ||
          !mounted ||
          generation != _loadGeneration) {
        return;
      }
      await Future.delayed(widget.retryDuration);
      if (!mounted || generation != _loadGeneration) return;
      await _tryLoad(generation, attempt + 1);
    }
  }
}
