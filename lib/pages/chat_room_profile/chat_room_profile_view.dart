import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';
import 'package:extera_next/widgets/list_divider.dart';
import 'package:extera_next/widgets/mxc_image_viewer.dart' show MxcImageViewer;

import 'chat_room_profile.dart';

class ChatRoomProfileView extends StatelessWidget {
  final ChatRoomProfileController controller;
  const ChatRoomProfileView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = controller.room.client;

    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).roomProfile)),
      body: MaxWidthBody(
        child: ListView(
          children: [
            const SizedBox(height: 24),
            // The effective identity in this chat: the in-chat override if
            // one is set, otherwise the account profile.
            FutureBuilder<Profile>(
              future: controller.accountProfile,
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final avatarUrl = controller.avatarUrl ?? profile?.avatarUrl;
                // The account id doubles as fallback letter source while no
                // name is resolvable.
                final displayName =
                    controller.displayName ??
                    profile?.displayName ??
                    client.userID!;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Avatar(
                        mxContent: avatarUrl,
                        name: displayName,
                        client: client,
                        size: Avatar.defaultSize * 2,
                        onTap: avatarUrl == null
                            ? null
                            : () => showDialog(
                                context: context,
                                useRootNavigator: false,
                                builder: (_) => MxcImageViewer(avatarUrl),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        displayName,
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        controller.isCustomized
                            ? L10n.of(context).roomProfileCustomHint
                            : L10n.of(context).roomProfileDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                clipBehavior: Clip.hardEdge,
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(L10n.of(context).editDisplayname),
                      onTap: controller.editDisplayname,
                    ),
                    const ListDivider(),
                    ListTile(
                      leading: const Icon(Icons.photo_outlined),
                      title: Text(L10n.of(context).changeYourAvatar),
                      onTap: controller.changeAvatar,
                    ),
                    if (controller.avatarUrl != null) ...[
                      const ListDivider(),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(L10n.of(context).removeYourAvatar),
                        onTap: controller.removeAvatar,
                      ),
                    ],
                    if (controller.isCustomized) ...[
                      const ListDivider(),
                      ListTile(
                        leading: const Icon(Icons.restart_alt_outlined),
                        title: Text(L10n.of(context).resetToGlobalProfile),
                        onTap: controller.resetToAccountProfile,
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
