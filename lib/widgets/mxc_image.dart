import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:http/http.dart' show ClientException;
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/themes.dart';
import 'package:extera_next/utils/client_download_content_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:extera_next/widgets/matrix.dart';

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

class _MxcImageError extends StatelessWidget {
  final double? width;
  final double? height;

  const _MxcImageError({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Icon(
          Icons.broken_image_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _MxcImageState extends State<MxcImage> {
  /// Global in-memory cache of decoded-input image bytes.
  ///
  /// Raw bytes accumulate quickly (message thumbnails, avatars, stickers),
  /// so the cache is bounded both by total bytes and entry count; the
  /// least-recently-used entries are dropped first. Evicted data is still
  /// available through the on-disk HTTP/media cache, so an eviction only
  /// costs a disk read plus decode, not a network round trip.
  static const int _cacheMaxBytes = 64 * 1024 * 1024;
  static const int _cacheMaxEntries = 1024;

  /// Maximum number of actual load attempts for one image generation.
  static const int _maxLoadAttempts = 4;
  static final Map<String, Uint8List> _imageDataLru = <String, Uint8List>{};
  static int _imageDataBytes = 0;

  Uint8List? _imageDataNoCache;
  bool _loadFailed = false;

  // Incremented whenever the image source changes. Async media requests keep
  // the generation they started with so stale completions cannot populate a
  // newer MxcImage with bytes from the previous grid cell.
  int _loadGeneration = 0;

  Uint8List? get _imageData =>
      widget.cacheKey == null ? _imageDataNoCache : _touch(_lruKey);
  set _imageData(Uint8List? data) {
    if (data == null) return;
    final cacheKey = widget.cacheKey;
    if (cacheKey == null) {
      _imageDataNoCache = data;
      return;
    }
    _store(data);
  }

  String get _lruKey {
    final namespace = widget.cacheName ?? '';
    final cacheKey = widget.cacheKey!;
    if (!widget.isThumbnail) {
      return '$namespace::\u0000$cacheKey::full';
    }
    return '$namespace::\u0000$cacheKey::thumbnail:'
        '${widget.width}x${widget.height}:'
        '${widget.thumbnailMethod.name}:${widget.animated}';
  }

  static Uint8List? _touch(String lruKey) {
    final data = _imageDataLru.remove(lruKey);
    if (data == null) return null;
    _imageDataLru[lruKey] = data; // move to most-recently-used position
    return data;
  }

  void _store(Uint8List data) {
    final lruKey = _lruKey;
    final previous = _imageDataLru.remove(lruKey);
    if (previous != null) {
      _imageDataBytes -= previous.length;
    }
    _imageDataLru[lruKey] = data;
    _imageDataBytes += data.length;
    _evictOverflow();
  }

  static void _evictOverflow() {
    while (_imageDataLru.length > _cacheMaxEntries ||
        (_imageDataBytes > _cacheMaxBytes && _imageDataLru.isNotEmpty)) {
      final oldestKey = _imageDataLru.keys.first;
      final evicted = _imageDataLru.remove(oldestKey)!;
      _imageDataBytes -= evicted.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _imageData;
    final hasData = data != null && data.isNotEmpty;

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: !hasData
          ? _loadFailed
                ? _MxcImageError(width: widget.width, height: widget.height)
                : _MxcImagePlaceholder(
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
                return _MxcImageError(
                  width: widget.width,
                  height: widget.height,
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
        oldWidget.client != widget.client;
    if (!sourceChanged) return;

    _loadGeneration++;
    _imageDataNoCache = null;
    _loadFailed = false;
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
      }
    }
  }

  void _markLoadFailed(int generation) {
    if (!mounted || generation != _loadGeneration || _loadFailed) return;
    setState(() => _loadFailed = true);
  }

  Future<void> _tryLoad(int generation, [int attempt = 1]) async {
    if (!mounted ||
        generation != _loadGeneration ||
        _loadFailed ||
        _imageData != null) {
      return;
    }
    try {
      await _load(generation);
      if (!mounted || generation != _loadGeneration) return;
      final data = _imageData;
      if (data == null || data.isEmpty) {
        _markLoadFailed(generation);
      }
    } catch (error, stackTrace) {
      final retryable =
          error is IOException ||
          error is ClientException ||
          (error is MxcDownloadException && error.isRetryable);
      Logs().d(
        retryable
            ? 'Unable to load mxc image (attempt $attempt)'
            : 'Unable to load mxc image',
        error,
        stackTrace,
      );

      // Retry transport errors plus explicitly transient HTTP responses. A
      // missing/forbidden media URI should fail once rather than fan out into a
      // request burst every time a virtualized picker cell is rebuilt.
      if (!retryable ||
          attempt >= _maxLoadAttempts ||
          !mounted ||
          generation != _loadGeneration) {
        if (_imageData == null) _markLoadFailed(generation);
        return;
      }
      await Future.delayed(widget.retryDuration);
      if (!mounted || generation != _loadGeneration) return;
      await _tryLoad(generation, attempt + 1);
    }
  }
}
