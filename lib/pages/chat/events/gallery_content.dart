import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/events/audio_player.dart';
import 'package:extera_next/pages/chat/events/html_message.dart';
import 'package:extera_next/pages/chat/events/message.dart';
import 'package:extera_next/pages/chat/events/message_download_content.dart';
import 'package:extera_next/pages/chat/events/redacted_content.dart';
import 'package:extera_next/pages/image_viewer/image_viewer.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/size_string.dart';
import 'package:extera_next/utils/url_launcher.dart';
import 'package:extera_next/widgets/blur_hash.dart';
import 'package:extera_next/widgets/mxc_image.dart';
import '../../../utils/matrix_sdk_extensions/event_extension.dart';

/// Renders an MSC4274 inline media gallery (`dm.filament.gallery`) message:
/// an optional caption on top, a grid of image/video tiles and audio/file
/// rows below.
class GalleryContent extends StatelessWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;
  final Timeline timeline;
  final MessageLayout layout;
  final bool selectable;
  final bool loadMedia;
  final void Function()? onLoadMedia;
  final bool showHiddenMedia;
  final void Function()? onRevealHiddenMedia;
  final String? contentWarning;
  final bool isLeftAligned;
  final bool previousEventSameSender;
  final bool nextEventSameSender;

  /// Optional trailing inline span appended to the end of the caption (used
  /// to reserve space for the inline status row, like in [ImageBubble]).
  final InlineSpan? trailingSpan;

  static const double gridTileSize = 176;

  const GalleryContent(
    this.event, {
    required this.timeline,
    required this.textColor,
    required this.linkColor,
    required this.layout,
    this.selectable = false,
    this.loadMedia = false,
    this.onLoadMedia,
    this.showHiddenMedia = false,
    this.onRevealHiddenMedia,
    this.contentWarning,
    this.isLeftAligned = false,
    this.previousEventSameSender = false,
    this.nextEventSameSender = false,
    this.trailingSpan,
    super.key,
  });

  /// Target width of the gallery (both grid tiles + caption), so the bubble
  /// is not just as wide as a single tile or caption text.
  static double _gridWidth() {
    final available = FluffyThemes.columnWidth * 1.5;
    const tileSize = gridTileSize;
    // Two columns of ~tileSize px, plus internal spacing, clamped so we don't
    // exceed the available chat width. Keep it reasonable on tiny screens too.
    return (tileSize + tileSize + 2).clamp(220.0, available - 16.0);
  }

  Map<String, dynamic> _itemInfo(Map<String, dynamic> item) =>
      item.tryGetMap<String, dynamic>('info') ?? <String, dynamic>{};

  String _tileContentWarningReason(BuildContext context) {
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

  /// Placeholder shown while media is not loaded. When a non-null [button] is
  /// given, an overlay button is rendered on top, like [ImageBubble]'s
  /// `_buildUnloaded` / `_buildHidden` overlays.
  Widget _buildTilePlaceholder(
    BuildContext context,
    Event itemEvent, {
    String? blurhash,
    VoidCallback? onPressed,
    IconData icon = Icons.image,
    String tooltip = '',
  }) {
    final label = tooltip.isEmpty
        ? ''
        : (itemEvent.content
                  .tryGetMap<String, dynamic>('info')
                  ?.tryGet<num>('size'))
              ?.sizeString;
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: BlurHash(
            blurhash: blurhash,
            width: double.infinity,
            height: gridTileSize,
          ),
        ),
        if (onPressed != null)
          Positioned.fill(
            child: Center(
              child: label == null || label.isEmpty
                  ? IconButton.filledTonal(
                      onPressed: onPressed,
                      icon: Icon(icon),
                      tooltip: tooltip,
                    )
                  : FilledButton.tonal(
                      onPressed: onPressed,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Row(
                        mainAxisSize: .min,
                        spacing: 8,
                        children: [Icon(icon, size: 20), Text(label)],
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  /// Builds a tile for an `m.image` or `m.video` gallery item.
  Widget _buildMediaTile(BuildContext context, Event itemEvent) {
    final isVideo = itemEvent.messageType == MessageTypes.Video;
    final info = _itemInfo(itemEvent.content);
    final blurhash = info.tryGet<String>('xyz.amorgan.blurhash');
    // Videos without a thumbnail cannot be rendered as an image without
    // downloading the full attachment, so keep the placeholder for them.
    final canRenderImage =
        itemEvent.hasAttachment && (!isVideo || itemEvent.hasThumbnail);
    final isHidden = contentWarning != null && !showHiddenMedia;

    // Individual tiles stay square; the whole grid is clipped once to the
    // bubble radius ([_gridBorderRadius]), like [ImageBubble].
    // No fixed width here so the lone tile in the last (odd) row can stretch.
    final Widget tile;
    if (canRenderImage && loadMedia && !isHidden) {
      tile = MxcImage(
        event: itemEvent,
        fit: BoxFit.cover,
        isThumbnail: true,
        placeholder: (context) => BlurHash(
          blurhash: blurhash,
          width: gridTileSize,
          height: gridTileSize,
        ),
      );
    } else if (isHidden) {
      // The hidden state is covered by a single reveal button overlaying
      // the whole grid (see [build]); tiles stay as bare placeholders.
      tile = _buildTilePlaceholder(context, itemEvent, blurhash: blurhash);
    } else {
      tile = _buildTilePlaceholder(
        context,
        itemEvent,
        blurhash: blurhash,
        onPressed: loadMedia ? null : onLoadMedia,
        icon: isVideo ? Icons.video_library : Icons.image,
        tooltip: isVideo
            ? L10n.of(context).downloadVideoNoSize
            : L10n.of(context).loadImageNoSize,
      );
    }
    return InkWell(
      onTap: () {
        if (isHidden) return;
        if (!loadMedia) {
          onLoadMedia?.call();
          return;
        }
        showDialog(
          context: context,
          useRootNavigator: false,
          builder: (_) =>
              ImageViewer(itemEvent, timeline: timeline, outerContext: context),
        );
      },
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: tile),
          if (isVideo && !isHidden && loadMedia && canRenderImage)
            Icon(
              Icons.play_circle_outline,
              size: 48,
              color: Colors.white.withAlpha(200),
            ),
        ],
      ),
    );
  }

  /// Builds the caption, styled like a normal text message.
  Widget _buildCaption(BuildContext context, double fontSize) {
    final body = event.body;
    if (body.isEmpty) return const SizedBox.shrink();
    final formattedHtml =
        AppSettings.renderHtml.value &&
            event.content.tryGet<String>('format') == 'org.matrix.custom.html'
        ? event.content.tryGet<String>('formatted_body')
        : null;
    if (formattedHtml != null) {
      return HtmlMessage(
        html: formattedHtml,
        textColor: textColor,
        room: event.room,
        selectable: selectable,
        fontSize: fontSize,
        trailingSpan: trailingSpan,
        linkStyle: TextStyle(color: linkColor, fontSize: fontSize),
        onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
        onCopy: () {
          Clipboard.setData(ClipboardData(text: event.body));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.of(context).copiedToClipboard)),
          );
        },
      );
    }
    final textScaler = MediaQuery.textScalerOf(context);
    final richSpan = TextSpan(
      style: TextStyle(color: textColor, fontSize: fontSize),
      children: [
        TextSpan(text: body),
        ?trailingSpan,
      ],
    );
    return selectable
        ? SelectableText.rich(richSpan, textScaler: textScaler)
        : Text.rich(richSpan, textScaler: textScaler);
  }

  /// Border radius of the grid clip, computed like [ImageBubble]'s: rounded
  /// corners follow the bubble shape, bottom corners are hard when a caption
  /// is present, top corners are hard when it is a reply.
  BorderRadius _gridBorderRadius() {
    final hardCorner = Radius.circular(2);
    final roundedCorner = Radius.circular(AppConfig.borderRadius - 2);

    var borderRadius = BorderRadius.all(roundedCorner);

    if (layout != .modern) {
      if (!isLeftAligned) {
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

      final hasCaption = event.body.isNotEmpty;
      if (hasCaption) {
        borderRadius = borderRadius.copyWith(
          bottomLeft: hardCorner,
          bottomRight: hardCorner,
        );
      }

      if (event.inReplyToEventId(includingFallback: false) != null &&
          hasCaption) {
        borderRadius = borderRadius.copyWith(
          topLeft: hardCorner,
          topRight: hardCorner,
        );
      }
    }

    return borderRadius;
  }

  @override
  Widget build(BuildContext context) {
    final fontSize =
        AppSettings.fontSizeFactor.value * AppSettings.messageFontSize.value;

    if (event.redacted) {
      return EventRedactedContent(
        event: event,
        textColor: textColor,
        fontSize: fontSize,
      );
    }

    final items = galleryItems(event);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Text(
          event.body,
          style: TextStyle(color: textColor, fontSize: fontSize),
        ),
      );
    }

    final gridTiles = <Widget>[];
    final rows = <Widget>[];
    var index = 0;
    for (final item in items) {
      final itemEvent = galleryItemEvent(event, item, index);
      index++;
      final msgType = itemEvent.messageType;
      final contentWarning = this.contentWarning;
      final showHiddenMedia = this.showHiddenMedia;
      if (msgType == MessageTypes.Image ||
          (msgType == MessageTypes.Video &&
              PlatformInfos.supportsVideoPlayer)) {
        gridTiles.add(_buildMediaTile(context, itemEvent));
        continue;
      }
      if (msgType == MessageTypes.Audio &&
          (PlatformInfos.isMobile ||
              PlatformInfos.isMacOS ||
              PlatformInfos.isWeb ||
              PlatformInfos.isLinux)) {
        rows.add(
          AudioPlayerWidget(
            itemEvent,
            color: textColor,
            linkColor: linkColor,
            fontSize: fontSize,
            layout: layout,
            loadMedia: loadMedia,
            showHiddenMedia: showHiddenMedia,
            onLoadMedia: onLoadMedia,
            onRevealHiddenMedia: onRevealHiddenMedia,
            contentWarning: contentWarning,
            selectable: selectable,
          ),
        );
        continue;
      }
      rows.add(
        MessageDownloadContent(
          itemEvent,
          textColor: textColor,
          linkColor: linkColor,
          layout: layout,
          loadMedia: loadMedia,
          showHiddenMedia: showHiddenMedia,
          onLoadMedia: onLoadMedia,
          onRevealHiddenMedia: onRevealHiddenMedia,
          contentWarning: contentWarning,
        ),
      );
    }

    final gridWidth = _gridWidth();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        if (gridTiles.isNotEmpty)
          Padding(
            padding: .all(layout == .modern ? 0 : 2),
            child: Container(
              decoration: BoxDecoration(borderRadius: _gridBorderRadius()),
              clipBehavior: Clip.antiAlias,
              width: gridWidth,
              child: contentWarning != null && !showHiddenMedia
                  // The content warning applies to the gallery as a whole,
                  // so a single button reveals all tiles at once.
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        _GridLayout(tiles: gridTiles, tileSize: gridTileSize),
                        FilledButton.tonal(
                          onPressed: onRevealHiddenMedia,
                          child: Row(
                            mainAxisSize: .min,
                            children: [
                              const Icon(Icons.visibility_off_outlined),
                              const SizedBox(width: 12),
                              Text(_tileContentWarningReason(context)),
                            ],
                          ),
                        ),
                      ],
                    )
                  : _GridLayout(tiles: gridTiles, tileSize: gridTileSize),
            ),
          ),
        if (rows.isNotEmpty) ...rows,
        if (event.body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _buildCaption(context, fontSize),
          ),
      ],
    );
  }
}

/// Lays gallery tiles in rows of up to 2. A lone tile in the last row
/// stretches to the full grid width instead of leaving an empty cell.
class _GridLayout extends StatelessWidget {
  final List<Widget> tiles;
  final double tileSize;

  const _GridLayout({required this.tiles, required this.tileSize});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (var i = 0; i < tiles.length; i++)
          Builder(
            builder: (context) {
              final isLastLone = tiles.length.isOdd && i == tiles.length - 1;
              return SizedBox(
                width: isLastLone ? (tileSize * 2 + 2) : tileSize,
                height: tileSize,
                child: tiles[i],
              );
            },
          ),
      ],
    );
  }
}
