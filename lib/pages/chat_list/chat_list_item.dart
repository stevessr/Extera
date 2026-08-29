import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat_list/unread_bubble.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/cached_localized_body.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/room_space_children_extension.dart';
import 'package:extera_next/utils/memoized_tile_cache.dart';
import 'package:extera_next/utils/room_status_extension.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/hover_builder.dart';
import 'package:extera_next/widgets/matrix.dart';
import '../../config/themes.dart';
import '../../utils/date_time_extension.dart';
import '../../widgets/avatar.dart';

/// Memoized hero-user loads for unnamed rooms. The FutureBuilder future used
/// to be recreated on every rebuild, refiring per-hero database lookups each
/// sync tick. Keyed by room id and hero set so membership changes retrigger;
/// failed lookups evict themselves.
final Map<String, Future<List<User>>> _heroUsersFutures = {};

Future<List<User>> _loadHeroUsersCached(Room room) {
  final key =
      '${room.id}::${room.summary.mHeroes?.join(',') ?? ''}::'
      '${room.directChatMatrixID ?? ''}';
  final cached = _heroUsersFutures[key];
  if (cached != null) return cached;
  final future = room.loadHeroUsers().catchError((Object error) {
    _heroUsersFutures.remove(key);
    throw error;
  });
  if (_heroUsersFutures.length > 128) {
    _heroUsersFutures.remove(_heroUsersFutures.keys.first);
  }
  return _heroUsersFutures[key] = future;
}

/// Snapshot of every input that influences the rendered room row. Compared
/// structurally on every rebuild; when unchanged the previously built widget
/// is reused so Flutter's element tree skips rebuilding that subtree.
typedef ChatListItemDeps = ({
  ThemeData theme,
  String localeName,
  bool activeChat,
  bool noBackgroundColor,
  String? filter,
  String displayname,
  String typingText,
  Room? space,
  Object? spaceNameContent,
  Object? spaceAvatarContent,
  String? lastEventId,
  EventStatus? lastEventStatus,
  bool lastEventRedacted,
  int receiptsCount,
  int notificationCount,
  int highlightCount,
  bool markedUnread,
  bool unread,
  bool hasNewMessages,
  bool isMuted,
  bool isLowPriority,
  bool isFavourite,
  Membership membership,
  String? directChatMatrixId,
  int memberCount,
  Object? avatarContent,
  Object? myMemberContent,
  bool senderMemberMissing,
  bool hasOnLongPress,
  bool hasOnForget,
});

/// Bounded per-room-row tile cache; rows rebuilt only when their deps
/// snapshot changes (new event, badge count, theme, rename, ...).
final MemoizedTileCache<ChatListItemDeps, Widget> _chatListItemTiles =
    MemoizedTileCache(maxEntries: 512);

class ChatListItem extends StatelessWidget {
  final Room room;
  final Room? space;
  final bool noBackgroundColor;
  final bool activeChat;
  final void Function(BuildContext context)? onLongPress;
  final void Function()? onForget;
  final void Function() onTap;
  final String? filter;

  const ChatListItem(
    this.room, {
    this.activeChat = false,
    this.noBackgroundColor = false,
    required this.onTap,
    this.onLongPress,
    this.onForget,
    this.filter,
    this.space,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final filter = this.filter;
    if (filter != null && !displayname.toLowerCase().contains(filter)) {
      return const SizedBox.shrink();
    }
    final space = this.space;
    final lastEvent = room.lastEvent;

    final deps = (
      theme: Theme.of(context),
      localeName: L10n.of(context).localeName,
      activeChat: activeChat,
      noBackgroundColor: noBackgroundColor,
      filter: filter,
      displayname: displayname,
      typingText: room.getLocalizedTypingText(context),
      space: space,
      spaceNameContent: space?.getState(EventTypes.RoomName)?.content,
      spaceAvatarContent: space?.getState(EventTypes.RoomAvatar)?.content,
      lastEventId: lastEvent?.eventId,
      lastEventStatus: lastEvent?.status,
      lastEventRedacted: lastEvent?.redacted ?? false,
      receiptsCount: lastEvent?.receipts.length ?? 0,
      notificationCount: room.notificationCount,
      highlightCount: room.highlightCount,
      markedUnread: room.markedUnread,
      unread: room.isUnread,
      hasNewMessages: room.hasNewMessages,
      isMuted: room.pushRuleState != PushRuleState.notify,
      isLowPriority: room.isLowPriority,
      isFavourite: room.isFavourite,
      membership: room.membership,
      directChatMatrixId: room.directChatMatrixID,
      memberCount: room.summary.mJoinedMemberCount ?? 1,
      avatarContent: room.getState(EventTypes.RoomAvatar)?.content,
      myMemberContent: room
          .getState(EventTypes.RoomMember, room.client.userID!)
          ?.content,
      senderMemberMissing:
          lastEvent != null &&
          room.getState(EventTypes.RoomMember, lastEvent.senderId) == null,
      hasOnLongPress: onLongPress != null,
      hasOnForget: onForget != null,
    );

    return _chatListItemTiles.get(room.id, deps, () => _buildTile(context));
  }

  Widget _buildTile(BuildContext context) {
    final client = Matrix.of(context).client;
    final theme = Theme.of(context);

    final isMuted = room.pushRuleState != PushRuleState.notify;
    final typingText = room.getLocalizedTypingText(context);
    final lastEvent = room.lastEvent;
    final ownMessage = lastEvent?.senderId == room.client.userID;
    final unread = room.isUnread;
    final directChatMatrixId = room.directChatMatrixID;
    final isDirectChat = directChatMatrixId != null;
    final hasNotifications = room.notificationCount > 0;
    final backgroundColor = activeChat
        ? theme.colorScheme.secondaryContainer
        : Colors.transparent;
    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final filter = this.filter;
    if (filter != null && !displayname.toLowerCase().contains(filter)) {
      return const SizedBox.shrink();
    }

    final needLastEventSender = lastEvent == null
        ? false
        : room.getState(EventTypes.RoomMember, lastEvent.senderId) == null;
    final space = this.space;

    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        borderRadius: borderRadius,
        clipBehavior: Clip.hardEdge,
        color: noBackgroundColor ? null : backgroundColor,
        child: FutureBuilder(
          future: room.name.isEmpty ? _loadHeroUsersCached(room) : null,
          builder: (context, _) => HoverBuilder(
            builder: (context, listTileHovered) => ListTile(
              visualDensity: const VisualDensity(vertical: -0.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              onLongPress: () => onLongPress?.call(context),
              leading: HoverBuilder(
                builder: (context, hovered) => AnimatedScale(
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  scale: hovered ? 1.1 : 1.0,
                  child: SizedBox(
                    width: Avatar.defaultSize,
                    height: Avatar.defaultSize,
                    child: Stack(
                      children: [
                        if (space != null)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Avatar(
                              border: BorderSide(
                                width: 2,
                                color: backgroundColor,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius / 4,
                              ),
                              mxContent: space.avatar,
                              size: Avatar.defaultSize * 0.75,
                              name: space.getLocalizedDisplayname(),
                              onTap: () => onLongPress?.call(context),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Avatar(
                            border: space == null
                                ? room.isSpace
                                      ? BorderSide(
                                          width: 1,
                                          color: theme.dividerColor,
                                        )
                                      : null
                                : BorderSide(width: 2, color: backgroundColor),
                            borderRadius: room.isSpace
                                ? BorderRadius.circular(
                                    AppConfig.borderRadius / 4,
                                  )
                                : null,
                            mxContent:
                                room.membership != .invite ||
                                    !AppSettings.hideAvatarsInInvites.value
                                ? room.avatar
                                : null,
                            size: space != null
                                ? Avatar.defaultSize * 0.75
                                : Avatar.defaultSize,
                            name: displayname,
                            presenceUserId: directChatMatrixId,
                            presenceBackgroundColor: backgroundColor,
                            onTap: () => onLongPress?.call(context),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => onLongPress?.call(context),
                            child: AnimatedScale(
                              duration: FluffyThemes.animationDuration,
                              curve: FluffyThemes.animationCurve,
                              scale: listTileHovered ? 1.0 : 0.0,
                              child: Material(
                                color: backgroundColor,
                                borderRadius: BorderRadius.circular(16),
                                child: const Icon(
                                  Icons.arrow_drop_down_circle_outlined,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              title: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      displayname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        fontWeight: unread || room.hasNewMessages
                            ? FontWeight.w500
                            : null,
                      ),
                    ),
                  ),
                  if (isMuted)
                    const Padding(
                      padding: EdgeInsets.only(left: 4.0),
                      child: Icon(Icons.notifications_off_outlined, size: 16),
                    ),
                  if (room.isLowPriority)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.low_priority,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (room.isFavourite)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.push_pin,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (!room.isSpace && room.membership != Membership.invite)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        room.latestEventReceivedTime.localizedTimeShort(
                          context,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (typingText.isEmpty &&
                      ownMessage &&
                      room.lastEvent?.status.isSending == true) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                    const SizedBox(width: 4),
                  ],
                  AnimatedContainer(
                    width: typingText.isEmpty ? 0 : 18,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.edit_outlined,
                      color: theme.colorScheme.secondary,
                      size: 14,
                    ),
                  ),
                  Expanded(
                    child: room.isSpace && room.membership == Membership.join
                        ? Text(
                            L10n.of(context).countChatsAndCountParticipants(
                              room.spaceChildrenCount,
                              (room.summary.mJoinedMemberCount ?? 1),
                            ),
                            style: TextStyle(color: theme.colorScheme.outline),
                            // Added overflow handling here for safety
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : typingText.isNotEmpty
                        ? Text(
                            typingText,
                            style: TextStyle(color: theme.colorScheme.primary),
                            maxLines: 1,
                            softWrap: false,
                            // Added overflow handling here for safety
                            overflow: TextOverflow.ellipsis,
                          )
                        : FutureBuilder(
                            key: ValueKey(
                              '${lastEvent?.eventId}_${lastEvent?.type}_${lastEvent?.redacted}',
                            ),
                            future: needLastEventSender
                                ? lastEvent.calcLocalizedBodyCached(
                                    MatrixLocals(L10n.of(context)),
                                    hideReply: true,
                                    hideEdit: true,
                                    plaintextBody: true,
                                    removeMarkdown: false,
                                    withSenderNamePrefix:
                                        (!isDirectChat ||
                                        directChatMatrixId !=
                                            room.lastEvent?.senderId),
                                  )
                                : null,
                            initialData: lastEvent
                                ?.calcLocalizedBodyFallbackCached(
                                  MatrixLocals(L10n.of(context)),
                                  hideReply: true,
                                  hideEdit: true,
                                  plaintextBody: true,
                                  removeMarkdown: true,
                                  withSenderNamePrefix: !isDirectChat,
                                ),
                            builder: (context, snapshot) => Row(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 2,
                              children: [
                                if (room.membership == Membership.join &&
                                    ownMessage)
                                  Icon(
                                    lastEvent!.receipts
                                            .where(
                                              (receipt) =>
                                                  room.directChatMatrixID ==
                                                      null
                                                  ? receipt.user.id !=
                                                        client.userID!
                                                  : receipt.user.id ==
                                                        room.directChatMatrixID,
                                            )
                                            .isNotEmpty
                                        ? Icons.done_all
                                        : Icons.done,
                                    size: 16,
                                    color: theme.colorScheme.outline,
                                  ),
                                Flexible(
                                  child: Text(
                                    room.membership == Membership.invite
                                        ? room
                                                  .getState(
                                                    EventTypes.RoomMember,
                                                    room.client.userID!,
                                                  )
                                                  ?.content
                                                  .tryGet<String>('reason') ??
                                              (isDirectChat
                                                  ? L10n.of(
                                                      context,
                                                    ).newChatRequest
                                                  : L10n.of(
                                                      context,
                                                    ).inviteGroupChat)
                                        : snapshot.data ??
                                              L10n.of(context).noMessagesYet,
                                    softWrap: false,
                                    maxLines: room.notificationCount >= 1
                                        ? 2
                                        : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: unread || room.hasNewMessages
                                          ? theme.colorScheme.onSurface
                                          : theme.colorScheme.outline,
                                      decoration:
                                          room.lastEvent?.redacted == true
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  UnreadBubble(room: room),
                ],
              ),
              onTap: onTap,
              trailing: onForget == null
                  ? room.membership == Membership.invite
                        ? IconButton(
                            tooltip: L10n.of(context).decline,
                            icon: const Icon(Icons.delete_forever_outlined),
                            color: theme.colorScheme.error,
                            onPressed: () async {
                              final consent = await showOkCancelAlertDialog(
                                context: context,
                                title: L10n.of(context).decline,
                                message: L10n.of(context).areYouSure,
                                okLabel: L10n.of(context).yes,
                                isDestructive: true,
                              );
                              if (consent != OkCancelResult.ok) return;
                              if (!context.mounted) return;
                              await showFutureLoadingDialog(
                                context: context,
                                future: room.leave,
                              );
                            },
                          )
                        : null
                  : IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      onPressed: onForget,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
