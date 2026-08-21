import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat_permissions_settings/chat_permissions_settings.dart';
import 'package:extera_next/pages/chat_permissions_settings/permission_list_tile.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';
import 'package:extera_next/widgets/list_divider.dart';
import 'package:extera_next/widgets/matrix.dart';

class _PermissionEntry {
  final String title;
  final String permissionKey;
  final String? category;
  final int? defaultLevel;
  final bool isStateEvent;

  const _PermissionEntry({
    required this.title,
    required this.permissionKey,
    this.isStateEvent = false,
    this.defaultLevel,
    this.category,
  });
}

class _PermissionCategory {
  final String title;
  final List<_PermissionEntry> entries;

  const _PermissionCategory({required this.title, required this.entries});
}

class ChatPermissionsSettingsView extends StatelessWidget {
  final ChatPermissionsSettingsController controller;

  const ChatPermissionsSettingsView(this.controller, {super.key});

  int _resolveLevel(
    Map<String, Object?> powerLevelsContent,
    _PermissionEntry entry,
  ) {
    final defaultUserLevel = entry.permissionKey == 'users_default' ? 0 : 0;
    final defaultEventLevel =
        powerLevelsContent.tryGet<int>('events_default') ?? 0;
    final defaultStateLevel =
        powerLevelsContent.tryGet<int>('state_default') ?? 50;
    if (entry.category == null) {
      final v = powerLevelsContent[entry.permissionKey];
      return v is int ? v : (entry.defaultLevel ?? defaultUserLevel);
    }
    final nested = powerLevelsContent.tryGetMap<String, Object?>(
      entry.category!,
    );
    final v = nested?[entry.permissionKey];
    return v is int
        ? v
        : entry.defaultLevel ??
              (entry.category == 'events'
                  ? entry.isStateEvent
                        ? defaultStateLevel
                        : defaultEventLevel
                  : defaultUserLevel);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);
    final l10n = L10n.of(context);

    final categories0 = [
      _PermissionCategory(
        title: l10n.users,
        entries: [
          _PermissionEntry(
            title: l10n.defaultPermissionLevel,
            permissionKey: 'users_default',
            defaultLevel: 0,
          ),
        ],
      ),
      _PermissionCategory(
        title: l10n.messages,
        entries: [
          _PermissionEntry(
            title: l10n.sendMessages,
            permissionKey: EventTypes.Message,
            category: 'events',
            isStateEvent: false,
          ),
          _PermissionEntry(
            title: l10n.sendStickers,
            permissionKey: EventTypes.Sticker,
            category: 'events',
            isStateEvent: false,
          ),
          _PermissionEntry(
            title: l10n.sendReactions,
            permissionKey: EventTypes.Reaction,
            category: 'events',
            isStateEvent: false,
          ),
          _PermissionEntry(
            title: l10n.startPolls,
            permissionKey: EventTypes.PollStart,
            category: 'events',
            isStateEvent: false,
          ),
          _PermissionEntry(
            title: l10n.voteInPolls,
            permissionKey: EventTypes.PollResponse,
            category: 'events',
            isStateEvent: false,
          ),
          _PermissionEntry(
            title: l10n.endPolls,
            permissionKey: 'org.matrix.msc3381.poll.end',
            category: 'events',
            isStateEvent: false,
          ),
          _PermissionEntry(
            title: l10n.sendRoomNotifications,
            permissionKey: 'room',
            category: 'notifications',
            defaultLevel: 50,
          ),
          _PermissionEntry(
            title: l10n.pinMessages,
            permissionKey: EventTypes.RoomPinnedEvents,
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.otherMessageEvents,
            permissionKey: 'events_default',
            defaultLevel: 0,
          ),
        ],
      ),
      _PermissionCategory(
        title: l10n.calls,
        entries: [
          _PermissionEntry(
            title: l10n.startOrJoinCalls,
            permissionKey: 'org.matrix.msc3401.call.member',
            category: 'events',
            isStateEvent: true,
          ),
        ],
      ),
      _PermissionCategory(
        title: l10n.moderation,
        entries: [
          _PermissionEntry(
            title: l10n.inviteOtherUsers,
            permissionKey: 'invite',
            defaultLevel: 0,
          ),
          _PermissionEntry(
            title: l10n.kickUsers,
            permissionKey: 'kick',
            defaultLevel: 50,
          ),
          _PermissionEntry(
            title: l10n.banUsers,
            permissionKey: 'ban',
            defaultLevel: 50,
          ),
          _PermissionEntry(
            title: l10n.redactMessage,
            permissionKey: 'redact',
            defaultLevel: 50,
          ),
          _PermissionEntry(
            title: l10n.redactOwnMessages,
            permissionKey: EventTypes.Redaction,
            category: 'events',
            isStateEvent: false,
          ),
        ],
      ),
      _PermissionCategory(
        title: l10n.roomMetadata,
        entries: [
          _PermissionEntry(
            title: l10n.editRoomAvatar,
            permissionKey: EventTypes.RoomAvatar,
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.editRoomName,
            permissionKey: EventTypes.RoomName,
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.editRoomTopic,
            permissionKey: EventTypes.RoomTopic,
            category: 'events',
            isStateEvent: true,
          ),
        ],
      ),
      _PermissionCategory(
        title: l10n.roomSettings,
        entries: [
          _PermissionEntry(
            title: l10n.editWidgets,
            permissionKey: 'im.vector.modular.widgets',
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.editRoomEmotes,
            permissionKey: 'im.ponies.room_emotes',
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.changeTheVisibilityOfChatHistory,
            permissionKey: EventTypes.HistoryVisibility,
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.enableEncryption,
            permissionKey: EventTypes.Encryption,
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.editPermissions,
            permissionKey: EventTypes.RoomPowerLevels,
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.editRoomAliases,
            permissionKey: EventTypes.RoomCanonicalAlias,
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.editJoinRules,
            permissionKey: 'm.room.join_rules',
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.editBlockedServers,
            permissionKey: 'm.room.server_acl',
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.upgradeRoom,
            permissionKey: EventTypes.RoomTombstone,
            category: 'events',
            isStateEvent: true,
          ),
          _PermissionEntry(
            title: l10n.editOtherRoomSettings,
            permissionKey: 'state_default',
            defaultLevel: 50,
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(L10n.of(context).chatPermissions),
      ),
      body: MaxWidthBody(
        withoutVerticalPadding: true,
        child: Padding(
          padding: const .all(8),
          child: StreamBuilder(
            stream: controller.onChanged,
            builder: (context, _) {
              final roomId = controller.roomId;
              final room = roomId == null
                  ? null
                  : Matrix.of(context).client.getRoomById(roomId);
              if (room == null) {
                return Center(child: Text(L10n.of(context).noRoomsFound));
              }
              final powerLevelsContent = Map<String, Object?>.from(
                room.getState(EventTypes.RoomPowerLevels)?.content ?? {},
              );
              final canEdit = room.canChangePowerLevel;

              final knownEventKeys = <String>{
                for (final c in categories0)
                  for (final e in c.entries)
                    if (e.category == 'events') e.permissionKey,
              };
              final eventsMap =
                  powerLevelsContent.tryGetMap<String, Object?>('events') ?? {};
              final otherEntries = <_PermissionEntry>[
                for (final key in eventsMap.keys)
                  if (!knownEventKeys.contains(key) && eventsMap[key] is int)
                    _PermissionEntry(
                      title: key,
                      permissionKey: key,
                      category: 'events',
                    ),
              ];
              final categories = <_PermissionCategory>[
                ...categories0,
                if (otherEntries.isNotEmpty)
                  _PermissionCategory(title: l10n.other, entries: otherEntries),
              ];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: borderRadius,
                    clipBehavior: Clip.hardEdge,
                    child: ListTile(
                      leading: const Icon(Icons.info_outlined),
                      subtitle: Text(
                        L10n.of(context).chatPermissionsDescription,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < categories.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _buildCategoryCard(
                      context,
                      theme: theme,
                      borderRadius: borderRadius,
                      category: categories[i],
                      powerLevelsContent: powerLevelsContent,
                      canEdit: canEdit,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(
    BuildContext context, {
    required ThemeData theme,
    required BorderRadius borderRadius,
    required _PermissionCategory category,
    required Map<String, Object?> powerLevelsContent,
    required bool canEdit,
  }) {
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: borderRadius,
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              category.title,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          for (var j = 0; j < category.entries.length; j++) ...[
            if (j > 0) const ListDivider(),
            Builder(
              builder: (context) {
                final entry = category.entries[j];
                final level = _resolveLevel(powerLevelsContent, entry);
                return PermissionsListTile(
                  permissionKey: entry.permissionKey,
                  permission: level,
                  category: entry.category,
                  displayName: entry.title,
                  canEdit: canEdit,
                  onChanged: (newLevel) => controller.editPowerLevel(
                    context,
                    entry.permissionKey,
                    level,
                    newLevel: newLevel,
                    category: entry.category,
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
