import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/animated_emoji.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';

class ReplyContent extends StatelessWidget {
  final Event replyEvent;
  final bool ownMessage;
  final Timeline? timeline;
  final Color? textColor;
  final bool noBubble;

  const ReplyContent(
    this.replyEvent, {
    this.textColor,
    this.noBubble = false,
    this.ownMessage = false,
    super.key,
    this.timeline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final timeline = this.timeline;
    final displayEvent = timeline != null
        ? replyEvent.getDisplayEvent(timeline)
        : replyEvent;
    final fontSize =
        AppSettings.fontSizeFactor.value * AppSettings.messageFontSize.value;

    final color = theme.brightness == Brightness.dark
        ? (noBubble
              ? theme.colorScheme.onSurface
              : (ownMessage
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSecondaryContainer))
        : ownMessage
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.tertiary;

    final textStyle = TextStyle(
      fontSize: fontSize,
      color: textColor ?? color,
      fontFamily: AppSettings.systemFont.value
          ? 'SystemFont'
          : AppSettings.chatFont.value.isNotEmpty
          ? AppSettings.systemFont.value
                ? 'SystemFont'
                : AppSettings.chatFont.value
          : null,
      fontFamilyFallback: AppSettings.fontFallback(
        AppSettings.chatFallbackFonts,
        colorEmojiFirst: true,
      ),
    );

    return Row(
      mainAxisSize: .min,
      spacing: 2,
      children: [
        Container(
          width: 5,
          height: fontSize * 2 + 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        Flexible(
          fit: .loose,
          child: Padding(
            padding: const .symmetric(horizontal: 6, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FutureBuilder<User?>(
                  initialData: displayEvent.senderFromMemoryOrFallback,
                  future: displayEvent.fetchSenderUser(),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data?.calcDisplayname() ??
                          displayEvent.senderFromMemoryOrFallback
                              .calcDisplayname(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textColor ?? color,
                        fontSize: fontSize,
                      ),
                    );
                  },
                ),
                AnimatedEmojiText(
                  displayEvent
                      .calcLocalizedBodyFallback(
                        MatrixLocals(L10n.of(context)),
                        withSenderNamePrefix: false,
                        hideReply: true,
                        plaintextBody: true,
                      )
                      .split('\n')
                      .first,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: textStyle,
                  fontSize: fontSize,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
