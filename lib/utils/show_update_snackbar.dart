import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:extera_next/utils/url_launcher.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/platform_infos.dart';

abstract class UpdateNotifier {
  static const String versionStoreKey = 'last_known_version';

  static void showUpdateSnackBar(BuildContext context) async {
    final theme = Theme.of(context);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentVersion = await PlatformInfos.getVersion();
    final store = await SharedPreferences.getInstance();
    final storedVersion = store.getString(versionStoreKey);

    if (currentVersion != storedVersion) {
      if (storedVersion != null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 30),
            showCloseIcon: true,
            dismissDirection: .horizontal,
            closeIconColor: theme.colorScheme.onSurface,
            backgroundColor: theme.colorScheme.surfaceContainerHigh,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.of(context).updateInstalled(currentVersion),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: .end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        padding: const .symmetric(horizontal: 12),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        openLink(AppConfig.donateUrl);
                      },
                      child: Text(L10n.of(context).supportDevelopment),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        foregroundColor: theme.colorScheme.onPrimary,
                        backgroundColor: theme.colorScheme.primary,
                        padding: const .symmetric(horizontal: 12),
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        openLink(AppConfig.changelogUrl);
                      },
                      icon: const Icon(Icons.list),
                      label: Text(L10n.of(context).changelog),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }
      await store.setString(versionStoreKey, currentVersion);
    }
  }
}
