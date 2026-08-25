import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat_list/navi_rail_item.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:extera_next/utils/stream_extension.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/matrix.dart';

class SpacesNavigationRail extends StatefulWidget {
  final String? activeSpaceId;
  final void Function() onGoToChats;
  final void Function(String) onGoToSpaceId;
  final List<Room> rootSpaces;

  const SpacesNavigationRail({
    required this.activeSpaceId,
    required this.onGoToChats,
    required this.onGoToSpaceId,
    required this.rootSpaces,
    super.key,
  });

  @override
  State<SpacesNavigationRail> createState() => _SpacesNavigationRailState();
}

class _SpacesNavigationRailState extends State<SpacesNavigationRail> {
  /// Composed once per client so the StreamBuilder below keeps a single
  /// subscription across rebuilds instead of resubscribing per setState.
  Stream<bool>? _syncStream;
  Client? _boundClient;

  Stream<bool> _getSyncStream(Client client) {
    if (!identical(client, _boundClient)) {
      _boundClient = client;
      _syncStream = client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1));
    }
    return _syncStream!;
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final isSettings =
        GoRouter.of(context).routeInformationProvider.value.uri.path.startsWith(
          '/rooms/settings',
        ) &&
        FluffyThemes.isColumnMode(context);
    // workaround on settings button remaining selected.
    // who will even see it selected on mobile?
    return StreamBuilder(
      key: ValueKey(client.userID.toString()),
      stream: _getSyncStream(client),
      builder: (context, snapshot) {
        // Single pass over all rooms per rebuild: every badge used to run
        // its own full O(rooms) scan, so the rail cost was multiplied by
        // the number of items.
        final rootSpaces = widget.rootSpaces;
        const allChatsKey = '';
        final unreadCounts = <String, int>{allChatsKey: 0};
        for (final id in rootSpaces) {
          unreadCounts[id.id] = 0;
        }
        final roomOwnerSpaceIds = <String, List<String>>{};
        for (final space in rootSpaces) {
          for (final childId in space.spaceChildren.map((c) => c.roomId)) {
            if (childId == null) continue;
            roomOwnerSpaceIds.putIfAbsent(childId, () => []).add(space.id);
          }
        }
        for (final room in client.rooms) {
          if (!(room.isUnread || room.membership == Membership.invite)) {
            continue;
          }
          unreadCounts[allChatsKey] = unreadCounts[allChatsKey]! + 1;
          final owners = roomOwnerSpaceIds[room.id];
          if (owners != null) {
            for (final id in owners) {
              unreadCounts[id] = unreadCounts[id]! + 1;
            }
          }
        }
        return Container(
          width: FluffyThemes.navRailWidth,
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.vertical,
                    itemCount: widget.rootSpaces.length + 2,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return NaviRailItem(
                          isSelected:
                              widget.activeSpaceId == null && !isSettings,
                          onTap: widget.onGoToChats,
                          icon: const Padding(
                            padding: EdgeInsets.all(10.0),
                            child: Icon(Icons.forum_outlined),
                          ),
                          selectedIcon: const Padding(
                            padding: EdgeInsets.all(10.0),
                            child: Icon(Icons.forum),
                          ),
                          toolTip: L10n.of(context).chats,
                          unreadBadgeCount: unreadCounts[allChatsKey],
                        );
                      }
                      i--;
                      if (i == widget.rootSpaces.length) {
                        return NaviRailItem(
                          isSelected: false,
                          onTap: () => context.go('/rooms/newspace'),
                          icon: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(Icons.add),
                          ),
                          toolTip: L10n.of(context).createNewSpace,
                        );
                      }
                      final space = widget.rootSpaces[i];
                      final displayname = widget.rootSpaces[i]
                          .getLocalizedDisplayname(
                            MatrixLocals(L10n.of(context)),
                          );
                      return NaviRailItem(
                        toolTip: displayname,
                        isSelected: widget.activeSpaceId == space.id,
                        onTap: () =>
                            widget.onGoToSpaceId(widget.rootSpaces[i].id),
                        unreadBadgeCount: unreadCounts[space.id],
                        icon: Avatar(
                          mxContent: widget.rootSpaces[i].avatar,
                          name: displayname,
                          border: BorderSide(
                            width: 1,
                            color: Theme.of(context).dividerColor,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppConfig.borderRadius / 2,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                NaviRailItem(
                  isSelected: isSettings,
                  onTap: () => context.go('/rooms/settings'),
                  icon: const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: Icon(Icons.settings_outlined),
                  ),
                  selectedIcon: const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: Icon(Icons.settings),
                  ),
                  toolTip: L10n.of(context).settings,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// class _SpacesNavigationRailState extends State<SpacesNavigationRail> {
//   List<Room>? _cachedRootSpaces;

//   List<Room> _computeRootSpaces(Client client) {
//     final allSpaces = client.rooms.where((room) => room.isSpace).toList();

//     // Build a set of all space IDs that are children of another space.
//     // This is O(n * m) where n = spaces, m = avg children per space,
//     // instead of the previous O(n^2 * m) nested .any() approach.
//     final childSpaceIds = <String>{};
//     for (final space in allSpaces) {
//       for (final child in space.spaceChildren) {
//         final roomId = child.roomId;
//         if (roomId != null) {
//           childSpaceIds.add(roomId);
//         }
//       }
//     }

//     // O(n) set lookup per space
//     return allSpaces
//         .where((space) => !childSpaceIds.contains(space.id))
//         .toList();
//   }

// }
