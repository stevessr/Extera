import 'package:material_ui/material_ui.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/generated/l10n/l10n.dart';

class PermissionsListTile extends StatelessWidget {
  final String permissionKey;
  final int permission;
  final String? category;
  final void Function(int? level)? onChanged;
  final bool canEdit;

  /// Optional pre-resolved display name. If non-null it is shown verbatim
  /// instead of looking up a localized string for [category]+[permissionKey].
  final String? displayName;

  const PermissionsListTile({
    super.key,
    required this.permissionKey,
    required this.permission,
    this.category,
    required this.onChanged,
    required this.canEdit,
    this.displayName,
  });

  String getLocalizedPowerLevelString(BuildContext context) {
    final displayName = this.displayName;
    if (displayName != null) return displayName;
    if (category == null) {
      switch (permissionKey) {
        case 'users_default':
          return L10n.of(context).defaultPermissionLevel;
        case 'events_default':
          return L10n.of(context).sendMessages;
        case 'state_default':
          return L10n.of(context).changeGeneralChatSettings;
        case 'ban':
          return L10n.of(context).banFromChat;
        case 'kick':
          return L10n.of(context).kickFromChat;
        case 'redact':
          return L10n.of(context).deleteMessage;
        case 'invite':
          return L10n.of(context).inviteOtherUsers;
      }
    } else if (category == 'notifications') {
      switch (permissionKey) {
        case 'rooms':
          return L10n.of(context).sendRoomNotifications;
      }
    } else if (category == 'events') {
      switch (permissionKey) {
        case EventTypes.RoomName:
          return L10n.of(context).changeTheNameOfTheGroup;
        case EventTypes.RoomTopic:
          return L10n.of(context).changeTheDescriptionOfTheGroup;
        case EventTypes.RoomPowerLevels:
          return L10n.of(context).changeTheChatPermissions;
        case EventTypes.HistoryVisibility:
          return L10n.of(context).changeTheVisibilityOfChatHistory;
        case EventTypes.RoomCanonicalAlias:
          return L10n.of(context).changeTheCanonicalRoomAlias;
        case EventTypes.RoomAvatar:
          return L10n.of(context).editRoomAvatar;
        case EventTypes.RoomTombstone:
          return L10n.of(context).replaceRoomWithNewerVersion;
        case EventTypes.Encryption:
          return L10n.of(context).enableEncryption;
        case 'm.room.server_acl':
          return L10n.of(context).editBlockedServers;
      }
    }
    return permissionKey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final tier = permission >= 100
        ? _LevelTier.admin
        : permission >= 50
        ? _LevelTier.moderator
        : _LevelTier.user;
    final tierColor = switch (tier) {
      .admin => Colors.orangeAccent,
      .moderator => Colors.blueAccent,
      .user => Colors.greenAccent,
    };
    final tierLabel = switch (tier) {
      .admin => L10n.of(context).adminLevel(permission),
      .moderator => L10n.of(context).moderatorLevel(permission),
      .user => L10n.of(context).userLevel(permission),
    };

    return ListTile(
      title: Text(getLocalizedPowerLevelString(context)),
      trailing: MenuAnchor(
        alignmentOffset: const Offset(0, 4),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainer),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(2),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 4),
          ),
        ),
        menuChildren: [
          _buildMenuItem(
            context,
            label: L10n.of(context).userLevel(permission < 50 ? permission : 0),
            value: permission < 50 ? permission : 0,
            selected: tier == _LevelTier.user,
            accent: Colors.greenAccent,
          ),
          _buildMenuItem(
            context,
            label: L10n.of(context).moderatorLevel(
              permission < 100 && permission >= 50 ? permission : 50,
            ),
            value: permission < 100 && permission >= 50 ? permission : 50,
            selected: tier == _LevelTier.moderator,
            accent: Colors.blueAccent,
          ),
          _buildMenuItem(
            context,
            label: L10n.of(
              context,
            ).adminLevel(permission >= 100 ? permission : 100),
            value: permission >= 100 ? permission : 100,
            selected: tier == _LevelTier.admin,
            accent: Colors.orangeAccent,
          ),
          const Divider(height: 8),
          _buildMenuItem(
            context,
            label: L10n.of(context).custom,
            value: null,
            selected: false,
            accent: colorScheme.primary,
            leading: const Icon(Icons.tune_outlined, size: 18),
          ),
        ],
        builder: (context, controller, _) {
          return _MenuTriggerChip(
            label: tierLabel,
            color: tierColor,
            enabled: canEdit,
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String label,
    required int? value,
    required bool selected,
    required Color accent,
    Widget? leading,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return MenuItemButton(
      onPressed: canEdit ? () => onChanged?.call(value) : null,
      leadingIcon:
          leading ??
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(
          selected ? colorScheme.secondaryContainer : Colors.transparent,
        ),
        foregroundColor: WidgetStatePropertyAll(
          selected ? colorScheme.onSecondaryContainer : colorScheme.onSurface,
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      ),
      child: Text(label),
    );
  }
}

enum _LevelTier { user, moderator, admin }

class _MenuTriggerChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _MenuTriggerChip({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppConfig.borderRadius / 2);
    final background = enabled
        ? color.withAlpha(32)
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: background,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: foreground),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 20, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
