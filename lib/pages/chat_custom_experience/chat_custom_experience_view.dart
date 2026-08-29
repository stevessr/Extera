import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';
import 'chat_custom_experience.dart';

class ChatCustomExperienceView extends StatelessWidget {
  final ChatCustomExperience controller;
  const ChatCustomExperienceView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roomId = controller.roomId;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).customExperience)),
      body: MaxWidthBody(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            clipBehavior: Clip.hardEdge,
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(L10n.of(context).roomProfile),
                  onTap: () => context.push('/rooms/$roomId/details/profile'),
                  trailing: const Icon(Icons.chevron_right_outlined),
                ),
                ListTile(
                  leading: const Icon(Icons.wallpaper_outlined),
                  title: Text(L10n.of(context).chatWallpaper),
                  onTap: () => context.push('/rooms/$roomId/details/wallpaper'),
                  trailing: const Icon(Icons.chevron_right_outlined),
                ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(L10n.of(context).privacy),
                  onTap: () => context.push('/rooms/$roomId/details/privacy'),
                  trailing: const Icon(Icons.chevron_right_outlined),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
