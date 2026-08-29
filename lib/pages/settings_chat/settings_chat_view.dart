import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';
import 'package:extera_next/widgets/list_divider.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/mxc_image.dart';
import 'package:extera_next/widgets/settings_switch_list_tile.dart';
import 'settings_chat.dart';

class SettingsChatView extends StatelessWidget {
  final SettingsChatController controller;
  const SettingsChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).chat),
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.textTheme.bodyLarge!.color,
        child: MaxWidthBody(
          withoutVerticalPadding: true,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Material(
                  clipBehavior: Clip.hardEdge,
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: borderRadius,
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(
                          L10n.of(context).chat,
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ListTile(
                        title: Text(L10n.of(context).quickAction),
                        subtitle: Text(L10n.of(context).quickActionDescription),
                        trailing: Row(
                          spacing: 8,
                          mainAxisSize: .min,
                          children: [
                            if (controller.doubleTapAction == 'react')
                              Material(
                                borderRadius: BorderRadius.circular(
                                  AppConfig.borderRadius / 2,
                                ),
                                color: theme.colorScheme.surfaceContainerLow,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    AppConfig.borderRadius / 2,
                                  ),
                                  onTap: () {
                                    controller.changeDefaultReaction();
                                  },
                                  child: Padding(
                                    padding: const .symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child:
                                        controller.doubleTapReact.startsWith(
                                          'mxc://',
                                        )
                                        ? MxcImage(
                                            client: Matrix.of(context).client,
                                            height: 28,
                                            width: 28,
                                            isThumbnail: false,
                                            animated: true,
                                            uri: Uri.parse(
                                              controller.doubleTapReact,
                                            ),
                                          )
                                        : Text(
                                            controller.doubleTapReact,
                                            style: TextStyle(fontSize: 20),
                                          ),
                                  ),
                                ),
                              ),
                            Material(
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius / 2,
                              ),
                              color: theme.colorScheme.surfaceContainerLow,
                              child: DropdownButton<String>(
                                value: controller.doubleTapAction,
                                padding: const .symmetric(horizontal: 12.0),
                                borderRadius: BorderRadius.circular(
                                  AppConfig.borderRadius / 2,
                                ),
                                underline: const SizedBox.shrink(),
                                icon: const SizedBox.shrink(),
                                onChanged: (value) {
                                  controller.setDoubleTapAction(
                                    value ?? "none",
                                  );
                                },
                                items: [
                                  DropdownMenuItem(
                                    value: "none",
                                    child: Text(L10n.of(context).none),
                                  ),
                                  DropdownMenuItem(
                                    value: "react",
                                    child: Text(L10n.of(context).react),
                                  ),
                                  DropdownMenuItem(
                                    value: "reply",
                                    child: Text(L10n.of(context).reply),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).formattedMessages,
                        subtitle: L10n.of(context).formattedMessagesDescription,
                        setting: AppSettings.renderHtml,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).hideMemberChangesInPublicChats,
                        subtitle: L10n.of(
                          context,
                        ).hideMemberChangesInPublicChatsBody,
                        setting: AppSettings.hideMemberChangesInPublicChats,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).hideRedactedMessages,
                        subtitle: L10n.of(context).hideRedactedMessagesBody,
                        setting: AppSettings.hideRedactedEvents,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).autoLoadMedia,
                        subtitle: L10n.of(context).autoLoadMediaLong,
                        setting: AppSettings.autoLoadMedia,
                      ),
                      if (PlatformInfos.isMobile) ...[
                        const ListDivider(),
                        SettingsSwitchListTile.adaptive(
                          title: L10n.of(context).showCameraButton,
                          subtitle: L10n.of(context).showCameraButtonDesc,
                          setting: AppSettings.showCameraButton,
                        ),
                      ],
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(
                          context,
                        ).hideInvalidOrUnknownMessageFormats,
                        setting: AppSettings.hideUnknownEvents,
                      ),
                      const ListDivider(),
                      if (PlatformInfos.isMobile) ...[
                        SettingsSwitchListTile.adaptive(
                          title: L10n.of(context).autoplayImages,
                          setting: AppSettings.autoplayImages,
                        ),
                        const ListDivider(),
                      ],
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).sendOnEnter,
                        setting: AppSettings.sendOnEnter,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).swipeRightToLeftToReply,
                        setting: AppSettings.swipeRightToLeftToReply,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).messageTranslations,
                        setting: AppSettings.messageTranslation,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).latexMath,
                        setting: AppSettings.latexMath,
                      ),
                      if (PlatformInfos.isMobile) ...[
                        const ListDivider(),
                        SettingsSwitchListTile.adaptive(
                          title: L10n.of(context).enableVideoNotes,
                          setting: AppSettings.enableVideoNotes,
                        ),
                      ],
                      // const ListDivider(),
                      // ListTile(
                      //   title: Text(L10n.of(context).messageFontSize),
                      //   trailing: Text(
                      //     '${AppSettings.messageFontSize.value.toStringAsFixed(0)} pt',
                      //   ),
                      // ),
                      // Slider.adaptive(
                      //   min: 8,
                      //   max: 32,
                      //   divisions: 24,
                      //   value: AppSettings.messageFontSize.value,
                      //   semanticFormatterCallback: (d) => d.toString(),
                      //   onChanged: controller.changeMessageFontSize,
                      // ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                Material(
                  clipBehavior: Clip.hardEdge,
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: borderRadius,
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(
                          L10n.of(context).customEmojisAndStickers,
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ListTile(
                        title: Text(L10n.of(context).customEmojisAndStickers),
                        subtitle: Text(
                          L10n.of(context).customEmojisAndStickersBody,
                        ),
                        onTap: () => context.go('/rooms/settings/chat/emotes'),
                        trailing: const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Icon(Icons.chevron_right_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
