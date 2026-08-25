import 'package:flutter/material.dart';

import 'package:badges/badges.dart' as b;
import 'package:matrix/matrix.dart';

import 'matrix.dart';

class UnreadRoomsBadge extends StatelessWidget {
  /// Precomputed count of matching unread rooms. When provided, the widget
  /// skips scanning all rooms on every rebuild — callers that rebuild every
  /// sync tick should compute counts once and pass them here.
  final int? count;
  final bool Function(Room)? filter;
  final b.BadgePosition? badgePosition;
  final Widget? child;

  const UnreadRoomsBadge({
    super.key,
    this.count,
    this.filter,
    this.badgePosition,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final unreadCount =
        count ??
        Matrix.of(context).client.rooms
            .where(
              (r) =>
                  (filter?.call(r) ?? true) &&
                  (r.isUnread || r.membership == Membership.invite),
            )
            .length;
    return b.Badge(
      badgeStyle: b.BadgeStyle(
        badgeColor: theme.colorScheme.primary,
        elevation: 4,
        borderSide: BorderSide(color: theme.colorScheme.surface, width: 2),
      ),
      badgeContent: Text(
        unreadCount.toString(),
        style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 12),
      ),
      showBadge: unreadCount != 0,
      badgeAnimation: const b.BadgeAnimation.scale(),
      position: badgePosition ?? b.BadgePosition.bottomEnd(),
      child: child,
    );
  }
}
