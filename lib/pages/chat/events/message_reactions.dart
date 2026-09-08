import 'dart:async';
import 'dart:ui';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/date_time_extension.dart';
import 'package:flutter/material.dart';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/pages/chat/chat.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/multi_hole_clipper.dart';
import 'package:extera_next/widgets/mxc_image.dart';

class MessageReactions extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final ChatController? chatController;

  const MessageReactions(
    this.event,
    this.timeline, {
    this.chatController,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final allReactionEvents = event.aggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final reactionMap = <String, _ReactionEntry>{};
    final client = Matrix.of(context).client;
    final translucencyEffect = AppSettings.enableChatFrostedGlass.value;
    final reactionGlobalKeys = <String, GlobalKey>{};

    for (final e in allReactionEvents) {
      final key = e.content
          .tryGetMap<String, dynamic>('m.relates_to')
          ?.tryGet<String>('key');
      if (key != null) {
        if (!reactionMap.containsKey(key)) {
          reactionMap[key] = _ReactionEntry(
            key: key,
            count: 0,
            reacted: false,
            reactionEvents: [],
          );
        }
        reactionMap[key]!.count++;
        reactionMap[key]!.reactionEvents!.add(e);
        reactionMap[key]!.reacted |= e.senderId == e.room.client.userID;
      }
    }

    final reactionList = reactionMap.values.toList();
    reactionList.sort((a, b) => b.count - a.count > 0 ? 1 : -1);
    final ownMessage = event.senderId == event.room.client.userID;
    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      alignment:
          (ownMessage &&
              chatController?.layout != .modern &&
              {
                EventTypes.Message,
                EventTypes.Sticker,
              }.contains(event.type)) // Nested reactions :)
          ? WrapAlignment.end
          : WrapAlignment.start,
      children: [
        ...reactionList.map((r) {
          reactionGlobalKeys[r.key] = GlobalKey();
          return _Reaction(
            reactionKey: r.key,
            count: r.count,
            reacted: r.reacted,
            translucencyEffect: translucencyEffect,
            chipKey: reactionGlobalKeys[r.key],
            onTap: () {
              if (r.reacted) {
                final evt = allReactionEvents.firstWhereOrNull(
                  (e) =>
                      e.senderId == e.room.client.userID &&
                      e.content.tryGetMap('m.relates_to')?['key'] == r.key,
                );
                if (evt != null) {
                  showFutureLoadingDialog(
                    context: context,
                    future: () => evt.redactEvent(),
                  );
                }
              } else {
                event.room.sendReaction(event.eventId, r.key);
              }
            },
            onLongPress: () async {
              if (chatController?.reactionsMenuOpen == true) return;
              await _AdaptiveReactorsDialog(
                client: client,
                timeline: timeline,
                reactionEntry: r,
                chatController: chatController,
                reactionKey: reactionGlobalKeys[r.key]!,
              ).show(context);
            },
          );
        }),
        if (allReactionEvents.any((e) => e.status.isSending))
          const SizedBox(
            width: 24,
            height: 24,
            child: Padding(
              padding: EdgeInsets.all(4.0),
              child: CircularProgressIndicator.adaptive(strokeWidth: 1),
            ),
          ),
      ],
    );
  }
}

class _Reaction extends StatelessWidget {
  final String reactionKey;
  final int count;
  final bool? reacted;
  final void Function()? onTap;
  final void Function()? onLongPress;
  final bool translucencyEffect;
  final GlobalKey? chipKey;

  const _Reaction({
    required this.reactionKey,
    required this.count,
    required this.reacted,
    required this.onTap,
    required this.onLongPress,
    this.translucencyEffect = false,
    this.chipKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    final color = reacted == true
        ? theme.bubbleColor
        : theme.colorScheme.surfaceContainerHigh;
    Widget content;

    var renderKey = Characters(reactionKey);
    if (renderKey.length > 10) {
      renderKey = renderKey.getRange(0, 9) + Characters('…');
    }

    final reactionIcon = reactionKey.startsWith('mxc://')
        ? MxcImage(
            uri: Uri.parse(reactionKey),
            width: 20,
            height: 20,
            animated: true,
            isThumbnail: false,
          )
        : Text(
            renderKey.toString(),
            style: TextStyle(
              color: reacted == true ? theme.onBubbleColor : textColor,
              fontSize: DefaultTextStyle.of(context).style.fontSize,
            ),
            textScaler: const TextScaler.linear(1.2),
          );

    content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        reactionIcon,
        const SizedBox(width: 8),
        Text(
          count.toString(),
          style: TextStyle(
            color: textColor,
            fontSize: DefaultTextStyle.of(context).style.fontSize,
            fontWeight: .bold,
          ),
          textScaler: const TextScaler.linear(1.1),
        ),
      ],
    );

    return InkWell(
      onTap: () => onTap != null ? onTap!() : null,
      onLongPress: () => onLongPress != null ? onLongPress!() : null,
      onSecondaryTap: () => onLongPress != null
          ? onLongPress!()
          : null, // It is better to make it a seperate option
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      child: Container(
        key: chipKey,
        decoration: BoxDecoration(
          color: translucencyEffect ? color.withValues(alpha: 0.7) : color,
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: content,
      ),
    );
  }
}

class _ReactionEntry {
  String key;
  int count;
  bool reacted;
  List<Event>? reactionEvents;

  _ReactionEntry({
    required this.key,
    required this.count,
    required this.reacted,
    this.reactionEvents,
  });
}

class _AdaptiveReactorsDialog {
  final Client? client;
  final _ReactionEntry? reactionEntry;
  final ChatController? chatController;
  final Timeline? timeline;
  final GlobalKey reactionKey;

  const _AdaptiveReactorsDialog({
    this.client,
    this.timeline,
    this.chatController,
    this.reactionEntry,
    required this.reactionKey,
  });

  Future<bool?> show(BuildContext context) async {
    final overlay = Overlay.of(context, rootOverlay: true);
    final route = ModalRoute.of(context);
    OverlayEntry? entry;
    LocalHistoryEntry? historyEntry;
    final completer = Completer<bool?>();
    var closed = false;

    void closeOverlay([bool? result]) {
      if (closed) return;
      closed = true;
      entry?.remove();
      entry = null;
      chatController?.setReactionsMenuOpen(false);
      if (!completer.isCompleted) completer.complete(result);
    }

    void remove([bool? result]) {
      if (closed) return;
      if (historyEntry != null) {
        final he = historyEntry!;
        historyEntry = null;
        route?.removeLocalHistoryEntry(he);
      } else {
        closeOverlay(result);
      }
    }

    historyEntry = LocalHistoryEntry(onRemove: () => closeOverlay());
    route?.addLocalHistoryEntry(historyEntry!);

    entry = OverlayEntry(
      builder: (context) => _ReactionsContextMenuOverlay(
        reactionKey: reactionKey,
        onDismiss: () => remove(),
        onOpen: () => chatController?.setReactionsMenuOpen(true),
        child: _ReactionsMenuBody(
          client: client,
          timeline: timeline,
          reactionEntry: reactionEntry,
          chatController: chatController,
          onClose: () => remove(),
        ),
      ),
    );

    overlay.insert(entry!);
    return completer.future;
  }
}

class _ReactionsContextMenuOverlay extends StatefulWidget {
  final GlobalKey reactionKey;
  final void Function() onDismiss;
  final void Function() onOpen;
  final Widget child;

  const _ReactionsContextMenuOverlay({
    required this.reactionKey,
    required this.onDismiss,
    required this.onOpen,
    required this.child,
  });

  @override
  State<_ReactionsContextMenuOverlay> createState() =>
      _ReactionsContextMenuOverlayState();
}

class _ReactionsContextMenuOverlayState
    extends State<_ReactionsContextMenuOverlay>
    with WidgetsBindingObserver {
  Rect? _reactionRect;
  Timer? _pollTimer;
  double? _initialBottomInset;
  bool _metricsReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initialBottomInset = MediaQuery.of(context).viewInsets.bottom;
      _metricsReady = true;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ReactionsContextMenuOverlay old) {
    super.didUpdateWidget(old);
    if (widget.reactionKey != old.reactionKey) {
      _startPolling();
    }
  }

  @override
  void didChangeMetrics() {
    if (!_metricsReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _initialBottomInset == null) return;
      final currentBottomInset = MediaQuery.of(context).viewInsets.bottom;
      if ((currentBottomInset - _initialBottomInset!).abs() > 1) {
        widget.onDismiss();
      }
    });
  }

  void _startPolling({Duration duration = const Duration(milliseconds: 900)}) {
    _pollTimer?.cancel();
    final endTime = DateTime.now().add(duration);
    _pollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _measure();
      if (DateTime.now().isAfter(endTime)) {
        timer.cancel();
      }
    });
  }

  void _measure() {
    final ctx = widget.reactionKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;

    final pos = box.localToGlobal(Offset.zero);
    final rect = Rect.fromLTWH(pos.dx, pos.dy, box.size.width, box.size.height);

    if (rect != _reactionRect) {
      setState(() {
        _reactionRect = rect;
        widget.onOpen();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            GestureDetector(
              onTap: widget.onDismiss,
              behavior: HitTestBehavior.translucent,
              child: ClipPath(
                clipper: MultiHoleClipper(
                  holes: [?_reactionRect],
                  radius: Radius.circular(AppConfig.borderRadius),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: AnimatedOpacity(
                    opacity: _reactionRect == null ? 0 : 1,
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            CustomSingleChildLayout(
              delegate: _ReactionsMenuLayoutDelegate(rect: _reactionRect),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.1, end: 1.0),
                duration: FluffyThemes.animationDuration,
                curve: FluffyThemes.animationCurve,
                builder: (context, value, child) {
                  return Opacity(opacity: value, child: child);
                },
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReactionsMenuLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect? rect;

  _ReactionsMenuLayoutDelegate({required this.rect});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest).enforce(
      BoxConstraints(
        maxWidth: 360,
        maxHeight: constraints.biggest.height * 0.6,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final r = rect;
    if (r == null) return Offset.zero;
    const margin = 10.0;
    var left = r.center.dx - childSize.width / 2;
    if (left + childSize.width > size.width - margin) {
      left = size.width - childSize.width - margin;
    }
    if (left < margin) left = margin;
    var top = r.bottom + margin;
    if (top + childSize.height > size.height - margin) {
      top = r.top - margin - childSize.height;
    }
    if (top < margin) top = margin;
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_ReactionsMenuLayoutDelegate oldDelegate) {
    return rect != oldDelegate.rect;
  }
}

class _ReactionsMenuBody extends StatelessWidget {
  final Client? client;
  final _ReactionEntry? reactionEntry;
  final ChatController? chatController;
  final Timeline? timeline;
  final VoidCallback onClose;

  const _ReactionsMenuBody({
    this.client,
    this.timeline,
    this.chatController,
    this.reactionEntry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reactionEvents = reactionEntry!.reactionEvents;

    if (reactionEvents == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(L10n.of(context).oopsSomethingWentWrong),
      );
    }

    return Material(
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      color: theme.colorScheme.surfaceContainerHigh,
      clipBehavior: Clip.hardEdge,
      elevation: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: List.generate(reactionEvents.length, (i) {
                  final event = reactionEvents[i];
                  final user = event.senderFromMemoryOrFallback;
                  final canRedact = event.canRedact && chatController != null;
                  final redact = canRedact
                      ? () {
                          onClose();
                          chatController!.redactEventsAction(event: event);
                        }
                      : null;

                  return Column(
                    children: [
                      ListTile(
                        leading: Avatar(
                          mxContent: user.avatarUrl,
                          size: 32,
                          name: user.displayName ?? user.id,
                          key: ValueKey(user.id),
                        ),
                        title: Text(user.displayName ?? user.id),
                        subtitle: Text(
                          event.originServerTs.localizedMessageTime(context),
                        ),
                        visualDensity: VisualDensity.compact,
                        dense: !FluffyThemes.isColumnMode(context),
                        onTap: chatController == null
                            ? null
                            : () {
                                chatController!.replyAction(event);
                                onClose();
                              },
                        onLongPress: redact,
                      ),
                      if (timeline != null)
                        SizedBox(
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: MessageReactions(
                              event,
                              timeline!,
                              chatController: chatController,
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
