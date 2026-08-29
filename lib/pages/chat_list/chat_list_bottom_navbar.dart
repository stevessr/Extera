import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:badges/badges.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/pages/chat_list/chat_list.dart';
import 'package:extera_next/widgets/unread_rooms_badge.dart';

import '../../widgets/matrix.dart';

class ChatListBottomNavbar extends StatefulWidget {
  final ChatListController controller;
  final Widget? fab;

  const ChatListBottomNavbar(this.controller, {this.fab, super.key});

  @override
  State<ChatListBottomNavbar> createState() => _ChatListBottomNavbarState();
}

class _ChatListBottomNavbarState extends State<ChatListBottomNavbar> {
  ChatListController get _c => widget.controller;

  List<Room> spaces = [];
  Map<String, Room> spaceDelegateCandidates = {};

  @override
  void initState() {
    final client = Matrix.of(context).client;

    spaces = client.rooms.where((r) => r.isSpace).toList();
    for (final space in spaces) {
      for (final spaceChild in space.spaceChildren) {
        final roomId = spaceChild.roomId;
        if (roomId == null) continue;
        spaceDelegateCandidates[roomId] = space;
      }
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final filters = [
      if (AppSettings.separateChatTypes.value)
        ActiveFilter.messages
      else
        ActiveFilter.allChats,
      if (AppSettings.separateChatTypes.value) ActiveFilter.groups,
      ActiveFilter.unread,
      if (spaceDelegateCandidates.isNotEmpty &&
          !_c.widget.displayNavigationRail)
        ActiveFilter.spaces,
      if (AppSettings.enablePeopleTab.value) ActiveFilter.people,
    ];

    final filterLambdas = {
      ActiveFilter.allChats: (Room room) => true,
      ActiveFilter.messages: (Room room) => room.isDirectChat,
      ActiveFilter.groups: (Room room) => !room.isDirectChat,
      ActiveFilter.unread: (Room room) => room.isUnread,
      ActiveFilter.spaces: (Room room) => false,
      ActiveFilter.people: (Room room) => false,
    };

    final client = Matrix.of(context).client;
    // Single pass over all rooms per rebuild: every badge used to run its
    // own full O(rooms) scan, so the bar cost was multiplied by the
    // number of filters.
    final unreadCounts = <ActiveFilter, int>{
      for (final filter in filters) filter: 0,
    };
    for (final room in client.rooms) {
      if (!(room.isUnread || room.membership == Membership.invite)) {
        continue;
      }
      for (final filter in filters) {
        if (filterLambdas[filter]!(room)) {
          unreadCounts[filter] = unreadCounts[filter]! + 1;
        }
      }
    }

    final child = Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: filters.map((filter) {
          final isActive = _c.activeFilter == filter;

          final backgroundColor = isActive
              ? theme.colorScheme.surfaceContainerHighest
              : Colors.transparent;

          final foregroundColor = isActive
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurfaceVariant;

          return Expanded(
            key: ValueKey(filter),
            child: Padding(
              padding: const .all(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(124),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => _c.setActiveFilter(filter),
                    borderRadius: BorderRadius.circular(124),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isActive)
                            Icon(
                              filter.toIconData(false),
                              size: 20,
                              color: foregroundColor,
                            )
                          else
                            UnreadRoomsBadge(
                              filter: filterLambdas[filter]!,
                              count: unreadCounts[filter],
                              badgePosition: BadgePosition.topEnd(),
                              child: Icon(
                                filter.toIconData(true),
                                size: 20,
                                color: foregroundColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );

    return Row(
      mainAxisSize: .max,
      spacing: 8,
      children: [
        Flexible(
          flex: 1,
          child: AppSettings.enableChatFrostedGlass.value
              ? _FloatingShell(
                  child: Material(
                    borderRadius: BorderRadius.circular(128),
                    clipBehavior: Clip.hardEdge,
                    color: Colors.transparent,
                    child: child,
                  ),
                )
              : Material(
                  borderRadius: BorderRadius.circular(128),
                  clipBehavior: Clip.hardEdge,
                  color: theme.colorScheme.surfaceContainer,
                  child: child,
                ),
        ),
        widget.fab ?? const SizedBox.shrink(),
      ],
    );
  }
}

class _FloatingShell extends StatelessWidget {
  final Widget child;
  const _FloatingShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PhysicalModel(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.hardEdge,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: theme.colorScheme.surfaceContainerHigh.withAlpha(
                theme.brightness == Brightness.dark ? 160 : 190,
              ),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withAlpha(60),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(
                    theme.brightness == Brightness.dark ? 60 : 20,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
