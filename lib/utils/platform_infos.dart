import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/url_launcher.dart';
import 'package:extera_next/widgets/list_divider.dart';
import '../config/app_config.dart';

abstract class PlatformInfos {
  static bool get isWeb => kIsWeb;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static bool get isCupertinoStyle => isIOS || isMacOS;

  static bool get isMobile => isAndroid || isIOS;

  /// For desktops which don't support ChachedNetworkImage yet
  static bool get isBetaDesktop => isWindows || isLinux;

  static bool get isDesktop => isLinux || isWindows || isMacOS;

  static bool get usesTouchscreen => !isMobile;

  static bool get supportsVideoPlayer => !isWindows && !isLinux;
  static bool get supportsSpellCheck => isMobile;

  /// Web could also record in theory but currently only wav which is too large
  static bool get platformCanRecord => (isMobile || isMacOS);

  static String get clientName =>
      '${AppConfig.applicationName} ${isWeb ? 'web' : Platform.operatingSystem}${kReleaseMode ? '' : 'Debug'}';

  static Future<String> getVersion() async {
    var version = kIsWeb ? 'Web' : 'Unknown';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    return version;
  }

  static void showDialog(BuildContext context) async {
    final version = await PlatformInfos.getVersion();
    final theme = Theme.of(context);

    showAboutDialog(
      context: context,
      useRootNavigator: false,
      children: [
        Text('Version: $version'),
        Material(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          color: theme.colorScheme.surfaceContainerHighest,
          clipBehavior: .hardEdge,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(
                    Icons.source,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                title: Text(L10n.of(context).sourceCode),
                onTap: () => openLink(AppConfig.sourceCodeUrl),
              ),
              ListDivider(color: theme.colorScheme.surfaceContainerHigh),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.errorContainer,
                  child: Icon(
                    Icons.favorite,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                title: Text(L10n.of(context).supportDevelopment),
                onTap: () => openLink(AppConfig.donateUrl),
              ),
              ListDivider(color: theme.colorScheme.surfaceContainerHigh),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(
                    Icons.list,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                title: const Text('Logs'),
                onTap: () {
                  Navigator.of(context, rootNavigator: false).pop();
                  context.go('/logs');
                },
              ),
              ListDivider(color: theme.colorScheme.surfaceContainerHigh),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.tertiaryContainer,
                  child: Icon(
                    Icons.settings,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
                title: const Text('Advanced config'),
                onTap: () {
                  Navigator.of(context, rootNavigator: false).pop();
                  context.go('/configs');
                },
              ),
            ],
          ),
        ),
      ],
      applicationIcon: Image.asset(
        'assets/logo.png',
        width: 64,
        height: 64,
        filterQuality: FilterQuality.medium,
      ),
      applicationName: AppConfig.applicationName,
    );
  }
}
