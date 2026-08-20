import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/wallpaper.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';
import 'package:extera_next/widgets/list_divider.dart';
import 'chat_wallpaper.dart';

class ChatWallpaperView extends StatelessWidget {
  final ChatWallpaperController controller;

  const ChatWallpaperView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);

    final config = controller.config;
    final image = config.image;

    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(l10n.chatWallpaper),
      ),
      backgroundColor: theme.colorScheme.surface,
      body: MaxWidthBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: borderRadius,
                child: Container(
                  height: 212,
                  color: theme.colorScheme.surfaceContainerHigh,
                  alignment: Alignment.center,
                  child: image == null
                      ? Icon(
                          controller.isHidden
                              ? Icons.hide_image_outlined
                              : Icons.wallpaper_outlined,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : Opacity(
                          opacity: controller.opacity,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: controller.blur,
                              sigmaY: controller.blur,
                            ),
                            child: Image(
                              image: image,
                              fit: BoxFit.cover,
                              width: FluffyThemes.columnWidth * 2,
                              height: 212,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                config.isRoomSpecific
                    ? l10n.chatWallpaperIsCustom
                    : l10n.chatWallpaperFollowsGlobal,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Material(
                color: theme.colorScheme.surfaceContainerHigh,
                clipBehavior: Clip.hardEdge,
                borderRadius: borderRadius,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: Text(l10n.setWallpaper),
                      onTap: controller.setWallpaper,
                    ),
                    if (!controller.isHidden) ...[
                      const ListDivider(),
                      ListTile(
                        leading: const Icon(Icons.hide_image_outlined),
                        title: Text(l10n.hideChatWallpaper),
                        onTap: controller.hideWallpaper,
                      ),
                    ],
                    if (controller.isRoomSpecific) ...[
                      const ListDivider(),
                      ListTile(
                        leading: Icon(
                          Icons.settings_backup_restore_outlined,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          l10n.useGlobalWallpaper,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        onTap: controller.useGlobalWallpaper,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // The sliders write into the room, so they only make sense once the
            // room actually has a wallpaper of its own.
            if (controller.isRoomSpecific && image != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Material(
                  color: theme.colorScheme.surfaceContainerHigh,
                  clipBehavior: Clip.hardEdge,
                  borderRadius: borderRadius,
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(l10n.opacity),
                        subtitle: Slider(
                          min: 0.1,
                          max: 1.0,
                          divisions: 9,
                          value: controller.opacity.clamp(0.1, 1.0),
                          label: controller.opacity.toStringAsFixed(1),
                          onChanged: controller.updateOpacity,
                          onChangeEnd: controller.saveOpacity,
                        ),
                      ),
                      const ListDivider(),
                      ListTile(
                        title: Text(l10n.blur),
                        subtitle: Slider(
                          max: 10.0,
                          divisions: 10,
                          value: controller.blur.clamp(0.0, 10.0),
                          label: controller.blur.toStringAsFixed(1),
                          onChanged: controller.updateBlur,
                          onChangeEnd: controller.saveBlur,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
