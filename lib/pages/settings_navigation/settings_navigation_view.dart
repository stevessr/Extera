import 'package:flutter/material.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';
import 'package:extera_next/widgets/list_divider.dart';
import 'package:extera_next/widgets/settings_switch_list_tile.dart';

import 'settings_navigation.dart';

class SettingsNavigationView extends StatelessWidget {
  final SettingsNavigationController controller;

  const SettingsNavigationView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).navigationAndLayout),
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
                          L10n.of(context).navigationAndLayout,
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).useLegacyAppBar,
                        setting: AppSettings.useLegacyChatListAppBar,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).useLegacyNavBar,
                        setting: AppSettings.useLegacyNavBar,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).enableAppBarCenterTitle,
                        setting: AppSettings.enableAppBarCenterTitle,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).presencesToggle,
                        setting: AppSettings.showPresences,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).separateChatTypes,
                        setting: AppSettings.separateChatTypes,
                      ),
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).showSpaceRoomsInGlobalList,
                        setting: AppSettings.showSpaceRoomsInGlobalList,
                      ),
                      if (PlatformInfos.isMobile) ...[
                        const ListDivider(),
                        SettingsSwitchListTile.adaptive(
                          title: L10n.of(context).displayNavigationRail,
                          setting: AppSettings.displayNavigationRail,
                        ),
                      ],
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).enablePeopleTab,
                        setting: AppSettings.enablePeopleTab,
                      ),
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
