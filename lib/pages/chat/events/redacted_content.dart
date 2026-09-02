import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/font_family.dart';

class EventRedactedContent extends StatelessWidget {
  final Event event;
  final Color textColor;
  final double fontSize;

  const EventRedactedContent({
    super.key,
    required this.event,
    required this.textColor,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: event.redactedBecause?.fetchSenderUser(),
      builder: (context, snapshot) {
        final reason = event.redactedBecause?.content.tryGet<String>('reason');
        final redactedBy =
            snapshot.data?.calcDisplayname() ??
            event.redactedBecause?.senderId.localpart ??
            L10n.of(context).user;

        final label = reason == null
            ? L10n.of(context).redactedBy(redactedBy)
            : L10n.of(context).redactedByBecause(redactedBy, reason);

        final fontFamily = resolveFontFamily(
          useSystemFont: AppSettings.systemFont.value,
          configuredFont: AppSettings.chatFont.value,
        );
        final textStyle = TextStyle(
          color: textColor.withAlpha(128),
          fontSize: fontSize,
          fontFamily: AppSettings.systemFont.value
              ? 'SystemFont'
              : AppSettings.chatFont.value.isNotEmpty
              ? AppSettings.systemFont.value
                    ? 'SystemFont'
                    : AppSettings.chatFont.value
              : null,
          fontFamilyFallback: AppSettings.fontFallback(AppSettings.chatFallbackFonts),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text.rich(
            TextSpan(
              children: [
                WidgetSpan(
                  child: Icon(
                    Icons.close,
                    color: textColor.withAlpha(128),
                    size: 21 * AppSettings.fontSizeFactor.value,
                  ),
                ),
                WidgetSpan(child: const SizedBox(width: 4)),
                TextSpan(text: label),
              ],
              style: textStyle,
            ),
          ),
        );
      },
    );
  }
}
