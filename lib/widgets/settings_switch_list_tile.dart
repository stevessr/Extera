import 'package:flutter/material.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/widgets/theme_builder.dart';

class SettingsSwitchListTile extends StatefulWidget {
  final AppSettings<bool> setting;
  final String title;
  final String? subtitle;
  final Function(bool)? onChanged;

  const SettingsSwitchListTile.adaptive({
    super.key,
    required this.setting,
    required this.title,
    this.subtitle,
    this.onChanged,
  });

  @override
  SettingsSwitchListTileState createState() => SettingsSwitchListTileState();
}

class SettingsSwitchListTileState extends State<SettingsSwitchListTile> {
  @override
  Widget build(BuildContext context) {
    final subtitle = widget.subtitle;
    return SwitchListTile.adaptive(
      value: widget.setting.value,
      title: Text(widget.title),
      subtitle: subtitle == null ? null : Text(subtitle),
      onChanged: (bool newValue) async {
        // Call listeners only after the preference is committed. Several font
        // listeners read AppSettings synchronously, so the old ordering made
        // them rebuild with the previous value and left mixed typography on
        // screen until another unrelated rebuild happened.
        await widget.setting.setItem(newValue);
        if (!mounted) return;

        widget.onChanged?.call(newValue);

        if (widget.setting == AppSettings.systemFont) {
          ThemeController.of(context).refreshTypography();
        } else if (widget.setting == AppSettings.notoEmojiFont) {
          ThemeController.of(context).refreshTypography(notoEmoji: newValue);
        }

        if (mounted) setState(() {});
      },
    );
  }
}
