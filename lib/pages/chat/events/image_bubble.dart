import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/events/html_message.dart';
import 'package:extera_next/pages/image_viewer/image_viewer.dart';
import 'package:extera_next/utils/size_string.dart';
import 'package:extera_next/utils/url_launcher.dart';
import 'package:extera_next/widgets/mxc_image.dart';
import '../../../widgets/blur_hash.dart';

class ImageBubble extends StatelessWidget {
  final Event event;
  final bool tapToView;
  final BoxFit fit;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? linkColor;
  final bool thumbnailOnly;
  final bool animated;
  final double width;
  final double? imageWidth;
  final double height;
  final void Function()? onTap;
  final Timeline? timeline;
  final InlineSpan? trailingSpan;

  final bool ownMessage;
  final bool previousEventSameSender;
  final bool nextEventSameSender;

  final bool loadMedia;
  final void Function()? onLoadMedia;
  final bool showHiddenMedia;
  final void Function()? onRevealHiddenMedia;
  final String? contentWarning;

  const ImageBubble(
    this.event, {
    this.tapToView = true,
    this.backgroundColor,
    this.fit = BoxFit.contain,
    this.thumbnailOnly = true,
    this.width = 400,
    this.imageWidth,
    this.height = 512,
    this.animated = false,
    this.ownMessage = false,
    this.previousEventSameSender = false,
    this.nextEventSameSender = false,
    this.onTap,
    this.timeline,
    this.textColor,
    this.linkColor,
    this.loadMedia = false,
    this.onLoadMedia,
    this.showHiddenMedia = false,
    this.onRevealHiddenMedia,
    this.contentWarning,
    this.trailingSpan,
    super.key,
  });

  double get _effectiveImageWidth => imageWidth ?? width;
  double get _effectiveImageHeight {
    final infoMap = event.infoMap;
    // final imageWidth = infoMap['w'] as int?;
    final imageHeight = infoMap['h'] as int?;

    if (imageHeight == null) return 512.0;

    return min(512, max(256.0, imageHeight.toDouble()));
  }

  double get _aspectRatio {
    // Get image dimensions from event metadata
    final infoMap = event.infoMap;
    final imageWidth = infoMap['w'] as int?;
    final imageHeight = infoMap['h'] as int?;

    if (imageWidth != null &&
        imageHeight != null &&
        imageWidth > 0 &&
        imageHeight > 0) {
      // Return aspect ratio (width / height)
      return (imageWidth / imageHeight).clamp(0.3, 16);
    }

    // Fallback to square aspect ratio if metadata is not available
    return 1.0;
  }

  Widget _buildPlaceholder(BuildContext context) {
    final blurHashString = event.infoMap['xyz.amorgan.blurhash'] is String
        ? event.infoMap['xyz.amorgan.blurhash'] as String
        : 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    return BlurHash(
      blurhash: blurHashString,
      width: _effectiveImageWidth,
      height: _effectiveImageHeight,
      fit: fit,
    );
  }

  String _contentWarningReason(BuildContext context) {
    final l10n = L10n.of(context);
    switch (contentWarning) {
      case 'town.robin.msc3725.spoiler':
        return l10n.contentWarningReason(l10n.contentWarningSpoiler);
      case 'town.robin.msc3725.nsfw':
        return l10n.contentWarningReason(l10n.contentWarningNsfw);
      case 'town.robin.msc3725.graphic':
        return l10n.contentWarningReason(l10n.contentWarningGraphic);
      case 'town.robin.msc3725.medical':
        return l10n.contentWarningReason(l10n.contentWarningMedical);
      default:
        return l10n.contentWarningReason(l10n.contentWarning);
    }
  }

  Widget _buildUnloaded(BuildContext context) {
    final blurHashString = event.infoMap['xyz.amorgan.blurhash'] is String
        ? event.infoMap['xyz.amorgan.blurhash'] as String
        : 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    final size = event.infoMap['size'] is num
        ? event.infoMap['size'] as num
        : null;
    return Stack(
      children: [
        BlurHash(
          blurhash: blurHashString,
          width: _effectiveImageWidth,
          height: _effectiveImageHeight,
          fit: fit,
        ),
        Center(
          child: FilledButton.tonal(
            onPressed: onLoadMedia,
            child: Row(
              mainAxisSize: .min,
              children: [
                const Icon(Icons.image),
                const SizedBox(width: 12),
                Text(
                  size != null
                      ? size.sizeString
                      : L10n.of(context).loadImageNoSize,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHidden(BuildContext context) {
    final blurHashString = event.infoMap['xyz.amorgan.blurhash'] is String
        ? event.infoMap['xyz.amorgan.blurhash'] as String
        : 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    final reason = _contentWarningReason(context);
    return Stack(
      children: [
        BlurHash(
          blurhash: blurHashString,
          width: _effectiveImageWidth,
          height: _effectiveImageHeight,
          fit: fit,
        ),
        Center(
          child: FilledButton.tonal(
            onPressed: onRevealHiddenMedia,
            child: Row(
              mainAxisSize: .min,
              children: [
                const Icon(Icons.visibility_off_outlined),
                const SizedBox(width: 12),
                Text(reason),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _onTap(BuildContext context) {
    if (!loadMedia) return;
    if (onTap != null) {
      onTap!();
      return;
    }
    if (!tapToView) return;
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (_) =>
          ImageViewer(event, timeline: timeline, outerContext: context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hardCorner = Radius.circular(2);
    final roundedCorner = Radius.circular(AppConfig.borderRadius - 2);

    var borderRadius = BorderRadius.all(roundedCorner);

    final fileDescription = event.fileDescription == null
        ? null
        : AppSettings.renderHtml.value && event.isRichFileDescription
        ? event.fileDescription
        : event.fileDescription!
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;');
    final isHidden = contentWarning != null && !showHiddenMedia;
    final textColor = this.textColor;

    if (ownMessage) {
      borderRadius = borderRadius.copyWith(
        topRight: nextEventSameSender ? hardCorner : roundedCorner,
        bottomRight: previousEventSameSender ? hardCorner : roundedCorner,
      );
    } else {
      borderRadius = borderRadius.copyWith(
        topLeft: nextEventSameSender ? hardCorner : roundedCorner,
        bottomLeft: previousEventSameSender ? hardCorner : roundedCorner,
      );
    }

    if (fileDescription != null) {
      borderRadius = borderRadius.copyWith(
        bottomLeft: hardCorner,
        bottomRight: hardCorner,
      );
    }

    if (event.inReplyToEventId(includingFallback: false) != null &&
        fileDescription != null) {
      borderRadius = borderRadius.copyWith(
        topLeft: hardCorner,
        topRight: hardCorner,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Padding(
          padding: const .all(2),
          child: Container(
            decoration: BoxDecoration(
              color: event.messageType == MessageTypes.Sticker
                  ? Colors.transparent
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: borderRadius,
            ),
            clipBehavior: Clip.antiAlias,
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width, maxHeight: height),
              child: AspectRatio(
                aspectRatio: _aspectRatio,
                child: InkWell(
                  onTap: () => _onTap(context),
                  child: Hero(
                    tag: event.eventId,
                    child: isHidden
                        ? _buildHidden(context)
                        : loadMedia
                        ? MxcImage(
                            event: event,
                            width: _effectiveImageWidth,
                            height: _effectiveImageHeight,
                            fit: fit,
                            animated: animated,
                            isThumbnail: thumbnailOnly,
                            placeholder:
                                event.messageType == MessageTypes.Sticker
                                ? null
                                : _buildPlaceholder,
                          )
                        : _buildUnloaded(context),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (fileDescription != null && textColor != null)
          SizedBox(
            width: width,
            child: Padding(
              padding: const .symmetric(horizontal: 16, vertical: 4),
              child: HtmlMessage(
                html: fileDescription,
                textColor: textColor,
                room: event.room,
                fontSize:
                    AppSettings.fontSizeFactor.value *
                    AppSettings.messageFontSize.value,
                trailingSpan: trailingSpan,
                linkStyle: TextStyle(
                  color: linkColor,
                  fontSize:
                      AppSettings.fontSizeFactor.value *
                      AppSettings.messageFontSize.value,
                  decoration: .none,
                ),
                selectable: true,
                onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: event.body));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(L10n.of(context).copiedToClipboard)),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
