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

  static void clearCache(String cacheName) =>
      _MxcImageState._imageDataCaches.remove(cacheName);
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
  static final Map<String?, Map<String, Uint8List>> _imageDataCaches = {};
  Uint8List? _imageDataNoCache;

  /// Bytes of the last successful load, kept around while a reload after a
  /// widget update (e.g. toggling animated avatars) is in flight, so that the
  /// image swaps seamlessly instead of flashing a placeholder.
  Uint8List? _staleData;

  /// The bytes to render: the ones for the current configuration if they are
  /// loaded already, otherwise the last bytes this state ever had, so that a
  /// reconfiguration keeps the old pixels visible until the new ones arrive.
  Uint8List? get _imageData =>
      (widget.cacheKey == null
          ? _imageDataNoCache
          : _imageDataCache[widget.cacheKey]) ??
      _staleData;

  set _imageData(Uint8List? data) {
    if (data == null) return;
    final cacheKey = widget.cacheKey;
    cacheKey == null
        ? _imageDataNoCache = data
        : _imageDataCache[cacheKey] = data;
  }

  Map<String, Uint8List> get _imageDataCache =>
      _imageDataCaches[widget.cacheName ?? ''] ??= {};

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

  @override
  void didUpdateWidget(MxcImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A changed configuration (uri, thumbnailing, animated flag, cache key)
    // invalidates the bytes looked up under the old one. Reload while the
    // previous image stays on screen, see [_staleData].
    final needsReload =
        oldWidget.uri != widget.uri ||
        oldWidget.event != widget.event ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.animated != widget.animated ||
        oldWidget.isThumbnail != widget.isThumbnail ||
        oldWidget.thumbnailMethod != widget.thumbnailMethod;
    if (needsReload && _imageData == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
    }
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
        _imageData = _staleData = remoteData;
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
          _imageData = _staleData = data.bytes;
        });
        return;
      }
    }
  }

  Future<void> _tryLoad() async {
    // Compare against the cache for the *current* configuration only; the
    // [_staleData] holdover must not prevent loading the new bytes.
    final cached = widget.cacheKey == null
        ? _imageDataNoCache
        : _imageDataCache[widget.cacheKey];
    if (cached != null) {
      return;
    }
    try {
      await _load();
    } on IOException catch (_) {
      if (!mounted) return;
      await Future.delayed(widget.retryDuration);
      _tryLoad();
    }
  }
}
