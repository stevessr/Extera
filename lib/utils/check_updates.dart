import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'package:flutter/material.dart' as legacy;

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/custom_http_client.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/url_launcher.dart';

class ForgejoRelease {
  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final bool draft;
  final bool prerelease;

  const ForgejoRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.draft,
    required this.prerelease,
  });

  factory ForgejoRelease.fromJson(Map<String, dynamic> json) => ForgejoRelease(
    tagName: json['tag_name'] as String,
    name: json['name'] as String? ?? '',
    body: json['body'] as String? ?? '',
    htmlUrl: json['html_url'] as String,
    draft: json['draft'] as bool? ?? false,
    prerelease: json['prerelease'] as bool? ?? false,
  );
}

Future<List<ForgejoRelease>> fetchReleases() async {
  final http = CustomHttpClient.createHTTPClient();
  final response = await http.get(Uri.parse(AppConfig.updateCheckUrl));

  if (response.statusCode > 399) {
    throw HttpException("Failed to fetch releases: ${response.statusCode}");
  }

  final releases = <ForgejoRelease>[];
  for (final release in jsonDecode(response.body) as List<dynamic>) {
    releases.add(ForgejoRelease.fromJson(release as Map<String, dynamic>));
  }

  return releases;
}

String normalizeVersionTag(String tag) {
  var version = tag.trim();
  if (version.startsWith('v') || version.startsWith('V')) {
    version = version.substring(1);
  }
  final buildIndex = version.indexOf('+');
  if (buildIndex != -1) {
    version = version.substring(0, buildIndex);
  }
  final preIndex = version.indexOf('-');
  if (preIndex != -1) {
    version = version.substring(0, preIndex);
  }
  return version;
}

int compareSemverVersions(String a, String b) {
  final aSegments = a.split('.');
  final bSegments = b.split('.');
  final segmentCount = aSegments.length > bSegments.length
      ? aSegments.length
      : bSegments.length;
  for (var i = 0; i < segmentCount; i++) {
    final aSegment = i < aSegments.length ? aSegments[i] : '';
    final bSegment = i < bSegments.length ? bSegments[i] : '';
    // Non-numeric segments count as 0, same as missing segments.
    final aValue = int.tryParse(aSegment) ?? 0;
    final bValue = int.tryParse(bSegment) ?? 0;
    if (aValue != bValue) {
      return aValue.compareTo(bValue);
    }
  }
  return 0;
}

void checkForUpdates(BuildContext context) async {
  // Web assets are updated in place and PlatformInfos reports the package
  // version as "Web". Do not make a cross-origin request from local web
  // development (the version endpoint intentionally does not enable CORS).
  if (PlatformInfos.isWeb ||
      !AppSettings.checkForUpdates.value ||
      AppConfig.alreadyCheckedUpdates) {
    return;
  }
  if (kDebugMode) {
    Logs().w("Running in debug mode - not checking updates");
    return;
  }
  Logs().v("Checking updates...");
  try {
    final currentVersion = await PlatformInfos.getVersion();
    final releases = await fetchReleases();

    // Drafts and prereleases are not offered as updates; if the server only
    // has those, fall back to the unfiltered list instead of showing nothing.
    var updateableReleases = releases
        .where((release) => !release.draft && !release.prerelease)
        .toList();
    if (updateableReleases.isEmpty) {
      updateableReleases = releases;
    }
    updateableReleases.sort(
      (a, b) => compareSemverVersions(
        normalizeVersionTag(b.tagName),
        normalizeVersionTag(a.tagName),
      ),
    );

    final behindCount = updateableReleases
        .where(
          (release) =>
              compareSemverVersions(
                normalizeVersionTag(release.tagName),
                currentVersion,
              ) >
              0,
        )
        .length;
    if (behindCount == 0) return;

    final latest = updateableReleases.first;
    final latestVersion = normalizeVersionTag(latest.tagName);
    Logs().v(
      "Latest version: $latestVersion | Current version: $currentVersion | Releases behind: $behindCount",
    );

    AppConfig.alreadyCheckedUpdates = true;

    await showAdaptiveBottomSheet(
      context: context,
      useRootNavigator: false,
      builder: (context) {
        return Scaffold(
          appBar: AppBar(title: Text(L10n.of(context).updateAvailableTitle)),
          body: Column(
            mainAxisSize: .min,
            children: [
              Padding(
                padding: const .symmetric(horizontal: 8),
                child: Text(L10n.of(context).updateAvailable(latestVersion)),
              ),
              Padding(
                padding: const .symmetric(horizontal: 8),
                child: Text(L10n.of(context).updateReleasesBehind(behindCount)),
              ),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const .symmetric(horizontal: 8),
                  // WORKAROUND --- https://github.com/foresightmobile/flutter_markdown_plus/issues/144
                  child: MaterialUiCompatibilityBridge(
                    child: MarkdownBody(
                      data: latest.body,
                      styleSheet: MarkdownStyleSheet.fromTheme(
                        legacy.Theme.of(context),
                      ),
                      onTapLink: (text, href, title) {
                        if (href != null) {
                          UrlLauncher(context, href).launchUrl();
                        }
                      },
                    ),
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.list_alt),
                trailing: const Icon(Icons.chevron_right),
                title: Text(L10n.of(context).changelogButton),
                onTap: () {
                  UrlLauncher(context, AppConfig.changelogUrl).launchUrl();
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                trailing: const Icon(Icons.chevron_right),
                title: Text(L10n.of(context).downloadUpdateButton),
                onTap: () {
                  UrlLauncher(context, latest.htmlUrl).launchUrl();
                },
              ),
            ],
          ),
        );
      },
    );
  } catch (e) {
    Logs().e("Failed to check for updates", e);
  }
}
