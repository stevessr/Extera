import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:linkify/linkify.dart' show linkify;
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/events/poll_content.dart';
import 'package:extera_next/pages/chat/events/redacted_content.dart';
import 'package:extera_next/pages/chat/events/video_player.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/date_time_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:extera_next/utils/poll_events.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/matrix.dart';
import '../../../utils/platform_infos.dart';
import '../../../utils/url_launcher.dart';
import 'audio_player.dart';
import 'cute_events.dart';
import 'html_message.dart';
import 'image_bubble.dart';
import 'map_bubble.dart';
import 'message_download_content.dart';
import 'utd_content.dart';

class MessageContent extends StatelessWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;
  final void Function(Event)? onInfoTab;
  final BorderRadius borderRadius;
  final Timeline timeline;
  final bool selectable;
  final bool useBubbleLayout;

  final bool ownMessage;
  final bool previousEventSameSender;
  final bool nextEventSameSender;

  final bool loadMedia;
  final void Function()? onLoadMedia;
  final bool showHiddenMedia;
  final void Function()? onRevealHiddenMedia;
  final String? contentWarning;

  /// Optional trailing inline span appended to the end of plain text messages
  /// (used to reserve space for the inline status row, Telegram-style).
  final InlineSpan? trailingSpan;

  const MessageContent(
    this.event, {
    this.onInfoTab,
    super.key,
    required this.timeline,
    required this.textColor,
    required this.linkColor,
    required this.borderRadius,
    this.ownMessage = false,
    this.previousEventSameSender = false,
    this.nextEventSameSender = false,
    this.useBubbleLayout = true,
    this.selectable = false,
    this.loadMedia = false,
    this.onLoadMedia,
    this.showHiddenMedia = false,
    this.onRevealHiddenMedia,
    this.contentWarning,
    this.trailingSpan,
  });

  void _verifyOrRequestKey(BuildContext context) async {
    final l10n = L10n.of(context);
    if (event.content['can_request_session'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(event.calcLocalizedBodyFallback(MatrixLocals(l10n))),
        ),
      );
      return;
    }
    final client = Matrix.of(context).client;
    if (client.isUnknownSession && client.encryption!.crossSigning.enabled) {
      final success = await context.push('/backup');
      if (success != true) return;
    }
    event.requestKey();
    final sender = event.senderFromMemoryOrFallback;
    await showAdaptiveBottomSheet(
      context: context,
      builder: (context) => Scaffold(
        appBar: AppBar(
          leading: CloseButton(onPressed: Navigator.of(context).pop),
          title: Text(
            l10n.whyIsThisMessageEncrypted,
            style: const TextStyle(fontSize: 16),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(
                  mxContent: sender.avatarUrl,
                  name: sender.calcDisplayname(),
                  presenceUserId: sender.stateKey,
                  client: event.room.client,
                ),
                title: Text(sender.calcDisplayname()),
                subtitle: Text(event.originServerTs.localizedTime(context)),
                trailing: const Icon(Icons.lock_outlined),
              ),
              const Divider(),
              Text(event.calcLocalizedBodyFallback(MatrixLocals(l10n))),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fontSize =
        AppSettings.fontSizeFactor.value * AppSettings.messageFontSize.value;
    final buttonTextColor = textColor;
    final bigEmotes =
        event.onlyEmotes && event.numberEmotes > 0 && event.numberEmotes <= 3;
    switch (event.type) {
      case EventTypes.Message:
      case EventTypes.Encrypted:
      case EventTypes.Sticker:
      case PollEvents.PollStart:
        // temporary solution
        switch (event.messageType) {
          case MessageTypes.Poll:
            if (event.redacted) continue textmessage;
            return PollWidget(
              event,
              color: textColor,
              linkColor: linkColor,
              fontSize: fontSize,
              timeline: timeline,
            );
          case MessageTypes.Image:
          case MessageTypes.Sticker:
            if (event.redacted) continue textmessage;
            final w = event.content
                .tryGetMap<String, Object?>('info')
                ?.tryGet<int>('w');
            final h = event.content
                .tryGetMap<String, Object?>('info')
                ?.tryGet<int>('h');
            final maxSize = event.messageType == MessageTypes.Sticker
                ? 128.0 * AppSettings.stickerScale.value
                : event.messageType == MessageTypes.Image
                ? h != null
                      ? min(512.0, max(256.0, h.toDouble()))
                      : 512.0
                : 256.0;
            var imageWidth = maxSize;
            var fit = event.messageType == MessageTypes.Sticker
                ? BoxFit.contain
                : BoxFit.cover;
            if (w != null && h != null) {
              fit = BoxFit.contain;
              if (w > h) {
                imageWidth = maxSize;
              } else {
                imageWidth = max(32, maxSize * (w / h));
              }
            }
            // Ensure the bubble is wide enough for text content
            // when there's a file description below the image.
            const minBubbleWidth = 180.0;
            final bubbleWidth = max(minBubbleWidth, imageWidth);
            return ImageBubble(
              event,
              width: bubbleWidth,
              imageWidth: imageWidth,
              height: h == null ? 512.0 : min(512, max(256.0, h.toDouble())),
              fit: fit,
              // borderRadius: borderRadius,
              timeline: timeline,
              textColor: textColor,
              linkColor: linkColor,
              loadMedia: loadMedia,
              showHiddenMedia: showHiddenMedia,
              trailingSpan: trailingSpan,
              onLoadMedia: onLoadMedia,
              onRevealHiddenMedia: onRevealHiddenMedia,
              contentWarning: contentWarning,
              ownMessage: ownMessage,
              nextEventSameSender: nextEventSameSender,
              previousEventSameSender: previousEventSameSender,
            );
          case CuteEventContent.eventType:
            return CuteContent(event);
          case MessageTypes.Audio:
            if (PlatformInfos.isMobile ||
                PlatformInfos.isMacOS ||
                PlatformInfos.isWeb ||
                // Extera Next is not being built for snap, so enable this.
                PlatformInfos.isLinux) {
              return AudioPlayerWidget(
                event,
                color: textColor,
                linkColor: linkColor,
                fontSize: fontSize,
                trailingSpan: trailingSpan,
                loadMedia: loadMedia,
                showHiddenMedia: showHiddenMedia,
                onLoadMedia: onLoadMedia,
                onRevealHiddenMedia: onRevealHiddenMedia,
                contentWarning: contentWarning,
              );
            }
            return MessageDownloadContent(
              event,
              textColor: textColor,
              linkColor: linkColor,
              trailingSpan: trailingSpan,
              loadMedia: loadMedia,
              showHiddenMedia: showHiddenMedia,
              onLoadMedia: onLoadMedia,
              onRevealHiddenMedia: onRevealHiddenMedia,
              contentWarning: contentWarning,
            );
          case MessageTypes.Video:
            return EventVideoPlayer(
              event,
              textColor,
              linkColor,
              timeline: timeline,
              loadThumbnail: loadMedia,
              showHiddenMedia: showHiddenMedia,
              trailingSpan: trailingSpan,
              onRevealHiddenMedia: onRevealHiddenMedia,
              contentWarning: contentWarning,
              ownMessage: ownMessage,
              nextEventSameSender: nextEventSameSender,
              previousEventSameSender: previousEventSameSender,
            );
          case MessageTypes.File:
            return MessageDownloadContent(
              event,
              textColor: textColor,
              linkColor: linkColor,
              trailingSpan: trailingSpan,
              loadMedia: loadMedia,
              showHiddenMedia: showHiddenMedia,
              onLoadMedia: onLoadMedia,
              onRevealHiddenMedia: onRevealHiddenMedia,
              contentWarning: contentWarning,
            );

          case MessageTypes.Text:
          case MessageTypes.Notice:
          case MessageTypes.Emote:
            if (AppSettings.renderHtml.value &&
                !event.redacted &&
                event.isRichMessage) {
              var html = AppSettings.renderHtml.value && event.isRichMessage
                  ? event.formattedText
                  : event.text.replaceAll('<', '&lt;').replaceAll('>', '&gt;');
              if (event.messageType == MessageTypes.Emote) {
                html = '* $html';
              }
              return Padding(
                padding: .symmetric(
                  horizontal: useBubbleLayout ? 16 : 0,
                  vertical: 2,
                ),
                child: HtmlMessage(
                  html: html,
                  textColor: textColor,
                  room: event.room,
                  selectable: selectable,
                  trailingSpan: trailingSpan,
                  fontSize:
                      AppSettings.fontSizeFactor.value *
                      AppSettings.messageFontSize.value,
                  bigEmotes: bigEmotes,
                  linkStyle: TextStyle(
                    color: linkColor,
                    fontSize:
                        AppSettings.fontSizeFactor.value *
                        AppSettings.messageFontSize.value,
                    decoration: .none,
                    fontFamily: AppSettings.systemFont.value
                        ? 'SystemFont'
                        : AppSettings.chatFont.value.isNotEmpty
                        ? AppSettings.systemFont.value
                              ? 'SystemFont'
                              : AppSettings.chatFont.value
                        : null,
                    fontFamilyFallback: AppSettings.twemojiFont.value
                        ? [
                            'Twemoji Mozilla',
                            ...AppSettings.chatFallbackFonts.value.split(','),
                          ]
                        : AppSettings.chatFallbackFonts.value.split(','),
                  ),
                  onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: event.body));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(L10n.of(context).copiedToClipboard),
                      ),
                    );
                  },
                ),
              );
            }
            // else we fall through to the normal message rendering
            continue textmessage;
          case MessageTypes.BadEncrypted:
          case EventTypes.Encrypted:
            return EventUndecryptableContent(
              event: event,
              textColor: textColor,
              fontSize: fontSize,
              onPressed: () => _verifyOrRequestKey(context),
            );
          case MessageTypes.Location:
            final geoUri = Uri.tryParse(
              event.content.tryGet<String>('geo_uri')!,
            );
            if (geoUri != null && geoUri.scheme == 'geo') {
              final latlong = geoUri.path
                  .split(';')
                  .first
                  .split(',')
                  .map((s) => double.tryParse(s))
                  .toList();
              if (latlong.length == 2 &&
                  latlong.first != null &&
                  latlong.last != null) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MapBubble(
                      latitude: latlong.first!,
                      longitude: latlong.last!,
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      icon: Icon(Icons.location_on_outlined, color: textColor),
                      onPressed: UrlLauncher(
                        context,
                        geoUri.toString(),
                      ).launchUrl,
                      label: Text(
                        L10n.of(context).openInMaps,
                        style: TextStyle(color: textColor),
                      ),
                    ),
                  ],
                );
              }
            }
            continue textmessage;
          case MessageTypes.None:
          textmessage:
          default:
            if (event.redacted) {
              return EventRedactedContent(
                event: event,
                textColor: buttonTextColor,
                fontSize: fontSize,
              );
            }
            final messageText = event.calcLocalizedBodyFallback(
              MatrixLocals(L10n.of(context)),
              hideReply: true,
            );
            final messageStyle = TextStyle(
              color: textColor,
              fontSize: bigEmotes ? fontSize * 2 : fontSize,
              decoration: event.redacted ? TextDecoration.lineThrough : null,
              fontFamily: AppSettings.systemFont.value
                  ? 'SystemFont'
                  : AppSettings.chatFont.value.isNotEmpty
                  ? AppSettings.systemFont.value
                        ? 'SystemFont'
                        : AppSettings.chatFont.value
                  : null,
              fontFamilyFallback: AppSettings.twemojiFont.value
                  ? [
                      'Twemoji Mozilla',
                      ...AppSettings.chatFallbackFonts.value.split(','),
                    ]
                  : AppSettings.chatFallbackFonts.value.split(','),
            );
            final messageLinkStyle = TextStyle(
              color: linkColor,
              fontSize: fontSize,
              decoration: .none,
              fontFamily: AppSettings.systemFont.value
                  ? 'SystemFont'
                  : AppSettings.chatFont.value.isNotEmpty
                  ? AppSettings.systemFont.value
                        ? 'SystemFont'
                        : AppSettings.chatFont.value
                  : null,
              fontFamilyFallback: AppSettings.twemojiFont.value
                  ? [
                      'Twemoji Mozilla',
                      ...AppSettings.chatFallbackFonts.value.split(','),
                    ]
                  : AppSettings.chatFallbackFonts.value.split(','),
            );
            final spanChildren = <InlineSpan>[
              ...?buildTextSpanChildren(
                linkify(
                  messageText,
                  options: const LinkifyOptions(humanize: false),
                ),
                style: messageStyle,
                linkStyle: messageStyle.merge(messageLinkStyle),
                onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                useMouseRegion: !selectable,
              ),
              ?trailingSpan,
            ];
            final richSpan = TextSpan(
              style: messageStyle,
              children: spanChildren,
            );
            final textScaler = MediaQuery.textScalerOf(context);
            return Padding(
              padding: .symmetric(
                horizontal: useBubbleLayout ? 16 : 0,
                vertical: 2,
              ),
              child: selectable
                  ? SelectableText.rich(richSpan, textScaler: textScaler)
                  : Text.rich(richSpan, textScaler: textScaler),
            );
        }
      case EventTypes.CallInvite:
        return FutureBuilder<User?>(
          future: event.fetchSenderUser(),
          builder: (context, snapshot) {
            return _ButtonContent(
              label: L10n.of(context).startedACall(
                snapshot.data?.calcDisplayname() ??
                    event.senderFromMemoryOrFallback.calcDisplayname(),
              ),
              icon: '📞',
              textColor: buttonTextColor,
              onPressed: () => onInfoTab!(event),
              fontSize: fontSize,
            );
          },
        );
      default:
        return FutureBuilder<User?>(
          future: event.fetchSenderUser(),
          builder: (context, snapshot) {
            return _ButtonContent(
              label: L10n.of(context).userSentUnknownEvent(
                snapshot.data?.calcDisplayname() ??
                    event.senderFromMemoryOrFallback.calcDisplayname(),
                event.type,
              ),
              icon: 'ℹ️',
              textColor: buttonTextColor,
              onPressed: () => onInfoTab!(event),
              fontSize: fontSize,
            );
          },
        );
    }
  }
}

class _ButtonContent extends StatelessWidget {
  final void Function() onPressed;
  final String label;
  final String icon;
  final Color? textColor;
  final double fontSize;

  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.textColor,
    required this.onPressed,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: onPressed,
        child: Text(
          '$icon  $label',
          style: TextStyle(color: textColor, fontSize: fontSize),
        ),
      ),
    );
  }
}
