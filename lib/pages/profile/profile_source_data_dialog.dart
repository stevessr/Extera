import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';

class ProfileSourceDataDialog extends StatelessWidget {
  final Map<String, dynamic> data;

  const ProfileSourceDataDialog(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encoder = JsonEncoder.withIndent(' ');
    final json = encoder.convert(data);
    final style = TextStyle(
      fontFamily: AppSettings.monospaceFont.value,
      fontFamilyFallback: AppSettings.fontFallback(
        AppSettings.monospaceFallbackFonts,
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).showProfileSource)),
      body: Padding(
        padding: const .all(8),
        child: MaxWidthBody(
          withScrolling: true,
          withoutVerticalPadding: true,
          withoutVisibleBorder: true,
          child: Material(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            color: theme.colorScheme.surfaceContainerHigh,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: double.infinity),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(json, style: style),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
