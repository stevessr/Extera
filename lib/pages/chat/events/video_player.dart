import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/events/html_message.dart';
import 'package:extera_next/pages/chat/events/message.dart';
import 'package:extera_next/pages/image_viewer/image_viewer.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/size_string.dart';
import 'package:extera_next/utils/url_launcher.dart';
import 'package:extera_next/widgets/blur_hash.dart';
import 'package:extera_next/widgets/mxc_image.dart';

class EventVideoPlayer extends StatelessWidget {
  final Event event;
  final Timeline? timeline;
  final Color textColor;
  final Color linkColor;
  final bool loadThumbnail;
  final InlineSpan? trailingSpan;

  final bool ownMessage;
  final bool nextEventSameSender;
  final bool previousEventSameSender;
  final MessageLayout layout;
  final bool selectable;

  final bool showHiddenMedia;
  final void Function()? onRevealHiddenMedia;
  final String? contentWarning;

  const EventVideoPlayer(
    this.event,
    this.textColor,
    this.linkColor, {
    this.timeline,
    this.trailingSpan,
    this.selectable = true,
    this.loadThumbnail = false,
    this.ownMessage = false,
    this.nextEventSameSender = false,
    this.previousEventSameSender = false,
    this.showHiddenMedia = false,
    this.onRevealHiddenMedia,
    this.contentWarning,
    required this.layout,
    super.key,
  });

  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  String _hiddenReason(BuildContext context) {
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

  @override
  Widget build(BuildContext context) {
    final supportsVideoPlayer = PlatformInfos.supportsVideoPlayer;

    final hardCorner = Radius.circular(2);
    final roundedCorner = Radius.circular(AppConfig.borderRadius - 2);

    var borderRadius = BorderRadius.all(roundedCorner);

    final blurHash =
        (event.thumbnailInfoMap as Map<String, dynamic>).tryGet<String>(
          'xyz.amorgan.blurhash',
        ) ??
        fallbackBlurHash;
    final fileDescription = event.fileDescription == null
        ? null
        : AppSettings.renderHtml.value && event.isRichFileDescription
        ? event.fileDescription
        : event.fileDescription!
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;');
    final isHidden = contentWarning != null && !showHiddenMedia;

    final maxSize = 384.0;

    final infoMap = event.content.tryGetMap<String, Object?>('info');
    final w = infoMap?.tryGet<int>('w');
    final h = infoMap?.tryGet<int>('h');
    final hasDescription = event.fileDescription != null;
    const minBubbleWidth = 180.0;
    var width = maxSize;
    if (w != null && h != null) {
      if (w > h) {
        width = maxSize;
      } else {
        width = max(32, maxSize * (w / h));
      }
    }

    final bubbleWidth = hasDescription ? max(minBubbleWidth, width) : width;

    var aspectRatio = 1.0;

    if (w != null && h != null && w > 0 && h > 0) {
      aspectRatio = w / h;
    }

    final sizeInt = infoMap?.tryGet<num>('size');

    final durationInt = infoMap?.tryGet<int>('duration');
    final duration = durationInt == null
        ? null
        : Duration(milliseconds: durationInt);

    if (layout != .modern) {
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
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        Padding(
          padding: .all(layout == .modern ? 0 : 2),
          child: Material(
            clipBehavior: .antiAlias,
            shape: RoundedRectangleBorder(borderRadius: borderRadius),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bubbleWidth),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Stack(
                  children: [
                    if (!isHidden && event.hasThumbnail && loadThumbnail)
                      MxcImage(
                        event: event,
                        isThumbnail: true,
                        width: bubbleWidth,
                        fit: BoxFit.cover,
                        placeholder: (context) => LayoutBuilder(
                          builder: (context, constraints) => BlurHash(
                            blurhash: blurHash,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            fit: .cover,
                          ),
                        ),
                      )
                    else
                      BlurHash(
                        blurhash: blurHash,
                        width: bubbleWidth,
                        height: bubbleWidth * aspectRatio,
                        fit: .cover,
                      ),
                    if (isHidden)
                      Center(
                        child: FilledButton.tonal(
                          onPressed: onRevealHiddenMedia,
                          child: Row(
                            mainAxisSize: .min,
                            children: [
                              const Icon(Icons.visibility_off_outlined),
                              const SizedBox(width: 12),
                              Text(_hiddenReason(context)),
                            ],
                          ),
                        ),
                      )
                    else
                      Center(
                        child: FilledButton.tonal(
                          onPressed: () => supportsVideoPlayer
                              ? showDialog(
                                  context: context,
                                  useRootNavigator: false,
                                  builder: (_) => ImageViewer(
                                    event,
                                    timeline: timeline,
                                    outerContext: context,
                                  ),
                                )
                              : event.saveFile(context),
                          child: Row(
                            mainAxisSize: .min,
                            children: [
                              supportsVideoPlayer
                                  ? const Icon(Icons.play_arrow_outlined)
                                  : const Icon(Icons.file_download_outlined),
                              const SizedBox(width: 12),
                              Text(
                                supportsVideoPlayer
                                    ? sizeInt == null
                                          ? L10n.of(context).playVideoNoSize
                                          : sizeInt.sizeString
                                    : sizeInt == null
                                    ? L10n.of(context).downloadVideoNoSize
                                    : sizeInt.sizeString,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!isHidden && duration != null)
                      Positioned(
                        bottom: 8,
                        left: 16,
                        child: Text(
                          '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black.withAlpha(32),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (fileDescription != null)
          SizedBox(
            width: width,
            child: Padding(
              padding: .symmetric(
                horizontal: layout == .modern ? 0 : 16,
                vertical: 4,
              ),
              child: HtmlMessage(
                html: fileDescription,
                textColor: textColor,
                room: event.room,
                fontSize:
                    AppSettings.fontSizeFactor.value *
                    AppSettings.messageFontSize.value,
                linkStyle: TextStyle(
                  color: linkColor,
                  fontSize:
                      AppSettings.fontSizeFactor.value *
                      AppSettings.messageFontSize.value,
                  decoration: .none,
                ),
                trailingSpan: trailingSpan,
                selectable: selectable,
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
