import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/font_family.dart';

class EventUndecryptableContent extends StatelessWidget {
  final Event event;
  final Color textColor;
  final double fontSize;
  final void Function()? onPressed;

  const EventUndecryptableContent({
    super.key,
    required this.event,
    required this.textColor,
    required this.fontSize,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
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

    return InkWell(
      onTap: () {
        onPressed?.call();
      },
      child: Padding(
        padding: const .all(16),
        child: Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                child: Icon(
                  Icons.lock_outline,
                  color: textColor.withAlpha(128),
                  size: 21 * AppSettings.fontSizeFactor.value,
                ),
              ),
              WidgetSpan(child: const SizedBox(width: 4)),
              TextSpan(
                text: L10n.of(
                  context,
                ).couldNotDecryptMessage(event.plaintextBody),
              ),
            ],
            style: textStyle,
          ),
        ),
      ),
    );
  }
}
