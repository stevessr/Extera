import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/chat.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/animated_emoji.dart';
import 'package:extera_next/utils/date_time_extension.dart';
import 'package:extera_next/utils/emoji_picker_recent.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/emoji_picker.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/multi_hole_clipper.dart';
import 'package:extera_next/widgets/mxc_image.dart';

typedef _OpenReactionDetails = void Function(
  Event targetEvent,
  String reactionKey,
);

class MessageReactions extends StatelessWidget {
  final Event event;
  final Timeline timeline;
  final ChatController? chatController;
  final _OpenReactionDetails? onOpenDetails;

  const MessageReactions(
    this.event,
    this.timeline, {
    this.chatController,
    this.onOpenDetails,
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
          );
        }
        reactionMap[key]!.count++;
        reactionMap[key]!.reacted |= e.senderId == e.room.client.userID;
      }
    }

    final reactionList = reactionMap.values.toList()
      ..sort((a, b) {
        final countCompare = b.count.compareTo(a.count);
        return countCompare != 0 ? countCompare : a.key.compareTo(b.key);
      });
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
              final nestedDetails = onOpenDetails;
              if (nestedDetails != null) {
                nestedDetails(event, r.key);
                return;
              }
              if (chatController?.reactionsMenuOpen == true) return;
              await _AdaptiveReactorsDialog(
                client: client,
                timeline: timeline,
                targetEvent: event,
                selectedReactionKey: r.key,
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
        : AnimatedEmojiText(
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

  _ReactionEntry({
    required this.key,
    required this.count,
    required this.reacted,
  });
}

class _ReactionDetailsLevel {
  final Event targetEvent;
  final String reactionKey;

  const _ReactionDetailsLevel({
    required this.targetEvent,
    required this.reactionKey,
  });

  String get identity => '${targetEvent.eventId}\u0000$reactionKey';
}

class _AdaptiveReactorsDialog {
  final Client? client;
  final Event targetEvent;
  final String selectedReactionKey;
  final ChatController? chatController;
  final Timeline? timeline;
  final GlobalKey reactionKey;

  const _AdaptiveReactorsDialog({
    this.client,
    this.timeline,
    this.chatController,
    required this.targetEvent,
    required this.selectedReactionKey,
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
          targetEvent: targetEvent,
          selectedReactionKey: selectedReactionKey,
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

class _ReactionsMenuBody extends StatefulWidget {
  final Client? client;
  final Event targetEvent;
  final String selectedReactionKey;
  final ChatController? chatController;
  final Timeline? timeline;
  final VoidCallback onClose;

  const _ReactionsMenuBody({
    this.client,
    this.timeline,
    this.chatController,
    required this.targetEvent,
    required this.selectedReactionKey,
    required this.onClose,
  });

  @override
  State<_ReactionsMenuBody> createState() => _ReactionsMenuBodyState();
}

class _ReactionsMenuBodyState extends State<_ReactionsMenuBody> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late List<_ReactionDetailsLevel> _levels;

  Timeline? get timeline => widget.timeline;
  ChatController? get chatController => widget.chatController;

  @override
  void initState() {
    super.initState();
    _levels = [
      _ReactionDetailsLevel(
        targetEvent: widget.targetEvent,
        reactionKey: widget.selectedReactionKey,
      ),
    ];
    final client = widget.client ?? widget.targetEvent.room.client;
    _subscriptions.add(
      client.onTimelineEvent.stream.listen(_onTimelineUpdate),
    );
    _subscriptions.add(
      client.onHistoryEvent.stream.listen(_onTimelineUpdate),
    );
  }

  @override
  void didUpdateWidget(_ReactionsMenuBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetEvent.eventId != widget.targetEvent.eventId ||
        oldWidget.selectedReactionKey != widget.selectedReactionKey) {
      _levels = [
        _ReactionDetailsLevel(
          targetEvent: widget.targetEvent,
          reactionKey: widget.selectedReactionKey,
        ),
      ];
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }

  void _onTimelineUpdate(dynamic update) {
    if (!mounted || update is! Event) return;
    if (update.roomId != widget.targetEvent.roomId) return;
    if (update.type != EventTypes.Reaction &&
        update.type != EventTypes.Redaction &&
        update.redacts == null) {
      return;
    }
    setState(() {});
  }

  void _openNestedDetails(Event targetEvent, String reactionKey) {
    final next = _ReactionDetailsLevel(
      targetEvent: targetEvent,
      reactionKey: reactionKey,
    );
    if (_levels.any((level) => level.identity == next.identity)) return;
    setState(() => _levels.add(next));
  }

  void _goBack() {
    if (_levels.length <= 1) return;
    setState(() => _levels.removeLast());
  }

  List<Event> _reactionEventsFor(_ReactionDetailsLevel level) {
    final currentTimeline = timeline;
    if (currentTimeline == null) return const [];
    return level.targetEvent
        .aggregatedEvents(currentTimeline, RelationshipTypes.reaction)
        .where(
          (event) =>
              event.content.tryGetMap('m.relates_to')?['key'] ==
              level.reactionKey,
        )
        .toList(growable: false);
  }

  Future<void> _addReaction(BuildContext context, Event targetEvent) async {
    if (timeline == null ||
        targetEvent.redacted ||
        !targetEvent.room.canSendEvent(EventTypes.Reaction)) {
      return;
    }

    final room = targetEvent.room;
    final imagePacks = room.getImagePacks(ImagePackUsage.emoticon);
    final recentEmojiEntries = room.client.recentEmojis.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final recentEmojis = recentEmojiEntries.map((entry) => entry.key).toList();
    final customCategories = imagePacks.entries
        .map(
          (entry) => CustomCategory(
            id: entry.key,
            name: entry.value.pack.displayName!,
            icon: MxcImage(
              uri: entry.value.images.values.first.url,
              width: 32,
              height: 32,
            ),
            emojis: entry.value.images.map(
              (name, content) => MapEntry(name, content.url.toString()),
            ),
          ),
        )
        .toList(growable: false);
    final recentPickerEmojis = buildRecentPickerEmojis(
      recent: recentEmojis,
      customCategories: customCategories,
    );

    final emoji = await showAdaptiveBottomSheet<String>(
      context: context,
      builder: (context) => Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(L10n.of(context).customReaction),
          leading: CloseButton(
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ),
        body: SizedBox(
          height: double.infinity,
          child: MatrixEmojiPicker(
            onEmojiSelected: (_, emoji) => Navigator.of(
              context,
            ).pop(emoji.customData ?? emoji.standardEmoji!.char),
            onBackspacePressed: () {},
            recentEmojis: recentPickerEmojis,
            customCategories: customCategories,
            customEmojiBuilder: (context, name, size) =>
                MxcImage(uri: Uri.parse(name), width: 32, height: 32),
          ),
        ),
      ),
      useRootNavigator: false,
    );

    if (emoji == null) {
      return;
    }

    final alreadyReacted = targetEvent
        .aggregatedEvents(timeline!, RelationshipTypes.reaction)
        .any(
          (event) =>
              event.senderId == room.client.userID &&
              event.content.tryGetMap('m.relates_to')?['key'] == emoji,
        );
    if (alreadyReacted) {
      return;
    }

    room.client.addRecentEmoji(emoji);
    await room.sendReaction(targetEvent.eventId, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = _levels.last;
    final reactionEvents = _reactionEventsFor(level);

    return Column(
      mainAxisSize: .min,
      spacing: 4,
      children: [
        Material(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
          color: theme.colorScheme.surfaceContainerHigh,
          clipBehavior: Clip.hardEdge,
          elevation: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_levels.length > 1)
                ListTile(
                  dense: true,
                  leading: IconButton(
                    onPressed: _goBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  title: Text(
                    level.reactionKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text('${_levels.length}'),
                ),
              Flexible(
                child: reactionEvents.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(L10n.of(context).oopsSomethingWentWrong),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: List.generate(reactionEvents.length, (i) {
                            final event = reactionEvents[i];
                            final user = event.senderFromMemoryOrFallback;
                            final canReact =
                                timeline != null &&
                                !event.redacted &&
                                event.room.canSendEvent(EventTypes.Reaction);
                            final canRedact =
                                event.canRedact && chatController != null;
                            final redact = canRedact
                                ? () {
                                    widget.onClose();
                                    chatController!.redactEventsAction(
                                      event: event,
                                    );
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
                                    event.originServerTs.localizedMessageTime(
                                      context,
                                    ),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  dense: !FluffyThemes.isColumnMode(context),
                                  onTap: chatController == null
                                      ? null
                                      : () {
                                          chatController!.replyAction(event);
                                          widget.onClose();
                                        },
                                  onLongPress: redact,
                                  trailing: !canReact && chatController == null
                                      ? null
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (canReact)
                                              IconButton(
                                                tooltip: L10n.of(
                                                  context,
                                                ).customReaction,
                                                onPressed: () => _addReaction(
                                                  context,
                                                  event,
                                                ),
                                                icon: const Icon(
                                                  Icons.add_reaction_outlined,
                                                ),
                                              ),
                                            if (chatController != null)
                                              IconButton(
                                                onPressed: () {
                                                  chatController!.replyAction(
                                                    event,
                                                  );
                                                  widget.onClose();
                                                },
                                                icon: const Icon(
                                                  Icons.reply_outlined,
                                                ),
                                              ),
                                            if (canRedact)
                                              IconButton(
                                                onPressed: redact,
                                                color: theme.colorScheme.error,
                                                icon: const Icon(Icons.close),
                                              ),
                                          ],
                                        ),
                                ),
                                if (timeline != null)
                                  SizedBox(
                                    width: double.infinity,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: MessageReactions(
                                        event,
                                        timeline!,
                                        chatController: chatController,
                                        onOpenDetails: _openNestedDetails,
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
        ),
        Align(
          alignment: .topLeft,
          child: Text(
            L10n.of(context).reactionUiTip,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
