import 'package:flutter/material.dart';

import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/chat.dart';
import 'package:extera_next/pages/chat/events/message.dart';
import 'package:extera_next/pages/chat/typing_indicators.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/room_status_extension.dart';

class ChatEventList extends StatelessWidget {
  final ChatController controller;
  final bool showThreadRoots;

  const ChatEventList({
    super.key,
    required this.controller,
    this.showThreadRoots = false,
  });

  static const Key _centerKey = ValueKey('center-sliver');

  @override
  Widget build(BuildContext context) {
    final timeline = controller.timeline;

    if (timeline == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final theme = Theme.of(context);

    final colors = [theme.secondaryBubbleColor, theme.bubbleColor];

    final latestReadEvent = controller.room.getLatestReadMessage(
      timeline,
      userID: controller
          .room
          .directChatMatrixID, // If in a DM, show double check mark only when read by second party. Bridged DMs may have bridge bots sending read marks after message delivery to remote platform
    );

    final horizontalPadding = FluffyThemes.isColumnMode(context) ? 8.0 : 0.0;

    final events = controller.filteredEvents;

    final threads = controller.room.threads;

    final hasWallpaper = AppSettings.wallpaperPath.value.isNotEmpty;

    final latestReadEventIndex = latestReadEvent != null
        ? events.indexWhere((event) => event.eventId == latestReadEvent)
        : -1;

    final newEventCount = controller.newEventCount.clamp(0, events.length);
    final centerEventCount = events.length - newEventCount;

    // Builds a Message widget for the event at [eventIndex] in filteredEvents.
    Widget buildEventTile(int eventIndex) {
      //print('Building event $eventIndex ${events[eventIndex].eventId}');
      final event = events[eventIndex];
      final animateIn =
          eventIndex == 0 &&
          (DateTime.now().millisecondsSinceEpoch -
                  event.originServerTs.millisecondsSinceEpoch) <
              1000 &&
          controller.firstUpdateReceived;

      final thread = threads.containsKey(event.eventId)
          ? threads[event.eventId]
          : null;

      return AutoScrollTag(
        key: ValueKey(event.transactionId ?? event.eventId),
        index: controller.autoScrollIndexForEvent(eventIndex),
        controller: controller.scrollController,
        child: RepaintBoundary(
          key: controller.eventGlobalKeys.putIfAbsent(
            event.transactionId ?? event.eventId,
            () => GlobalKey(),
          ),
          child: Message(
            event,
            animateIn: animateIn,
            thread: thread,
            layout: controller.layout,
            singleSelected:
                controller.selectedEvents.length == 1 &&
                controller.selectedEvents.first.eventId == event.eventId,
            onSwipe: controller.replyAction,
            hasBeenRead:
                latestReadEventIndex != -1 &&
                latestReadEventIndex <= eventIndex,
            onInfoTab: controller.showEventInfo,
            onMention: () => controller.sendController.text +=
                '${event.senderFromMemoryOrFallback.mention} ',
            highlightMarker: controller.scrollToEventIdMarker == event.eventId,
            onSelect: controller.onSelectMessage,
            scrollToEventId: controller.scrollToEventId,
            longPressSelect: controller.selectedEvents.isNotEmpty,
            selected: controller.selectedEvents.any(
              (e) => e.eventId == event.eventId,
            ),
            selectable:
                controller.selectedEvents.isNotEmpty ||
                controller.selectedEventId == event.eventId,
            timeline: timeline,
            displayReadMarker:
                eventIndex > 0 && controller.readMarkerEventId == event.eventId,
            nextEvent: eventIndex + 1 < events.length
                ? events[eventIndex + 1]
                : null,
            previousEvent: eventIndex > 0 ? events[eventIndex - 1] : null,
            wallpaperMode: hasWallpaper,
            colors: colors,
            gradient: AppSettings.enableGradient.value,
            chatController: controller,
          ),
        ),
      );
    }

    return CustomScrollView(
      controller: controller.scrollController,
      reverse: true,
      center: _centerKey,
      physics: controller.selectedEventId != null
          ? const NeverScrollableScrollPhysics()
          : null,
      keyboardDismissBehavior: PlatformInfos.isIOS
          ? ScrollViewKeyboardDismissBehavior.onDrag
          : ScrollViewKeyboardDismissBehavior.manual,
      slivers: [
        SliverToBoxAdapter(
          child: AutoScrollTag(
            key: const ValueKey('chat_bottom_padding'),
            index: ChatController.bottomPaddingAutoScrollIndex,
            controller: controller.scrollController,
            child: ValueListenableBuilder<double>(
              valueListenable: controller.inputBarHeight,
              builder: (context, height, _) => SizedBox(height: height + 8),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int i) {
              return buildEventTile(newEventCount - 1 - i);
            },
            childCount: newEventCount,
            findChildIndexCallback: controller.findNewEventsChildIndexCallback,
          ),
        ),
        SliverPadding(
          key: _centerKey,
          padding: .only(
            top: MediaQuery.of(context).padding.top + 16,
            left: horizontalPadding,
            right: horizontalPadding,
          ),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int i) {
                if (i == 0) {
                  if (timeline.canRequestFuture) {
                    return Center(
                      child: ElevatedButton(
                        onPressed: controller.requestFuture,
                        child: timeline.isRequestingFuture
                            ? const LinearProgressIndicator()
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.arrow_downward),
                                  const SizedBox(width: 5),
                                  Text(L10n.of(context).loadMore),
                                ],
                              ),
                      ),
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TypingIndicators(controller, layout: controller.layout),
                    ],
                  );
                }

                if (i == centerEventCount + 1) {
                  if (timeline.canRequestHistory) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      controller.requestHistory,
                    );
                    final hasScrollBanner =
                        controller.scrollUpBannerEventId != null;
                    return Padding(
                      padding: EdgeInsets.only(
                        top: hasScrollBanner ? 72.0 : 0.0,
                      ),
                      child: Center(
                        child: ElevatedButton(
                          onPressed: controller.requestHistory,
                          child: timeline.isRequestingHistory
                              ? const LinearProgressIndicator()
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.arrow_upward),
                                    const SizedBox(width: 5),
                                    Text(L10n.of(context).loadMore),
                                  ],
                                ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }

                // i in [1..centerEventCount]: event tiles.
                // Maps to filteredEvents[newEventCount + (i - 1)].
                final eventIndex = newEventCount + (i - 1);
                return buildEventTile(eventIndex);
              },
              // typing + centerEventCount events + history button
              childCount: centerEventCount + 2,
              findChildIndexCallback: controller.findChildIndexCallback,
            ),
          ),
        ),
      ],
    );
  }
}
