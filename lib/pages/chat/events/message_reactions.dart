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
        ...reactionList.map(
          (r) => _Reaction(
            reactionKey: r.key,
            count: r.count,
            reacted: r.reacted,
            translucencyEffect: translucencyEffect,
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
            onLongPress: () async => await _AdaptiveReactorsDialog(
              client: client,
              timeline: timeline,
              reactionEntry: r,
              chatController: chatController,
            ).show(context),
          ),
        ),
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

  const _Reaction({
    required this.reactionKey,
    required this.count,
    required this.reacted,
    required this.onTap,
    required this.onLongPress,
    this.translucencyEffect = false,
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

class _AdaptiveReactorsDialog extends StatelessWidget {
  final Client? client;
  final _ReactionEntry? reactionEntry;
  final ChatController? chatController;
  final Timeline? timeline;

  const _AdaptiveReactorsDialog({
    this.client,
    this.timeline,
    this.chatController,
    this.reactionEntry,
  });

  Future<bool?> show(BuildContext context) => showAdaptiveBottomSheet(
    context: context,
    builder: (context) => this,
    useRootNavigator: false,
  );

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
    final reactionEvents = reactionEntry!.reactionEvents;

    if (reactionEvents == null) {
      return Text("reactionEvents == null");
    }

    final title = reactionEntry!.key.startsWith('mxc://')
        ? MxcImage(uri: Uri.parse(reactionEntry!.key), width: 32, height: 32)
        : AnimatedEmojiText(reactionEntry!.key);

    return Scaffold(
      appBar: AppBar(title: title),
      body: Center(
        child: Padding(
          padding: const .all(8),
          child: Material(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            color: theme.colorScheme.surfaceContainerHigh,
            clipBehavior: .hardEdge,
            child: CustomScrollView(
              slivers: [
                SliverList.builder(
                  itemBuilder: (context, i) {
                    final event = reactionEvents[i];
                    final user = event.senderFromMemoryOrFallback;
                    final canReact =
                        timeline != null &&
                        !event.redacted &&
                        event.room.canSendEvent(EventTypes.Reaction);

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
                          visualDensity: .compact,
                          onTap: canReact
                              ? () => _addReaction(context, event)
                              : null,
                          trailing: !canReact && chatController == null
                              ? null
                              : Row(
                                  mainAxisSize: .min,
                                  children: [
                                    if (canReact)
                                      IconButton(
                                        tooltip: L10n.of(
                                          context,
                                        ).customReaction,
                                        onPressed: () =>
                                            _addReaction(context, event),
                                        icon: const Icon(
                                          Icons.add_reaction_outlined,
                                        ),
                                      ),
                                    if (chatController != null)
                                      IconButton(
                                        onPressed: () {
                                          chatController?.replyAction(event);
                                          Navigator.of(context).pop();
                                        },
                                        icon: const Icon(Icons.reply_outlined),
                                      ),
                                    if (chatController != null &&
                                        event.canRedact)
                                      IconButton(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          chatController?.redactEventsAction(
                                            event: event,
                                          );
                                        },
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
                              padding: const .symmetric(horizontal: 16),
                              child: MessageReactions(
                                event,
                                timeline!,
                                chatController: chatController,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                  itemCount: reactionEvents.length,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
