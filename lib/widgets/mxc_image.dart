import 'dart:io';
import 'dart:typed_data';

import 'package:extera_next/config/themes.dart';
import 'package:extera_next/utils/client_download_content_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

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

  /// Upper bound for [_tryLoad] retries on persistent IO failures.
  static const int _maxLoadAttempts = 4;
  static final Map<String, Uint8List> _imageDataLru = <String, Uint8List>{};
  static int _imageDataBytes = 0;

  Uint8List? _imageDataNoCache;

  Uint8List? get _imageData =>
      widget.cacheKey == null ? _imageDataNoCache : _touch(_lruKey);
  set _imageData(Uint8List? data) {
    if (data == null) return;
    final cacheKey = widget.cacheKey;
    if (cacheKey == null) {
      _imageDataNoCache = data;
      return;
    }
    _store(cacheKey, data);
  }

  String get _lruKey => '${widget.cacheName ?? ''}::\u0000${widget.cacheKey!}';

  static Uint8List? _touch(String lruKey) {
    final data = _imageDataLru.remove(lruKey);
    if (data == null) return null;
    _imageDataLru[lruKey] = data; // move to most-recently-used position
    return data;
  }

  void _store(String cacheKey, Uint8List data) {
    final lruKey = '${widget.cacheName ?? ''}::\u0000$cacheKey';
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

    return AnimatedCrossFade(
      duration: FluffyThemes.animationDuration,
      firstChild: ClipRRect(
        borderRadius: widget.borderRadius,
        child: data == null
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
      ),
      secondChild: _MxcImagePlaceholder(
        width: widget.width,
        height: widget.height,
        placeholder: widget.placeholder,
      ),
      crossFadeState: hasData
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
  }

  Future<void> _load() async {
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
      if (!mounted) return;
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
      if (data.detectFileType is MatrixImageFile) {
        if (!mounted) return;
        setState(() {
          _imageData = data.bytes;
        });
        return;
      }
    }
  }

  Future<void> _tryLoad([int attempt = 0]) async {
    if (_imageData != null) {
      return;
    }
    try {
      await _load();
    } on IOException catch (_) {
      // Stop after a bounded number of attempts: retrying forever kept
      // burning network and CPU for permanently unavailable media.
      if (attempt >= _maxLoadAttempts) return;
      if (!mounted) return;
      await Future.delayed(widget.retryDuration);
      await _tryLoad(attempt + 1);
    }
  }
}
