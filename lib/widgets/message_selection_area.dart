import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:extera_next/utils/platform_infos.dart';

/// Keeps message text selectable without letting it swallow the right click.
///
/// [SelectableRegion] answers a secondary tap with its own copy / select all
/// toolbar, and wins the gesture arena against the message underneath it
/// because it sits on top. A right click on the text of a message would
/// therefore show that toolbar instead of the message context menu.
///
/// On desktop and web the toolbar is suppressed and the secondary click is
/// forwarded to [onSecondaryTap]. Mobile keeps the default behaviour: there the
/// toolbar is the only way to copy a selection, and the context menu opens on
/// long press anyway.
class MessageSelectionArea extends StatelessWidget {
  final Widget child;

  /// Called with the global position of a secondary (right) click.
  final void Function(Offset globalPosition)? onSecondaryTap;

  const MessageSelectionArea({
    required this.child,
    this.onSecondaryTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformInfos.isMobile) return SelectionArea(child: child);

    return Listener(
      // A `Listener` is not part of the gesture arena, so it sees the pointer
      // even though the selection region claims it.
      onPointerDown: (event) {
        if (event.buttons == kSecondaryButton) {
          onSecondaryTap?.call(event.position);
        }
      },
      child: SelectionArea(
        contextMenuBuilder: (context, selectableRegionState) =>
            const SizedBox.shrink(),
        child: child,
      ),
    );
  }
}
