// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present rustyraven <rustyraven[at]extera[dot]xyz>
// SPDX-FileCopyrightText: 2026-Present Contributors to Extera
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat_encryption_settings/chat_encryption_settings.dart';
import 'package:extera_next/utils/beautify_string_extension.dart';
import 'package:extera_next/utils/date_time_extension.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';
import 'package:extera_next/widgets/list_divider.dart';

class ChatEncryptionSettingsView extends StatefulWidget {
  final ChatEncryptionSettingsController controller;

  const ChatEncryptionSettingsView(this.controller, {super.key});

  @override
  State<ChatEncryptionSettingsView> createState() =>
      _ChatEncryptionSettingsViewState();
}

class _ChatEncryptionSettingsViewState
    extends State<ChatEncryptionSettingsView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);

    final controller = widget.controller;
    final room = controller.room;
    return StreamBuilder<Object>(
      stream: room.client.onSync.stream.where(
        (s) => s.rooms?.join?[room.id] != null || s.deviceLists != null,
      ),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_outlined),
            onPressed: () => context.go('/rooms/${controller.roomId!}'),
          ),
          title: Text(L10n.of(context).encryption),
          // actions: [
          //   TextButton(
          //     onPressed: () => launchUrlString(AppConfig.encryptionTutorial),
          //     child: Text(L10n.of(context).help),
          //   ),
          // ],
        ),
        body: MaxWidthBody(
          withoutVisibleBorder: true,
          child: Padding(
            padding: const .symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: borderRadius,
                  clipBehavior: .hardEdge,
                  child: SwitchListTile(
                    secondary: CircleAvatar(
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: const Icon(Icons.lock_outlined),
                    ),
                    title: Text(L10n.of(context).encryptThisChat),
                    value: room.encrypted,
                    onChanged: controller.enableEncryption,
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: borderRadius,
                  clipBehavior: .hardEdge,
                  child: Column(
                    children: [
                      if (room.isDirectChat) ...[
                        const SizedBox(height: 16),
                        ListTile(
                          title: Text(L10n.of(context).interactiveVerification),
                          subtitle: Text(
                            L10n.of(context).interactiveVerificationDescription,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: controller.startVerification,
                              icon: const Icon(Icons.verified_outlined),
                              label: Text(L10n.of(context).verifyStart),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const ListDivider(),
                      ],
                      if (room.encrypted) ...[
                        if (room.isDirectChat) const SizedBox(height: 16),
                        ListTile(
                          title: Text(
                            L10n.of(context).deviceKeys,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        StreamBuilder(
                          stream: room.client.onRoomState.stream.where(
                            (update) => update.roomId == controller.room.id,
                          ),
                          builder: (context, snapshot) => FutureBuilder<List<User>>(
                            future: room.requestParticipants(),
                            builder: (BuildContext context, snapshot) {
                              if (snapshot.hasError) {
                                return Center(
                                  child: Text(
                                    '${L10n.of(context).oopsSomethingWentWrong}: ${snapshot.error}',
                                  ),
                                );
                              }
                              final users = snapshot.data;
                              if (!snapshot.hasData || users == null) {
                                return const Center(
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 2,
                                  ),
                                );
                              }
                              return Column(
                                children: users.map((user) {
                                  final userDeviceKeys =
                                      room.client.userDeviceKeys[user.id];
                                  final masterKey = userDeviceKeys?.masterKey;
                                  final tofuSince =
                                      masterKey?.trustOnFirstUseSince;
                                  return Column(
                                    mainAxisSize: .min,
                                    children: [
                                      ListTile(
                                        leading: CircleAvatar(
                                          child: Text(
                                            (userDeviceKeys
                                                        ?.deviceKeys
                                                        .length ??
                                                    0)
                                                .toString(),
                                          ),
                                        ),
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                user.calcDisplayname(),
                                                maxLines: 1,
                                                overflow: .ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: .start,
                                          mainAxisSize: .min,
                                          children: [
                                            Text(
                                              user.id,
                                              maxLines: 1,
                                              overflow: .ellipsis,
                                              style: TextStyle(
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                            Text(
                                              masterKey == null
                                                  ? L10n.of(
                                                      context,
                                                    ).noUserKeyFound
                                                  : masterKey.verified == true
                                                  ? L10n.of(context).verified
                                                  : tofuSince != null
                                                  ? L10n.of(context).knownSince(
                                                      tofuSince.localizedTime(
                                                        context,
                                                      ),
                                                    )
                                                  : L10n.of(context).unverified,
                                              style: TextStyle(
                                                color: masterKey == null
                                                    ? theme
                                                          .colorScheme
                                                          .onErrorContainer
                                                    : masterKey.verified
                                                    ? Colors.green
                                                    : tofuSince != null
                                                    ? theme.colorScheme.primary
                                                    : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: () =>
                                            controller.uncollapse(user.id),
                                        trailing: IconButton(
                                          onPressed: () =>
                                              controller.uncollapse(user.id),
                                          icon: Icon(
                                            controller.uncollapsedUserId ==
                                                    user.id
                                                ? Icons
                                                      .keyboard_arrow_up_outlined
                                                : Icons
                                                      .keyboard_arrow_down_outlined,
                                          ),
                                        ),
                                      ),
                                      AnimatedSize(
                                        duration:
                                            FluffyThemes.animationDuration,
                                        curve: FluffyThemes.animationCurve,
                                        child:
                                            controller.uncollapsedUserId ==
                                                    user.id &&
                                                userDeviceKeys != null
                                            ? Column(
                                                mainAxisSize: .min,
                                                children: [
                                                  ...userDeviceKeys.deviceKeys.values.map((
                                                    device,
                                                  ) {
                                                    final signedDevice = device
                                                        .hasValidSignatureChain(
                                                          verifiedOnly: false,
                                                          verifiedByTheirMasterKey:
                                                              true,
                                                        );
                                                    final name =
                                                        device
                                                            .deviceDisplayName ??
                                                        device.deviceId;
                                                    return ListTile(
                                                      title: Row(
                                                        mainAxisSize: .min,
                                                        children: [
                                                          if (name != null)
                                                            Text('$name ー '),
                                                          Text(
                                                            device.verified
                                                                ? L10n.of(
                                                                    context,
                                                                  ).verified
                                                                : device.blocked
                                                                ? L10n.of(
                                                                    context,
                                                                  ).blocked
                                                                : !signedDevice
                                                                ? L10n.of(
                                                                    context,
                                                                  ).unsignedDevice
                                                                : L10n.of(
                                                                    context,
                                                                  ).signedDevice,
                                                            style: TextStyle(
                                                              color:
                                                                  device
                                                                      .verified
                                                                  ? Colors.green
                                                                  : device
                                                                        .blocked
                                                                  ? theme
                                                                        .colorScheme
                                                                        .error
                                                                  : !signedDevice
                                                                  ? theme
                                                                        .colorScheme
                                                                        .onErrorContainer
                                                                  : theme
                                                                        .colorScheme
                                                                        .primary,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      subtitle: Text(
                                                        device
                                                                .curve25519Key
                                                                ?.beautified ??
                                                            L10n.of(
                                                              context,
                                                            ).noCurve25519KeyFound,
                                                        style: TextStyle(
                                                          fontFamily:
                                                              AppSettings
                                                                  .monospaceFont
                                                                  .value,
                                                          fontFamilyFallback: AppSettings.fontFallback(
                                                            AppSettings
                                                                .monospaceFallbackFonts,
                                                          ),
                                                        ),
                                                      ),
                                                      leading: CircleAvatar(
                                                        backgroundColor:
                                                            device.verified
                                                            ? Colors.green[900]
                                                            : device.blocked
                                                            ? theme
                                                                  .colorScheme
                                                                  .onError
                                                            : !signedDevice
                                                            ? theme
                                                                  .colorScheme
                                                                  .errorContainer
                                                            : theme
                                                                  .colorScheme
                                                                  .primaryContainer,
                                                        child: Icon(
                                                          device.verified
                                                              ? Icons
                                                                    .check_circle_outline
                                                              : device.blocked
                                                              ? Icons.block
                                                              : !signedDevice
                                                              ? Icons
                                                                    .warning_rounded
                                                              : Icons.stars,
                                                          color: device.verified
                                                              ? Colors
                                                                    .green[200]
                                                              : device.blocked
                                                              ? theme
                                                                    .colorScheme
                                                                    .error
                                                              : !signedDevice
                                                              ? theme
                                                                    .colorScheme
                                                                    .onErrorContainer
                                                              : theme
                                                                    .colorScheme
                                                                    .primary,
                                                        ),
                                                      ),
                                                      trailing: Switch(
                                                        value: !device.blocked,
                                                        onChanged: (_) =>
                                                            controller
                                                                .toggleDeviceKey(
                                                                  device,
                                                                ),
                                                      ),
                                                    );
                                                  }),
                                                ],
                                              )
                                            : const SizedBox(
                                                height: 0,
                                                width: double.infinity,
                                              ),
                                      ),
                                      // const ListDivider(),
                                    ],
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: Text(
                              L10n.of(context).encryptionNotEnabled,
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
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
