import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/chat_view.dart';
import 'package:extera_next/pages/chat/event_info_dialog.dart';
import 'package:extera_next/pages/chat/events/message.dart';
import 'package:extera_next/pages/chat/message_context_menu.dart';
import 'package:extera_next/pages/chat/message_edits_dialog.dart';
import 'package:extera_next/pages/chat/recovered_event_dialog.dart';
import 'package:extera_next/pages/chat/seen_by_row.dart';
import 'package:extera_next/pages/chat/send_poll_dialog.dart';
import 'package:extera_next/pages/chat/translated_event_dialog.dart';
import 'package:extera_next/pages/chat/trust_user_key_dialog.dart';
import 'package:extera_next/pages/chat/vote_results_dialog.dart';
import 'package:extera_next/pages/chat_details/chat_details.dart';
import 'package:extera_next/pages/dialer/livekit_call_screen.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/clipboard_utils.dart';
import 'package:extera_next/utils/content_warning.dart';
import 'package:extera_next/utils/error_reporter.dart';
import 'package:extera_next/utils/file_selector.dart';
import 'package:extera_next/utils/loading_snackbar_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/synapse_admin_extension.dart';
import 'package:extera_next/utils/neurogate.dart';
import 'package:extera_next/utils/other_party_can_receive.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/privacy_options.dart';
import 'package:extera_next/utils/room_status_extension.dart';
import 'package:extera_next/utils/show_scaffold_dialog.dart';
import 'package:extera_next/utils/stream_extension.dart';
import 'package:extera_next/utils/web_drop/web_drop.dart';
import 'package:extera_next/widgets/adaptive_dialogs/image_editor_dialog.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:extera_next/widgets/emoji_picker.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/future_loading_snackbar.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/multi_hole_clipper.dart';
import 'package:extera_next/widgets/share_scaffold_dialog.dart';
import '../../utils/account_bundles.dart';
import '../../utils/localized_exception_extension.dart';
import '../../utils/memoized_tile_cache.dart';
import '../../utils/resize_video.dart';
import 'send_file_dialog.dart';
import 'send_location_dialog.dart';

/// Immutable snapshot of every input [ChatEventList] feeds into a message
/// tile. Records compare structurally, so an unchanged snapshot proves the
/// previously built [Message] widget can be reused verbatim, letting Flutter
/// skip the entire bubble subtree rebuild.
///
/// Callbacks are deliberately excluded: they only capture the controller and
/// the event, both of which are covered here.
typedef ChatTileDeps = ({
  Event event,
  Event? nextEvent,
  Event? previousEvent,
  Timeline timeline,
  Thread? thread,
  MessageLayout layout,
  Color secondaryBubbleColor,
  Color bubbleColor,
  bool animateIn,
  bool selected,
  bool singleSelected,
  bool longPressSelect,
  bool selectable,
  bool hasBeenRead,
  bool displayReadMarker,
  bool highlightMarker,
  bool wallpaperMode,
  bool gradient,
  // Settings read synchronously inside bubble builds; captured as values so
  // a changed setting invalidates cached tiles without any listener wiring.
  bool autoplayImages,
  String chatFallbackFonts,
  String chatFont,
  bool enableChatFrostedGlass,
  double fontSizeFactor,
  bool latexMath,
  double messageFontSize,
  String monospaceFallbackFonts,
  String monospaceFont,
  bool notoEmojiFont,
  bool renderHtml,
  double stickerScale,
  bool swipeRightToLeftToReply,
  bool systemFont,
  int memberStateVersion,
});

class ChatPage extends StatelessWidget {
  final String roomId;
  final List<ShareItem>? shareItems;
  final String? eventId;
  final bool? showThreadRoots;

  const ChatPage({
    super.key,
    required this.roomId,
    this.eventId,
    this.shareItems,
    this.showThreadRoots,
  });

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(context).client.getRoomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
          ),
        ),
      );
    }

    return ChatPageWithRoom(
      key: Key('chat_page_${roomId}_$eventId'),
      room: room,
      shareItems: shareItems,
      eventId: eventId,
      showThreadRoots: showThreadRoots,
    );
  }
}

class ChatPageWithRoom extends StatefulWidget {
  final Room room;
  final Thread? thread;
  final List<ShareItem>? shareItems;
  final String? eventId;
  final bool? showThreadRoots;

  const ChatPageWithRoom({
    super.key,
    required this.room,
    this.thread,
    this.shareItems,
    this.eventId,
    this.showThreadRoots,
  });

  @override
  ChatController createState() => ChatController();
}

class ChatController extends State<ChatPageWithRoom>
    with WidgetsBindingObserver {
  Room get room => sendingClient.getRoomById(roomId) ?? widget.room;
  bool get showThreadRoots => (widget.showThreadRoots ?? false);
  Thread? get thread =>
      sendingClient.getRoomById(roomId)?.threads[threadRootEventId] ??
      widget.room.threads[threadRootEventId];

  MessageLayout _layout = .bubbles;
  MessageLayout get layout => _layout;

  late Client sendingClient;

  Timeline? timeline;

  late final String readMarkerEventId;

  String get roomId => widget.room.id;
  String? get threadRootEventId => widget.thread?.rootEvent.eventId;

  final AutoScrollController scrollController = AutoScrollController();

  /// Tracks the actual rendered height of the floating input bar so the
  /// message list can reserve the correct amount of bottom padding.
  final ValueNotifier<double> inputBarHeight = ValueNotifier<double>(88);

  late final FocusNode inputFocus;

  Timer? typingCoolDown;
  Timer? typingTimeout;
  bool currentlyTyping = false;
  bool dragging = false;

  /// Dispose callback for the web-specific drag-and-drop DOM listeners.
  /// Non-null only on web.
  VoidCallback? _disposeWebDropListener;

  List<String> eventsToScrollBackTo = [];

  void onDragEntered(_) => setState(() => dragging = true);

  void onDragExited(_) => setState(() => dragging = false);

  void onDragDone(DropDoneDetails details) async {
    setState(() => dragging = false);
    await _showSendFileDialog(details.files);
  }

  // On web the `desktop_drop` package's `DropTarget` widget gates
  // `onDragDone` on an internal drag-status that resets to idle on every
  // spurious `dragleave` event (DOM bubbling fires one whenever the pointer
  // crosses child elements).  The status is often idle when `drop` arrives,
  // so the callback is silently skipped.  We bypass the widget entirely by
  // registering our own DOM listeners with a proper enter/leave counter.
  void _onWebDragState(bool isDragging) =>
      setState(() => dragging = isDragging);

  void _onWebDrop(List<XFile> files) async {
    setState(() => dragging = false);
    await _showSendFileDialog(files);
  }

  Future<void> _showSendFileDialog(List<XFile> files) async {
    if (files.isEmpty) return;

    await showAdaptiveDialog(
      context: context,
      useRootNavigator: false,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        thread: thread,
        replyEvent: replyEvent,
        outerContext: context,
      ),
    );
  }

  bool get canSaveSelectedEvent =>
      selectedEvents.length == 1 &&
      {
        MessageTypes.Video,
        MessageTypes.Image,
        MessageTypes.Sticker,
        MessageTypes.Audio,
        MessageTypes.File,
      }.contains(selectedEvents.single.messageType);

  void saveSelectedEvent(BuildContext context) =>
      selectedEvents.single.saveFile(context);

  List<Event> selectedEvents = [];

  final Set<String> unfolded = {};

  Event? replyEvent;
  bool replyMention = true;

  Event? editEvent;

  /// Replacement attachment for the image message currently being edited.
  ///
  /// Stays `null` as long as the user only edits the caption, in which case the
  /// original attachment is reused instead of being uploaded again.
  MatrixImageFile? editImageFile;

  /// Content warning to store with the image message currently being edited.
  ///
  /// Initialized from the message, so that editing only the caption keeps the
  /// warning it already had.
  String? editContentWarning;

  /// The content warning the message had when the edit started, used to tell
  /// whether the user actually changed something.
  String? _originalContentWarning;

  /// Whether the message currently being edited is an image message, so that
  /// the attachment and its content warning can be edited as well.
  bool get isEditingImage =>
      editEvent != null && editEvent!.messageType == MessageTypes.Image;

  void setEditContentWarning(String? type) => setState(() {
    editContentWarning = type;
  });

  final ValueNotifier<bool> _scrolledUp = ValueNotifier<bool>(false);

  bool get showScrollDownButton =>
      _scrolledUp.value || timeline?.allowNewEvent == false;

  ValueNotifier<bool> get scrolledUpNotifier => _scrolledUp;

  /// The event ID of the newest visible event when the user scrolled up.
  /// Used as the split point between the pre-center sliver (new events) and
  /// the center sliver (existing events). Events before this anchor in
  /// [filteredEvents] go into the pre-center sliver.
  String? _scrollAnchorEventId;

  /// Number of new events that arrived while the user was scrolled up,
  /// derived from the anchor position in [filteredEvents].
  int get newEventCount {
    if (_scrollAnchorEventId == null) return 0;
    final index = eventsKeyMap[_scrollAnchorEventId];
    if (index == null) return 0;
    return index;
  }

  bool get selectMode => selectedEvents.isNotEmpty;

  final int _loadHistoryCount = 100;

  String pendingText = '';

  bool showEmojiPicker = false;
  bool initiallyShowStickerPicker = false;

  List<Event>? _cachedFilteredEvents;
  Map<String, int>? _cachedEventsKeyMap;
  // Add a getter that the UI can use
  List<Event> get filteredEvents {
    if (_cachedFilteredEvents == null) {
      _recalculateEventsCache();
    }
    return _cachedFilteredEvents!;
  }

  Map<String, int> get eventsKeyMap {
    if (_cachedEventsKeyMap == null) {
      _recalculateEventsCache();
    }
    return _cachedEventsKeyMap!;
  }

  /// The [AutoScrollTag] index reserved for the bottom padding sliver in
  /// [ChatEventList]. Message tiles use [autoScrollIndexForEvent] so their
  /// indices don't collide with this one.
  static const int bottomPaddingAutoScrollIndex = 0;

  /// Converts a visible event index into the [AutoScrollTag] index used by
  /// the scroll controller. Index 0 is reserved for the bottom padding sliver.
  int autoScrollIndexForEvent(int eventIndex) => eventIndex + 1;

  /// Memoized message tiles; see [MemoizedTileCache] and [memoizeMessageTile].
  final MemoizedTileCache<ChatTileDeps, Message> _messageTileCache =
      MemoizedTileCache();

  /// Bumped whenever a room-member state event arrives: displaynames and
  /// avatars render inside every bubble, so all tiles must refresh.
  int _memberStateVersion = 0;

  final List<StreamSubscription<void>> _tileCacheSubs = [];

  int get memberStateVersion => _memberStateVersion;

  /// Returns the previously built [Message] widget for [eventId] when its
  /// inputs are unchanged; otherwise builds a fresh tile via [build].
  /// Reusing the identical widget instance makes Flutter's element tree
  /// skip the whole bubble subtree rebuild.
  Message memoizeMessageTile(
    String eventId,
    ChatTileDeps deps,
    Message Function() build,
  ) => _messageTileCache.get(eventId, deps, build);

  /// Extracts every event ID whose tile is affected by an incoming update:
  /// the updated event itself plus edit/reaction/reply/redaction targets.
  static Set<String> _tileIdsAffectedBy(Event event) {
    final ids = <String>{event.eventId};
    final relationship = event.relationshipEventId;
    if (relationship != null) ids.add(relationship);
    final relation = event.content['m.relates_to'];
    if (relation is Map<String, dynamic>) {
      final inReplyTo = relation['m.in_reply_to'];
      if (inReplyTo is Map<String, dynamic>) {
        final replyTarget = inReplyTo['event_id'];
        if (replyTarget is String) ids.add(replyTarget);
      }
    }
    final redacts = event.redacts;
    if (redacts != null) ids.add(redacts);
    return ids;
  }

  void _onTileRelevantEventUpdate(Event event) {
    if (event.roomId != roomId) return;
    if (event.type == EventTypes.RoomMember) {
      _memberStateVersion++;
      return;
    }
    final affected = _tileIdsAffectedBy(event);
    // Tiles quoting an affected event must refresh their reply previews.
    _messageTileCache.forEach((id, deps, _) {
      final quoted = deps.event.content['m.relates_to'];
      if (quoted is! Map<String, dynamic>) return;
      final inReplyTo = quoted['m.in_reply_to'];
      if (inReplyTo is Map<String, dynamic> &&
          affected.contains(inReplyTo['event_id'])) {
        affected.add(id);
      }
    });
    _messageTileCache.markDirty(affected);
  }

  void _subscribeTileInvalidation() {
    final client = Matrix.of(context).client;
    _tileCacheSubs.add(
      client.onTimelineEvent.stream.listen(_onTileRelevantEventUpdate),
    );
    _tileCacheSubs.add(
      client.onHistoryEvent.stream.listen(_onTileRelevantEventUpdate),
    );
    _tileCacheSubs.add(
      client.onRoomState.stream.listen((update) {
        if (update.roomId != roomId) return;
        if (update.state.type == EventTypes.RoomMember) {
          _memberStateVersion++;
        }
      }),
    );
  }

  void _unsubscribeTileInvalidation() {
    for (final sub in _tileCacheSubs) {
      sub.cancel();
    }
    _tileCacheSubs.clear();
    clearMessageTileCache();
  }

  void clearMessageTileCache() => _messageTileCache.clear();

  /// Rate-limited rebuild triggers for widgets inside the chat page.
  /// Composed once on the controller so StreamBuilders keep a single
  /// subscription across page rebuilds; recreating these pipelines in
  /// build() would resubscribe (and reset the rate-limit window) on every
  /// setState.
  late final Stream<bool> typingUpdatesStream = room.client.onSync.stream
      .where(
        (syncUpdate) =>
            syncUpdate.rooms?.join?[room.id]?.ephemeral?.any(
              (ephemeral) => ephemeral.type == 'm.typing',
            ) ??
            false,
      )
      .rateLimit(const Duration(seconds: 1));

  late final Stream<bool> syncStatusUpdatesStream = room
      .client
      .onSyncStatus
      .stream
      .rateLimit(const Duration(seconds: 1));

  /// Stable badge pipeline for the narrow-screen back button; recomposing
  /// it in build() would resubscribe and reset the throttle window on
  /// every per-second setState.
  late final Stream<bool> unreadBadgeUpdatesStream = room.client.onSync.stream
      .where((s) => s.hasRoomUpdate)
      .rateLimit(const Duration(seconds: 1));

  void _recalculateEventsCache() {
    if (timeline == null) {
      _cachedFilteredEvents = [];
      _cachedEventsKeyMap = {};
      return;
    }

    final events = timeline!.events
        .filterByThreaded(thread != null)
        .filterByVisibleInGui(threadId: thread?.rootEvent.eventId);

    _cachedFilteredEvents = events;

    _cachedEventsKeyMap = <String, int>{};
    for (var i = 0; i < _cachedFilteredEvents!.length; i++) {
      _cachedEventsKeyMap![_cachedFilteredEvents![i].eventId] = i;
    }
  }

  void acceptInvite() async {
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final waitForRoom = room.client.waitForRoomInSync(room.id, join: true);
        await room.join();
        await waitForRoom;
      },
      exceptionContext: ExceptionContext.joinRoom,
    );
    if (result.error != null) return;
  }

  void declineInvite() async {
    await showFutureLoadingDialog(context: context, future: room.leave);
    if (!mounted) return;
    context.go('/rooms');
  }

  void ignoreInvite() async {
    final userId = room
        .getState(EventTypes.RoomMember, room.client.userID!)
        ?.senderId;
    if (!mounted) return;
    context.go('/rooms/settings/security/ignorelist', extra: userId);
  }

  void recreateChat() async {
    final room = this.room;
    final userId = room.directChatMatrixID;
    if (userId == null) {
      throw Exception(
        'Try to recreate a room with is not a DM room. This should not be possible from the UI!',
      );
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => room.invite(userId),
    );
  }

  void leaveChat() async {
    final success = await showFutureLoadingDialog(
      context: context,
      future: room.leave,
    );
    if (success.error != null) return;
    context.go('/rooms');
  }

  void requestHistory([_]) async {
    Logs().v('Requesting history...');
    await timeline?.requestHistory(historyCount: _loadHistoryCount);
  }

  bool _requestingFuture = false;

  void requestFuture() async {
    final timeline = this.timeline;
    if (timeline == null) return;
    if (_requestingFuture) return;
    _requestingFuture = true;
    Logs().v('Requesting future...');
    final visibleEvents = timeline.events.filterByVisibleInGui();
    final mostRecentEvent = visibleEvents.firstOrNull;

    final anchorEventId = mostRecentEvent?.eventId;

    await timeline.requestFuture(historyCount: _loadHistoryCount);

    if (!mounted) {
      _requestingFuture = false;
      return;
    }

    // Move the scroll anchor forward so that newly loaded future events
    // are included in the center sliver (not the pre‑center sliver).
    // The scrollToIndex call below handles visual scroll anchoring.
    if (_scrollAnchorEventId != null && filteredEvents.isNotEmpty) {
      _scrollAnchorEventId = filteredEvents.first.eventId;
    }
    // If the timeline is now live (caught up to present), clear the anchor
    // and jump to the bottom — the user was actively loading to get to the
    // latest messages.
    if (timeline.allowNewEvent) {
      _scrollAnchorEventId = null;
      _scrolledUp.value = false;
      _cachedFilteredEvents = null;
      _cachedEventsKeyMap = null;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted && scrollController.hasClients) {
          await scrollController.scrollToIndex(
            bottomPaddingAutoScrollIndex,
            duration: FluffyThemes.animationDuration,
            preferPosition: AutoScrollPosition.begin,
          );
        }
      });
      setReadMarker();
      _requestingFuture = false;
      return;
    }

    if (anchorEventId != null && scrollController.hasClients) {
      final newVisibleEvents = timeline.events.filterByVisibleInGui();
      final anchorIndex = newVisibleEvents.indexWhere(
        (e) => e.eventId == anchorEventId,
      );
      if (anchorIndex > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scrollController.hasClients) return;
          scrollController.scrollToIndex(
            autoScrollIndexForEvent(anchorIndex),
            preferPosition: AutoScrollPosition.begin,
          );
        });
      }
    }

    if (mostRecentEvent != null) {
      setReadMarker(eventId: mostRecentEvent.eventId);
    }
    _requestingFuture = false;
  }

  void _updateScrollController() {
    if (!mounted) {
      return;
    }
    if (!scrollController.hasClients) return;

    final position = scrollController.position;

    final atBottom = position.pixels <= position.minScrollExtent;
    final isScrolledUp = position.pixels > position.minScrollExtent;

    if (timeline?.allowNewEvent == false ||
        isScrolledUp && !_scrolledUp.value) {
      _scrolledUp.value = true;
      if (_scrollAnchorEventId == null &&
          isScrolledUp &&
          filteredEvents.isNotEmpty) {
        _scrollAnchorEventId = filteredEvents.first.eventId;
      }
    } else if (atBottom && _scrolledUp.value) {
      _scrolledUp.value = false;
      _scrollAnchorEventId = null;
      setReadMarker();
      setState(() {});
    }
  }

  void _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = prefs.getString('draft_$roomId');
    if (draft != null && draft.isNotEmpty) {
      sendController.text = draft;
    }
  }

  void _shareItems([_]) async {
    final shareItems = widget.shareItems;
    if (shareItems == null || shareItems.isEmpty) return;
    if (!room.otherPartyCanReceiveMessages) {
      final theme = Theme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: theme.colorScheme.errorContainer,
          closeIconColor: theme.colorScheme.onErrorContainer,
          content: Text(
            L10n.of(context).otherPartyNotLoggedIn,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          showCloseIcon: true,
        ),
      );
      return;
    }
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    for (final item in shareItems) {
      if (item is FileShareItem) continue;
      if (item is TextShareItem) room.sendTextEvent(item.value);
      if (item is ContentShareItem) {
        final value = item.value;

        if (item.attribution != null) {
          // Сохраняем оригинальные значения ДО модификации
          final originalBody = value['body'] as String?;
          final originalFormattedBody = value['formatted_body'] as String?;

          if (originalBody is String) {
            if (['m.text', 'm.notice'].contains(value['msgtype'] as String) ||
                value['filename'] is String) {
              value['body'] = "${item.attribution}\n$originalBody";
            } else {
              value['filename'] = originalBody;
              value['body'] = item.attribution;
            }
          }

          // Формируем formatted_body на основе ОРИГИНАЛЬНЫХ значений
          if (value['format'] == 'org.matrix.custom.html' &&
              originalFormattedBody is String) {
            value['formatted_body'] =
                "<strong>${item.attribution}</strong><blockquote>$originalFormattedBody</blockquote>";
          } else if (originalBody is String) {
            value['formatted_body'] =
                "<strong>${item.attribution}</strong><blockquote>${HtmlEscape().convert(originalBody)}</blockquote>";
            value['format'] = 'org.matrix.custom.html';
          }

          value['xyz.extera.forward'] = {'attribution': item.attribution};
        }

        room.sendEvent(value);
      }
    }
    final files = shareItems
        .whereType<FileShareItem>()
        .map((item) => item.value)
        .toList();
    if (files.isEmpty) return;
    showAdaptiveDialog(
      context: context,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        thread: thread,
        outerContext: context,
        replyEvent: replyEvent,
      ),
    );
  }

  @override
  void initState() {
    inputFocus = FocusNode(onKeyEvent: _customKeyHandling);

    scrollController.addListener(_updateScrollController);
    inputFocus.addListener(_inputFocusListener);

    _loadDraft();
    WidgetsBinding.instance.addPostFrameCallback(_shareItems);
    super.initState();
    _displayChatDetailsColumn = ValueNotifier(
      AppSettings.displayChatDetailsColumn.value,
    );

    _layout = switch (AppSettings.messageStyle.value) {
      'bubbles' => .bubbles,
      'bubbles_legacy' => .bubblesLegacy,
      'modern' => .modern,
      _ => .bubbles,
    };
    sendingClient = Matrix.of(context).client;
    readMarkerEventId = room.hasNewMessages ? room.fullyRead : '';
    WidgetsBinding.instance.addObserver(this);
    _tryLoadTimeline();
    _subscribeTileInvalidation();

    _getThreads();
    if (PlatformInfos.isWeb) {
      _disposeWebDropListener = registerWebDropListener(
        onDragStateChanged: _onWebDragState,
        onDrop: _onWebDrop,
      );
    }
  }

  void _tryLoadTimeline() async {
    final initialEventId = widget.eventId;
    loadTimelineFuture = _getTimeline();
    Logs().v("Trying to load timeline...");
    try {
      await loadTimelineFuture;
      if (initialEventId != null) scrollToEventId(initialEventId, null);

      var readMarkerEventIndex = readMarkerEventId.isEmpty || timeline == null
          ? -1
          : timeline!.events
                .filterByVisibleInGui(
                  exceptionEventId: readMarkerEventId,
                  threadId: threadRootEventId,
                )
                .indexWhere((e) => e.eventId == readMarkerEventId);

      if (timeline != null &&
          timeline!.events.isNotEmpty &&
          readMarkerEventId.isNotEmpty &&
          readMarkerEventIndex == -1) {
        await timeline?.requestHistory(historyCount: _loadHistoryCount);
        readMarkerEventIndex = timeline!.events
            .filterByVisibleInGui(
              exceptionEventId: readMarkerEventId,
              threadId: threadRootEventId,
            )
            .indexWhere((e) => e.eventId == readMarkerEventId);
      }

      if (readMarkerEventIndex > 1) {
        Logs().v('Scroll up to visible event', readMarkerEventId);
        scrollToEventId(readMarkerEventId, null, highlightEvent: false);
        return;
      } else if (readMarkerEventId.isNotEmpty && readMarkerEventIndex == -1) {
        _showScrollUpMaterialBanner(readMarkerEventId);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(scrollController.position.minScrollExtent);
        }
      });

      setReadMarker();

      if (!mounted) return;
    } catch (e, s) {
      ErrorReporter(context, 'Unable to load timeline').onErrorCallback(e, s);
      rethrow;
    }
  }

  String? scrollUpBannerEventId;

  void discardScrollUpBannerEventId() => setState(() {
    scrollUpBannerEventId = null;
  });

  void _showScrollUpMaterialBanner(String eventId) => setState(() {
    scrollUpBannerEventId = eventId;
  });

  bool firstUpdateReceived = false;

  /// Timeline callbacks arrive in bursts (one sync can touch events,
  /// receipts and account data at once). Rebuilding the whole page per
  /// callback is wasted work; bursts coalesce into at most one rebuild per
  /// window, matching the rate limiting the chat list already applies.
  static const Duration _updateViewCoalesceWindow = Duration(milliseconds: 100);
  Timer? _updateViewTimer;

  Future<void> updateView() async {
    if (!mounted) return;
    if (_updateViewTimer != null) return;
    _updateViewTimer = Timer(_updateViewCoalesceWindow, () {
      _updateViewTimer = null;
      if (!mounted) return;
      setReadMarker();
      updateThreads();
      _cachedFilteredEvents = null;
      _cachedEventsKeyMap = null;
      setState(() {
        firstUpdateReceived = true;
      });
    });
  }

  Future<void> updateThreads() async {
    if (timeline?.events == null) return;
    final lastEvent = timeline?.events[timeline!.events.length - 1];

    if (lastEvent == null) return;
    if (lastEvent.relationshipType == RelationshipTypes.thread &&
        lastEvent.relationshipEventId != null) {
      final thread = await room.client.database.getThread(
        room.id,
        lastEvent.relationshipEventId!,
        room.client,
      );
      if (thread != null) {
        setState(() {
          threads?[lastEvent.eventId] = thread;
        });
      }
    }
  }

  Future<void>? loadTimelineFuture;
  Map<String, Thread>? threads = {};

  Future<void> _loadRoomTimeline({String? eventContextId}) async {
    try {
      timeline?.cancelSubscriptions();
      timeline = await room.getTimeline(
        onUpdate: updateView,
        eventContextId: eventContextId,
      );
    } catch (e, s) {
      Logs().w('Unable to load timeline on event ID $eventContextId', e, s);
      // if (!mounted) return;
      timeline = await room.getTimeline(onUpdate: updateView);
      if (!mounted) return;
      if (e is TimeoutException || e is IOException) {
        _showScrollUpMaterialBanner(eventContextId!);
      }
    }
  }

  Future<void> _loadThreadTimeline({String? eventContextId}) async {
    if (thread == null) {
      throw Exception(
        "_loadThreadTimeline should not be called, thread == null",
      );
    }
    try {
      timeline?.cancelSubscriptions();
      timeline = await thread!.getTimeline(
        onUpdate: updateView,
        eventContextId: eventContextId,
      );
      Logs().v("Thread timeline loaded ${timeline?.events.length}");
    } catch (e, s) {
      Logs().w(
        'Unable to load timeline on event ID $eventContextId (in thread)',
        e,
        s,
      );
      if (!mounted) return;
      timeline = await thread!.getTimeline(onUpdate: updateView);
      if (!mounted) return;
      if (e is TimeoutException || e is IOException) {
        _showScrollUpMaterialBanner(eventContextId!);
      }
    }
    if (timeline is ThreadTimeline && eventContextId == null) {
      (timeline as ThreadTimeline).getThreadEvents();
    }
  }

  Future<void> _getTimeline({String? eventContextId}) async {
    _scrollAnchorEventId = null;
    clearMessageTileCache();
    await Matrix.of(context).client.roomsLoading;
    await Matrix.of(context).client.accountDataLoading;
    threads = null;
    if (eventContextId != null &&
        (!eventContextId.isValidMatrixIdStrict() ||
            eventContextId.sigil != '\$')) {
      eventContextId = null;
    }
    if (thread == null) {
      await _loadRoomTimeline(eventContextId: eventContextId);
    } else {
      await _loadThreadTimeline(eventContextId: eventContextId);
    }
    timeline!.requestKeys(onlineKeyBackupOnly: false);
    if (room.markedUnread) room.markUnread(false);

    return;
  }

  Future<void> _getThreads() async {
    try {
      threads = await room.getThreads();
      Logs().w('Thread amount: ${threads?.length}');
    } catch (e, s) {
      Logs().w('Unable to load threads in $roomId', e, s);
    }
  }

  Future<void> showPollResults(Event event) async {
    await showFutureLoadingSnackbar(
      context: context,
      future: () => showPollResultsDialog(context, event),
    );
  }

  String? scrollToEventIdMarker;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    setReadMarker();
  }

  Future<void>? _setReadMarkerFuture;

  void setReadMarker({String? eventId}) {
    if (_setReadMarkerFuture != null) return;
    if (_scrolledUp.value) return;
    if (scrollUpBannerEventId != null) return;

    if (eventId == null &&
        !room.hasNewMessages &&
        room.notificationCount == 0) {
      return;
    }

    // Do not send read markers when app is not in foreground
    if (kIsWeb && !Matrix.of(context).webHasFocus) return;
    if (!kIsWeb &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final timeline = this.timeline;
    if (timeline == null || timeline.events.isEmpty) return;

    Logs().d('Set read marker...', eventId);
    // ignore: unawaited_futures
    _setReadMarkerFuture = timeline
        .setReadMarker(
          eventId: eventId,
          public: shouldSendPublicReadReceipts(room.client, roomId),
        )
        .then((_) {
          _setReadMarkerFuture = null;
        });

    if (timeline is RoomTimeline) {
      if (eventId == null || eventId == timeline.room.lastEvent?.eventId) {
        Matrix.of(
          context,
        ).backgroundPush?.cancelNotification(room.client, roomId);
      }
    }
    // TODO same for Threads
  }

  void performQuickAction(Event event) {
    switch (AppSettings.doubleTapAction.value) {
      case 'reply':
        replyAction(event);
        break;
      case 'react':
        _quickReaction(event);
        break;
    }
  }

  void _quickReaction(Event event) async {
    final reaction = AppSettings.doubleTapReaction.value;
    if (timeline == null) {
      await room.sendReaction(event.eventId, reaction);
      return;
    }
    final allReactionEvents = event.aggregatedEvents(
      timeline!,
      RelationshipTypes.reaction,
    );
    final myReaction = allReactionEvents.firstWhereOrNull(
      (event) =>
          event.senderId == sendingClient.userID! &&
          event.content
                  .tryGet<Map<String, dynamic>>('m.relates_to')
                  ?.tryGet<String>('key') ==
              reaction,
    );
    if (myReaction == null) {
      await room.sendReaction(event.eventId, reaction);
    } else {
      await room.redactEvent(myReaction.eventId);
    }
  }

  @override
  void dispose() {
    _unsubscribeTileInvalidation();
    _scrolledUp.dispose();
    timeline?.cancelSubscriptions();
    _updateViewTimer?.cancel();
    timeline = null;
    inputFocus.removeListener(_inputFocusListener);
    inputFocus.dispose();
    inputBarHeight.dispose();
    scrollController.dispose();
    sendController.dispose();
    _displayChatDetailsColumn.dispose();
    _disposeWebDropListener?.call();

    WidgetsBinding.instance.removeObserver(this);

    typingCoolDown?.cancel();
    typingTimeout?.cancel();
    _storeInputTimeoutTimer?.cancel();

    if (currentlyTyping) room.setTyping(false);
    super.dispose();
  }

  TextEditingController sendController = TextEditingController();

  void setSendingClient(Client c) {
    // first cancel typing with the old sending client
    if (currentlyTyping) {
      // no need to have the setting typing to false be blocking
      typingCoolDown?.cancel();
      typingCoolDown = null;
      room.setTyping(false);
      currentlyTyping = false;
    }
    // then cancel the old timeline
    // fixes bug with read reciepts and quick switching
    loadTimelineFuture = _getTimeline(eventContextId: room.fullyRead).onError(
      ErrorReporter(
        context,
        'Unable to load timeline after changing sending Client',
      ).onErrorCallback,
    );

    // then set the new sending client
    setState(() => sendingClient = c);
  }

  void setActiveClient(Client c) => setState(() {
    Matrix.of(context).setActiveClient(c);
  });

  Future<void> send() async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;

    final editingEvent = editEvent;
    if (editingEvent != null &&
        editingEvent.messageType == MessageTypes.Image) {
      await _sendImageEdit(editingEvent);
      return;
    }

    if (sendController.text.trim().isEmpty) return;

    if (inputFocus.hasFocus) {
      inputFocus.unfocus();
    }
    FocusScope.of(context).requestFocus(inputFocus);
    _storeInputTimeoutTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('draft_$roomId');
    var parseCommands = true;

    final commandMatch = RegExp(r'^\/(\w+)').firstMatch(sendController.text);
    if (commandMatch != null &&
        !sendingClient.commands.keys.contains(commandMatch[1]!.toLowerCase())) {
      final l10n = L10n.of(context);
      final dialogResult = await showOkCancelAlertDialog(
        context: context,
        title: l10n.commandInvalid,
        message: l10n.commandMissing(commandMatch[0]!),
        okLabel: l10n.sendAsText,
        cancelLabel: l10n.cancel,
      );
      if (dialogResult == OkCancelResult.cancel) return;
      parseCommands = false;
    }

    if (currentlyTyping) {
      typingCoolDown?.cancel();
      room.setTyping(false);
      currentlyTyping = false;
    }

    // ignore: unawaited_futures
    room.sendTextEvent(
      sendController.text,
      inReplyTo: replyEvent,
      replyMention: replyMention,
      editEventId: editEvent?.eventId,
      eventContent: editEvent?.content,
      parseCommands: parseCommands,
      threadRootEventId: thread?.rootEvent.eventId,
      threadLastEventId:
          thread?.lastEvent?.eventId ?? thread?.rootEvent.eventId,
    );
    sendController.value = TextEditingValue(
      text: pendingText,
      selection: const TextSelection.collapsed(offset: 0),
    );

    setState(() {
      sendController.text = pendingText;
      _inputTextIsEmpty = pendingText.isEmpty;
      replyEvent = null;
      editEvent = null;
      pendingText = '';
    });
  }

  /// Sends the edit of an image message.
  ///
  /// The attachment is only uploaded again when the user actually replaced or
  /// edited the image. Editing just the caption reuses the existing mxc uri,
  /// encryption keys and image info of the original event.
  Future<void> _sendImageEdit(Event event) async {
    if (inputFocus.hasFocus) inputFocus.unfocus();
    FocusScope.of(context).requestFocus(inputFocus);
    _storeInputTimeoutTimer?.cancel();

    final newImage = editImageFile;
    final originalContent = _editEventDisplayContent ?? event.content;
    final caption = sendController.text.trim();

    final originalFilename = originalContent.tryGet<String>('filename');
    final originalBody = originalContent.tryGet<String>('body');
    final filename = originalFilename ?? originalBody ?? 'image';

    // The input bar was prefilled with the body of the message, which is the
    // file name itself when the image has no caption. Only treat the text as a
    // caption if it actually differs from that file name, so that replacing an
    // uncaptioned image does not turn the old file name into a caption.
    final hasCaption =
        caption.isNotEmpty &&
        caption != filename &&
        !(originalFilename == null && caption == originalBody);

    if (newImage == null) {
      final content = originalContent.copy()
        // Relations of the original event must not be carried over into the
        // replacement content.
        ..remove('m.relates_to')
        ..remove('m.new_content')
        // The caption is plain text, so any previous formatting is stale.
        ..remove('format')
        ..remove('formatted_body')
        ..['msgtype'] = MessageTypes.Image
        ..['filename'] = filename
        ..['body'] = hasCaption ? caption : filename;
      applyContentWarning(content, editContentWarning);

      // ignore: unawaited_futures
      room.sendEvent(content, editEventId: event.eventId);
    } else {
      final extraContent = <String, dynamic>{
        'filename': newImage.name,
        'body': hasCaption ? caption : newImage.name,
      };
      applyContentWarning(extraContent, editContentWarning);

      // ignore: unawaited_futures
      room.sendFileEvent(
        newImage,
        editEventId: event.eventId,
        extraContent: extraContent,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('draft_$roomId');
    if (!mounted) return;

    setState(() {
      sendController.text = pendingText;
      _inputTextIsEmpty = pendingText.isEmpty;
      replyEvent = null;
      editEvent = null;
      editImageFile = null;
      editContentWarning = _originalContentWarning = null;
      pendingText = '';
    });
  }

  void sendPollAction() async {
    await showAdaptiveDialog(
      context: context,
      useRootNavigator: false,
      builder: (c) =>
          SendPollDialog(room: room, thread: thread, outerContext: context),
    );
    replyEvent = null;
  }

  void sendFileAction({FileType type = .any}) async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    final files = await selectFiles(context, allowMultiple: true, type: type);
    if (files.isEmpty) {
      Logs().v("Returning in sendFileAction, bc files.isEmpty==true");
      return;
    }
    await showAdaptiveDialog(
      context: context,
      useRootNavigator: false,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        thread: thread,
        outerContext: context,
        replyEvent: replyEvent,
        onClearReply: () {
          replyEvent = null;
        },
      ),
    );
    // replyEvent = null;
  }

  void sendImageFromClipBoard(
    Uint8List? image, {
    String mimeType = 'image/png',
  }) async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    Uint8List? pastedImage;
    if (PlatformInfos.isLinux) {
      pastedImage = await getImageFromClipboardLinux();
    } else if (PlatformInfos.isWindows) {
      pastedImage = await getImageFromClipboardWindows();
    } else if (PlatformInfos.isMacOS) {
      pastedImage = await getImageFromClipboardMacOS();
    } else {
      pastedImage = image;
    }
    if (pastedImage == null) return;

    final extension = mimeType.split('/').last.split('+').first;
    final files = [
      XFile.fromData(
        pastedImage,
        mimeType: mimeType,
        name: 'clipboard.$extension',
      ),
    ];

    await showAdaptiveDialog(
      context: context,
      useRootNavigator: false,
      builder: (c) => SendFileDialog(
        files: files,
        room: room,
        thread: thread,
        outerContext: context,
        replyEvent: replyEvent,
        onClearReply: () {
          replyEvent = null;
        },
      ),
    );
  }

  void openCameraAction() async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    inputFocus.unfocus();
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null) return;

    await showAdaptiveDialog(
      context: context,
      useRootNavigator: false,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        thread: thread,
        outerContext: context,
      ),
    );
  }

  void openVideoCameraAction() async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    inputFocus.unfocus();
    final file = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
    if (file == null) return;

    await showAdaptiveDialog(
      context: context,
      useRootNavigator: false,
      builder: (c) => SendFileDialog(
        files: [file],
        room: room,
        thread: thread,
        outerContext: context,
      ),
    );
  }

  Future<void> onVoiceMessageSend(
    String path,
    int duration,
    List<int> waveform,
    String fileName,
  ) async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final audioFile = XFile(path);

    final bytesResult = await showFutureLoadingDialog(
      context: context,
      future: audioFile.readAsBytes,
    );
    final bytes = bytesResult.result;
    if (bytes == null) return;

    final mimeType = lookupMimeType(fileName, headerBytes: bytes);
    final ext = mimeType == null ? null : extensionFromMime(mimeType);
    if (ext != null) {
      fileName = 'voice_message_${DateTime.now().millisecondsSinceEpoch}.$ext';
    }

    final file = MatrixAudioFile(bytes: bytes, name: fileName);

    await room
        .sendFileEvent(
          file,
          inReplyTo: replyEvent,
          extraContent: {
            'info': {...file.info, 'duration': duration},
            'org.matrix.msc3245.voice': {},
            'org.matrix.msc1767.audio': {
              'duration': duration,
              'waveform': waveform,
            },
          },
          threadLastEventId: thread?.lastEvent?.eventId,
          threadRootEventId: thread?.rootEvent.eventId,
        )
        .catchError((e) {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text((e as Object).toLocalizedString(context))),
          );
          return null;
        });
    setState(() {
      replyEvent = null;
    });
  }

  Future<void> onVideoNoteSend(
    String path,
    int duration,
    String fileName,
  ) async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final videoFile = XFile(path);

    final bytesResult = await showFutureLoadingDialog(
      context: context,
      future: videoFile.readAsBytes,
    );
    final bytes = bytesResult.result;
    if (bytes == null) return;

    final mimeType = lookupMimeType(fileName, headerBytes: bytes);
    final ext = mimeType == null ? null : extensionFromMime(mimeType);
    if (ext != null) {
      fileName = 'video_note_${DateTime.now().millisecondsSinceEpoch}.$ext';
    }

    final file = await videoFile.resizeVideo();

    MatrixImageFile? thumbnail;
    try {
      thumbnail = await videoFile.getVideoThumbnail();
    } catch (e, s) {
      Logs().w('Failed to generate video note thumbnail', e, s);
    }

    file.info['duration'] = duration;

    await room
        .sendFileEvent(
          file,
          thumbnail: thumbnail,
          inReplyTo: replyEvent,
          extraContent: {'xyz.extera.video_note': {}},
          threadLastEventId: thread?.lastEvent?.eventId,
          threadRootEventId: thread?.rootEvent.eventId,
        )
        .catchError((e) {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text((e as Object).toLocalizedString(context))),
          );
          return null;
        });
    setState(() {
      replyEvent = null;
    });
  }

  void hideEmojiPicker() {
    setState(() => showEmojiPicker = false);
  }

  void emojiPickerAction() {
    if (showEmojiPicker) {
      inputFocus.requestFocus();
    } else {
      inputFocus.unfocus();
    }
    setState(() {
      initiallyShowStickerPicker = sendController.text.isEmpty;
      showEmojiPicker = !showEmojiPicker;
    });
  }

  void _inputFocusListener() {
    if (showEmojiPicker && inputFocus.hasFocus) {
      setState(() => showEmojiPicker = false);
    }
  }

  void sendLocationAction() async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!mounted || !proceed) return;
    await showAdaptiveDialog(
      context: context,
      useRootNavigator: false,
      builder: (c) => SendLocationDialog(room: room, thread: thread),
    );
  }

  String _getSelectedEventString() {
    var copyString = '';
    if (selectedEvents.length == 1) {
      return selectedEvents.first
          .getDisplayEvent(timeline!)
          .calcLocalizedBodyFallback(MatrixLocals(L10n.of(context)));
    }
    for (final event in selectedEvents) {
      if (copyString.isNotEmpty) copyString += '\n\n';
      copyString += event
          .getDisplayEvent(timeline!)
          .calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: true,
          );
    }
    return copyString;
  }

  void copyEventsAction() {
    Clipboard.setData(ClipboardData(text: _getSelectedEventString()));
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  void copyLinkAction({Event? event}) {
    Clipboard.setData(
      ClipboardData(
        text: event != null
            ? event.getLink()
            : selectedEvents.map((event) => event.getLink()).join('\n'),
      ),
    );
    setState(() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).copiedToClipboard)),
      );
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  void recoverEventAction({Event? event}) async {
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).recoverMessage,
      message: L10n.of(context).recoverMessageDescription,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
    );
    if (!mounted) return;
    if (consent != OkCancelResult.ok) return;
    final mx = Matrix.of(context);
    if (!await mx.client.isSynapseAdministrator()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).errorRecoveringMessageNoAdmin)),
      );
      return;
    }
    event ??= selectedEvents.single;
    await mx.client.reportEvent(
      roomId,
      event.eventId,
      reason: "Extera (Next) Redacted Event Recover",
    );

    final reports = await mx.client.getEventReports();
    final report = reports.firstWhere(
      (rep) => rep['room_id'] == roomId && rep['event_id'] == event!.eventId,
    );
    final recoveredEvent = await mx.client.getReportedEvent(report['id']);

    if (recoveredEvent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).errorRecoveringMessage)),
      );
      return;
    }

    await showAdaptiveBottomSheet(
      context: context,
      builder: (context) =>
          RecoveredEventDialog(event: recoveredEvent, timeline: timeline!),
    );
  }

  void translateEventAction({Event? event}) async {
    if (!AppSettings.messageTranslation.value) {
      return;
    }
    event ??= selectedEvents.single;
    ScaffoldMessenger.of(
      context,
    ).showLoadingSnackBar(L10n.of(context).translating);
    NeurogateTranslationResponse translation;
    final content = {...event.content};
    try {
      translation = await Neurogate.translateText(
        room.client,
        event.isRichMessage ? event.formattedText : event.text,
        'auto', // TODO select source language
        AppSettings.translationTargetLanguage.value.isEmpty
            ? PlatformDispatcher.instance.locale.languageCode
            : AppSettings.translationTargetLanguage.value,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).errorTranslatingMessage)),
      );
      return;
    }
    if (event.isRichMessage) {
      content['formatted_body'] = translation.translation;
    } else {
      content['body'] = translation.translation;
    }
    content['xyz.extera.translated'] = true;
    ScaffoldMessenger.of(context).clearSnackBars();
    await showAdaptiveBottomSheet(
      context: context,
      builder: (BuildContext ctx) => TranslatedEventDialog(
        event: Event(
          content: content,
          type: 'm.room.message',
          eventId: event!.eventId,
          senderId: event.senderId,
          originServerTs: event.originServerTs,
          room: room,
        ),
        engine: translation.engine,
        timeline: timeline!,
      ),
    );
  }

  void reportEventAction({Event? event}) async {
    event ??= selectedEvents.single;
    final reason = await showTextInputDialog(
      context: context,
      title: L10n.of(context).whyDoYouWantToReportThis,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      hintText: L10n.of(context).reason,
    );
    if (reason == null || reason.isEmpty) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => Matrix.of(
        context,
      ).client.reportEvent(event!.roomId!, event.eventId, reason: reason),
    );
    if (result.error != null) return;
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  void deleteErrorEventsAction() async {
    try {
      if (selectedEvents.any((event) => event.status != EventStatus.error)) {
        throw Exception(
          'Tried to delete failed to send events but one event is not failed to sent',
        );
      }
      for (final event in selectedEvents) {
        await event.cancelSend();
      }
      setState(selectedEvents.clear);
    } catch (e, s) {
      ErrorReporter(
        context,
        'Error while delete error events action',
      ).onErrorCallback(e, s);
    }
  }

  void discussAction({Event? threadRootEvent}) async {
    final event = threadRootEvent ?? selectedEvents.first;
    if (!room.threads.containsKey(event.eventId)) {
      room.threads[event.eventId] = Thread(
        room: room,
        rootEvent: event,
        client: room.client,
        currentUserParticipated: false,
        count: 0,
        highlightCount: 0,
        notificationCount: 0,
      );
    }

    context.go('/rooms/$roomId/threads/${event.eventId}');
    selectedEvents.clear();
  }

  void endPollAction({Event? event}) async {
    event ??= selectedEvents.first;
    final client = currentRoomBundle.firstWhere(
      (cl) => event!.senderId == cl!.userID,
      orElse: () => null,
    );
    if (client == null) return;
    if (event.senderId != client.userID) return;
    await room.sendEvent({
      'org.matrix.msc1767.text': 'Ended poll',
      'm.relates_to': {'rel_type': 'm.reference', 'event_id': event.eventId},
      'body': 'Ended poll',
    }, type: 'org.matrix.msc3381.poll.end');
  }

  void redactEventsAction({Event? event}) async {
    final events = event != null ? [event] : selectedEvents;
    final reasonInput = events.any((event) => event.status.isSent)
        ? await showTextInputDialog(
            context: context,
            title: L10n.of(context).redactMessage,
            message: L10n.of(context).redactMessageDescription,
            isDestructive: true,
            hintText: L10n.of(context).optionalRedactReason,
            okLabel: L10n.of(context).remove,
            cancelLabel: L10n.of(context).cancel,
          )
        : null;
    if (reasonInput == null) return;
    final reason = reasonInput.isEmpty ? null : reasonInput;
    for (final event in events) {
      await showFutureLoadingDialog(
        context: context,
        future: () async {
          if (event.status.isSent) {
            if (event.canRedact) {
              await event.redactEvent(reason: reason);
            } else {
              final client = currentRoomBundle.firstWhere(
                (cl) => events.first.senderId == cl!.userID,
                orElse: () => null,
              );
              if (client == null) {
                return;
              }
              final room = client.getRoomById(roomId)!;
              await Event.fromJson(
                event.toJson(),
                room,
              ).redactEvent(reason: reason);
            }
          } else {
            await event.cancelSend();
          }
        },
      );
    }
    setState(() {
      showEmojiPicker = false;
      selectedEvents.clear();
    });
  }

  List<Client?> get currentRoomBundle {
    final clients = Matrix.of(context).currentBundle!;
    clients.removeWhere((c) => c!.getRoomById(roomId) == null);
    return clients;
  }

  bool get canRedactSelectedEvents {
    if (isArchived) return false;
    final clients = Matrix.of(context).currentBundle;
    for (final event in selectedEvents) {
      if (!event.status.isSent) return false;
      if (event.canRedact == false &&
          !(clients!.any((cl) => event.senderId == cl!.userID))) {
        return false;
      }
    }
    return true;
  }

  bool get canPinSelectedEvents {
    if (isArchived ||
        !room.canChangeStateEvent(EventTypes.RoomPinnedEvents) ||
        selectedEvents.length != 1 ||
        !selectedEvents.single.status.isSent) {
      return false;
    }
    return true;
  }

  bool get canEditSelectedEvents {
    if (isArchived ||
        selectedEvents.length != 1 ||
        !selectedEvents.first.status.isSent) {
      return false;
    }
    return currentRoomBundle.any(
      (cl) => selectedEvents.first.senderId == cl!.userID,
    );
  }

  void forwardEventsAction({Event? event}) async {
    await showScaffoldDialog(
      context: context,
      builder: (context) => ShareScaffoldDialog(
        items: selectedEvents.isEmpty
            ? [
                ContentShareItem(
                  sanitizeContent(
                    event!.getDisplayEvent(timeline!).content.copy(),
                  ),
                  attribution: generateAttributionString(event),
                ),
              ]
            : selectedEvents
                  .map(
                    (event) => ContentShareItem(
                      sanitizeContent(
                        event.getDisplayEvent(timeline!).content.copy(),
                      ),
                      attribution: generateAttributionString(event),
                    ),
                  )
                  .toList(),
      ),
    );
    if (!mounted) return;
    setState(() => selectedEvents.clear());
  }

  void sendAgainAction({Event? event}) {
    event ??= selectedEvents.first;
    if (event.status.isError) {
      event.sendAgain();
    }
    final allEditEvents = event
        .aggregatedEvents(timeline!, RelationshipTypes.edit)
        .where((e) => e.status.isError);
    for (final e in allEditEvents) {
      e.sendAgain();
    }
    setState(() => selectedEvents.clear());
  }

  void replyAction(Event? replyTo) {
    setState(() {
      replyEvent = replyTo ?? selectedEvents.first;
      selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  void setReplyMention(bool b) {
    setState(() {
      replyMention = b;
    });
  }

  bool _isEventVisibleInScroll(String eventId) {
    final eventIndex = eventsKeyMap[eventId];
    if (eventIndex == null) return false;
    final tagState =
        scrollController.tagMap[autoScrollIndexForEvent(eventIndex)];
    final tagContext = tagState?.context;
    if (tagContext == null) return false; // not currently laid out
    final renderBox = tagContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return false;
    final scrollRenderBox =
        scrollController.position.context.storageContext.findRenderObject()
            as RenderBox?;
    if (scrollRenderBox == null) return false;
    final viewportTop = scrollRenderBox.localToGlobal(Offset.zero).dy;
    final viewportBottom =
        viewportTop + scrollController.position.viewportDimension;
    final widgetTop = renderBox.localToGlobal(Offset.zero).dy;
    final widgetBottom = widgetTop + renderBox.size.height;
    return widgetBottom > viewportTop && widgetTop < viewportBottom;
  }

  /// The root of the thread [event] belongs to, or `null` if it is not a
  /// thread reply.
  String? _threadRootOf(Event event) =>
      event.relationshipType == RelationshipTypes.thread
      ? event.relationshipEventId
      : null;

  /// Navigates to the timeline that actually contains [event], if that is not
  /// the one currently displayed.
  ///
  /// Thread replies are filtered out of the room timeline and room messages are
  /// filtered out of thread timelines, so jumping between the two means
  /// changing routes rather than scrolling.
  bool _goToEventTimeline(Event event) {
    final targetThreadRootId = _threadRootOf(event);
    if (targetThreadRootId == threadRootEventId) return false;
    if (!mounted) return false;

    context.go(
      '/${Uri(pathSegments: [
        'rooms',
        roomId,
        if (targetThreadRootId != null) ...['threads', targetThreadRootId],
      ], queryParameters: {'event': event.eventId})}',
    );
    return true;
  }

  /// Same as [_goToEventTimeline], but for an event that is not loaded in the
  /// current timeline and therefore has to be fetched first.
  Future<bool> _goToRemoteEventTimeline(String eventId) async {
    try {
      final event = await room.getEventById(eventId);
      if (event == null) return false;
      return _goToEventTimeline(event);
    } catch (e, s) {
      Logs().w('Unable to look up $eventId to jump to it', e, s);
      return false;
    }
  }

  void scrollToEventId(
    String eventId,
    String? scrolledFromEventId, {
    bool highlightEvent = true,
    bool isRetry = false,
  }) async {
    final foundEvent = timeline!.events.firstWhereOrNull(
      (event) => event.eventId == eventId,
    );

    // print('Scrolling to $eventId.');

    final eventIndex = foundEvent == null
        ? -1
        : timeline!.events
              .filterByVisibleInGui(
                exceptionEventId: eventId,
                threadId: threadRootEventId,
              )
              .indexOf(foundEvent);

    // print('Scrolling to $eventId - index: $eventIndex');

    // invalidate cache
    _cachedEventsKeyMap = null;
    _cachedFilteredEvents = null;

    if (eventIndex == -1) {
      // A thread reply is never part of the room timeline, and a room message
      // is never part of a thread timeline. Before reloading anything, check
      // whether the event we already have simply belongs somewhere else.
      if (foundEvent != null && _goToEventTimeline(foundEvent)) return;

      if (isRetry) {
        // The event is not in this timeline at all. It may still be a thread
        // reply that was never loaded here, so ask the server about it.
        if (await _goToRemoteEventTimeline(eventId)) return;
        _showScrollUpMaterialBanner(eventId);
        return;
      }
      setState(() {
        timeline = null;
        _scrolledUp.value = false;
        loadTimelineFuture = _getTimeline(eventContextId: eventId).onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll to ID',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
      // print('Scrolling to $eventId (retry)');
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        scrollToEventId(
          eventId,
          scrolledFromEventId,
          highlightEvent: highlightEvent,
          isRetry: true,
        );
      });
      return;
    }
    if (highlightEvent) {
      setState(() {
        scrollToEventIdMarker = eventId;
      });
    }
    if ((eventsToScrollBackTo.isEmpty ||
            eventsToScrollBackTo.last != scrolledFromEventId) &&
        scrolledFromEventId != null) {
      if (!_isEventVisibleInScroll(scrolledFromEventId)) {
        setState(() {
          eventsToScrollBackTo.add(scrolledFromEventId);
        });
      }
    }
    await scrollController.scrollToIndex(
      autoScrollIndexForEvent(eventIndex),
      duration: FluffyThemes.animationDuration,
      preferPosition: .middle,
    );
    _updateScrollController();
  }

  void scrollDown() async {
    _scrollAnchorEventId = null;

    _cachedEventsKeyMap = null;
    _cachedFilteredEvents = null;

    if (eventsToScrollBackTo.isNotEmpty) {
      scrollToEventId(eventsToScrollBackTo.last, null);
      setState(() {
        eventsToScrollBackTo.removeLast();
      });
      return;
    }

    if (!timeline!.allowNewEvent) {
      setState(() {
        timeline = null;
        _scrolledUp.value = false;
        loadTimelineFuture = _getTimeline().onError(
          ErrorReporter(
            context,
            'Unable to load timeline after scroll down',
          ).onErrorCallback,
        );
      });
      await loadTimelineFuture;
    }
    await scrollController.scrollToIndex(
      bottomPaddingAutoScrollIndex,
      duration: FluffyThemes.animationDuration,
      preferPosition: AutoScrollPosition.begin,
    );
  }

  void onEmojiSelected(Category? _, PickerEmoji emoji) {
    room.client.addRecentEmoji(emoji.customData ?? emoji.standardEmoji!.char);
    typeEmoji(emoji);
    onInputBarChanged(sendController.text);
  }

  void typeEmoji(PickerEmoji? emoji) {
    if (emoji == null) return;
    if (emoji.type == .custom) {
      typeCustomEmoji(emoji);
      return;
    }
    final text = sendController.text;
    final selection = sendController.selection;
    final char = emoji.standardEmoji!.char;
    final newText = sendController.text.isEmpty
        ? char
        : text.replaceRange(selection.start, selection.end, char);
    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        // don't forget an UTF-8 combined emoji might have a length > 1
        offset: selection.baseOffset + char.length,
      ),
    );
  }

  void typeCustomEmoji(PickerEmoji emoji) {
    final text = sendController.text;
    final selection = sendController.selection;

    final customId = emoji.customId ?? emoji.customData ?? '';
    final insertPack = emoji.categoryId;

    var isUnique = true;
    if (customId.isNotEmpty && insertPack != null) {
      final emotePacks = room.getImagePacks(ImagePackUsage.emoticon);
      for (final pack in emotePacks.entries) {
        if (pack.key == insertPack) continue;
        for (final emote in pack.value.images.entries) {
          if (emote.key == customId) {
            isUnique = false;
            break;
          }
        }
        if (!isUnique) break;
      }
    }

    final packPrefix = (!isUnique && insertPack != null) ? '$insertPack~' : '';
    final insertText = ':$packPrefix$customId: ';

    final start = (selection.isValid ? selection.start : text.length).clamp(
      0,
      text.length,
    );
    final end = (selection.isValid ? selection.end : text.length).clamp(
      0,
      text.length,
    );

    final newText = text.isEmpty
        ? insertText
        : text.replaceRange(start, end, insertText);
    final cursorOffset = (start + insertText.length).clamp(0, newText.length);

    sendController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }

  void emojiPickerBackspace() {
    sendController
      ..text = sendController.text.characters.skipLast(1).toString()
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: sendController.text.length),
      );
  }

  void sendEmojiAction(String? emoji) async {
    final events = List<Event>.from(selectedEvents);
    setState(() => selectedEvents.clear());
    for (final event in events) {
      await room.sendReaction(event.eventId, emoji!);
    }
  }

  void clearSelectedEvents() => setState(() {
    selectedEvents.clear();
    _cachedFilteredEvents = null;
    _cachedEventsKeyMap = null;
    showEmojiPicker = false;
  });

  void clearSingleSelectedEvent() {
    if (selectedEvents.length <= 1) {
      clearSelectedEvents();
    }
  }

  void _startEditingEvent(Event event, {bool clearSelection = false}) {
    final timeline = this.timeline;
    if (timeline == null) return;

    final client = currentRoomBundle.firstWhere(
      (c) => c?.userID == event.senderId,
      orElse: () => null,
    );
    if (client == null) return;

    setSendingClient(client);
    setState(() {
      pendingText = sendController.text;
      editEvent = event;
      editImageFile = null;
      editContentWarning = _originalContentWarning = contentWarningOf(
        event.getDisplayEvent(timeline).content,
      );
      sendController.text = event.getDisplayEvent(timeline).body;
      if (clearSelection) selectedEvents.clear();
    });
    inputFocus.requestFocus();
  }

  /// The content of the message currently being edited, with all previous edits
  /// already applied.
  Map<String, dynamic>? get _editEventDisplayContent {
    final event = editEvent;
    final timeline = this.timeline;
    if (event == null || timeline == null) return null;
    return event.getDisplayEvent(timeline).content;
  }

  Future<Uint8List?> _currentEditImageBytes() async {
    final pending = editImageFile;
    if (pending != null) return pending.bytes;

    final event = editEvent;
    final timeline = this.timeline;
    if (event == null || timeline == null) return null;

    final result = await showFutureLoadingDialog(
      context: context,
      future: () =>
          event.getDisplayEvent(timeline).downloadAndDecryptAttachment(),
    );
    return result.result?.bytes;
  }

  Future<void> _setEditImage(
    Uint8List bytes,
    String name,
    String? mimeType,
  ) async {
    final file = await MatrixImageFile.create(
      bytes: bytes,
      name: name,
      mimeType: mimeType,
      nativeImplementations: sendingClient.nativeImplementations,
    );
    if (!mounted) return;
    setState(() {
      editImageFile = file;
    });
  }

  /// Picks another image to replace the attachment of the message being edited.
  void replaceEditImageAction() async {
    final picked = await selectFiles(context, type: FileType.image);
    final file = picked.firstOrNull;
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await _setEditImage(
      bytes,
      file.name,
      file.mimeType ?? lookupMimeType(file.name, headerBytes: bytes),
    );
  }

  /// Opens the image editor on the attachment of the message being edited.
  void editEditImageAction() async {
    final bytes = await _currentEditImageBytes();
    if (bytes == null || !mounted) return;

    final edited = await showImageEditor(context: context, byteArray: bytes);
    if (edited == null || !mounted) return;

    // The image editor always renders to JPEG.
    final currentName =
        editImageFile?.name ??
        _editEventDisplayContent?.tryGet<String>('filename') ??
        _editEventDisplayContent?.tryGet<String>('body') ??
        'image';
    final baseName = currentName.contains('.')
        ? currentName.substring(0, currentName.lastIndexOf('.'))
        : currentName;
    await _setEditImage(edited, '$baseName.jpg', 'image/jpeg');
  }

  /// Discards the replacement image and goes back to the original attachment.
  void resetEditImageAction() => setState(() {
    editImageFile = null;
  });

  KeyEventResult _customKeyHandling(FocusNode node, KeyEvent evt) {
    if (evt is KeyDownEvent &&
        evt.logicalKey == LogicalKeyboardKey.arrowUp &&
        !PlatformInfos.isMobile &&
        editEvent == null &&
        replyEvent == null &&
        sendController.text.isEmpty) {
      editLastSentMessage();
      return KeyEventResult.handled;
    }

    if (evt is KeyDownEvent &&
        evt.logicalKey == LogicalKeyboardKey.escape &&
        editEvent != null) {
      cancelEditWithConfirmation();
      return KeyEventResult.handled;
    }

    if (!HardwareKeyboard.instance.isShiftPressed &&
        evt.logicalKey.keyLabel == 'Enter' &&
        AppSettings.sendOnEnter.value) {
      if (evt is KeyDownEvent) {
        send();
      }
      return KeyEventResult.handled;
    } else if (evt.logicalKey.keyLabel == 'Enter' && evt is KeyDownEvent) {
      final currentLineNum =
          sendController.text
              .substring(0, sendController.selection.baseOffset)
              .split('\n')
              .length -
          1;
      final currentLine = sendController.text.split('\n')[currentLineNum];

      for (final pattern in [
        '- [ ] ',
        '- [x] ',
        '* [ ] ',
        '* [x] ',
        '- ',
        '* ',
        '+ ',
      ]) {
        if (currentLine.startsWith(pattern)) {
          if (currentLine == pattern) {
            return KeyEventResult.ignored;
          }
          sendController.text += '\n$pattern';
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    } else {
      return KeyEventResult.ignored;
    }
  }

  void editSelectedEventAction({Event? event}) {
    _startEditingEvent(event ?? selectedEvents.first, clearSelection: true);
  }

  void editLastSentMessage() {
    final timeline = this.timeline;
    if (timeline == null) return;

    final events = timeline.events.filterByVisibleInGui(
      threadId: threadRootEventId,
    );

    final lastOwnMessage = events.firstWhereOrNull(
      (e) =>
          e.type == EventTypes.Message &&
          e.messageType == MessageTypes.Text &&
          e.status.isSent &&
          !e.redacted &&
          currentRoomBundle.any((c) => c?.userID == e.senderId),
    );

    if (lastOwnMessage == null) return;

    _startEditingEvent(lastOwnMessage);
  }

  Future<void> cancelEditWithConfirmation() async {
    final originalText = editEvent!
        .getDisplayEvent(timeline!)
        .calcLocalizedBodyFallback(
          MatrixLocals(L10n.of(context)),
          withSenderNamePrefix: false,
          hideReply: true,
        );

    if (sendController.text != originalText ||
        editImageFile != null ||
        editContentWarning != _originalContentWarning) {
      final result = await showOkCancelAlertDialog(
        context: context,
        title: L10n.of(context).areYouSure,
        message: L10n.of(context).discardEdits,
        okLabel: L10n.of(context).ok,
        cancelLabel: L10n.of(context).cancel,
      );
      if (result == OkCancelResult.cancel) return;
    }

    cancelReplyEventAction();
  }

  void goToNewRoomAction() async {
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final users = await room.requestParticipants(
          [Membership.join, Membership.leave],
          true,
          false,
        );
        users.sort((a, b) => a.powerLevel.level.compareTo(b.powerLevel.level));
        final via = users
            .map((user) => user.id.domain)
            .whereType<String>()
            .toSet()
            .take(10)
            .toList();
        return room.client.joinRoom(
          room
              .getState(EventTypes.RoomTombstone)!
              .parsedTombstoneContent
              .replacementRoom,
          via: via,
        );
      },
    );
    if (result.error != null) return;
    if (!mounted) return;
    context.go('/rooms/${result.result!}');

    await showFutureLoadingDialog(context: context, future: room.leave);
  }

  ContextMenuController? _contextMenuController;

  void closeMessageMenu() {
    if (PlatformInfos.isMobile) {
      Navigator.of(context).pop(); // in 2
    } else {
      _contextMenuController?.remove();
    }
  }

  /// Pins the scroll anchor to the newest event so that incoming messages
  /// are routed to the pre-center sliver (below the viewport) instead of
  /// shifting the visible content. Used while the message context menu is
  /// open to prevent the list from auto-scrolling down when new events arrive.
  /// Returns true if this call set the anchor (i.e. the user was at the
  /// bottom before opening the menu); false if it was already pinned because
  /// the user had scrolled up.
  bool _menuSetAnchor = false;

  void _setScrollAnchorForMenu() {
    if (_scrollAnchorEventId == null && filteredEvents.isNotEmpty) {
      _scrollAnchorEventId = filteredEvents.first.eventId;
      _menuSetAnchor = true;
    }
  }

  /// Restores normal scroll behaviour after the context menu closes. If the
  /// menu itself pinned the anchor (the user was at the bottom) the view
  /// scrolls back down when new events arrived while it was open. If the user
  /// had scrolled up before opening the menu, the anchor stays managed by the
  /// normal scroll handler.
  void _onMenuClosed() {
    if (!_menuSetAnchor) return;
    _menuSetAnchor = false;
    // Compute newEventCount before clearing the anchor, since it depends on it.
    final hasNew = newEventCount > 0;
    _scrollAnchorEventId = null;
    if (hasNew) {
      _scrolledUp.value = false;
      _cachedFilteredEvents = null;
      _cachedEventsKeyMap = null;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !scrollController.hasClients) return;
        await scrollController.scrollToIndex(
          bottomPaddingAutoScrollIndex,
          duration: FluffyThemes.animationDuration,
          preferPosition: AutoScrollPosition.begin,
        );
        setReadMarker();
      });
    }
  }

  void _openMenu(Event event, Offset? tapPosition) {
    _setScrollAnchorForMenu();
    if (PlatformInfos.isMobile) {
      showAdaptiveBottomSheet(
        context: context,
        builder: (context) {
          return MessageContextMenu(controller: this, event: event);
        },
        useRootNavigator: false,
      ).whenComplete(_onMenuClosed);
    } else {
      _contextMenuController?.remove();
      _contextMenuController = ContextMenuController(
        onRemove: () {
          setState(() {
            selectedEventId = null;
            eventGlobalKeys.removeWhere((_, key) => key.currentContext == null);
          });
          _onMenuClosed();
        },
      );

      setState(() {
        selectedEventId = event.eventId;
        _contextMenuController!.show(
          context: context,
          contextMenuBuilder: (context) {
            return _ContextMenuOverlay(
              tapPosition: tapPosition ?? Offset.zero,
              onDismiss: () => _contextMenuController?.remove(),
              selectedEventKey:
                  eventGlobalKeys[event.transactionId ?? event.eventId]!,
              child: MessageContextMenu(controller: this, event: event),
            );
          },
        );
      });
    }
  }

  String? selectedEventId;

  void onSelectMessage(Event event, Offset? tapPosition) {
    if (selectedEvents.isEmpty) {
      _openMenu(event, tapPosition);
    } else {
      onMultiSelect(event);
    }
  }

  void onMultiSelect(Event event) {
    if (selectedEvents.contains(event)) {
      setState(() => selectedEvents.remove(event));
    } else {
      setState(() => selectedEvents.add(event));
    }
    selectedEvents.sort((a, b) => a.originServerTs.compareTo(b.originServerTs));
  }

  void showReadReceipts({Event? event}) {
    event ??= selectedEvents.first;
    final receipts = room.getReceipts(timeline!, eventId: event.eventId);
    SeenByDialog(receipts).show(context);
  }

  void showEdits({Event? event}) {
    event ??= selectedEvents.first;
    final events = event.aggregatedEvents(timeline!, RelationshipTypes.edit);
    events.add(event);
    showAdaptiveBottomSheet(
      context: context,
      builder: (context) {
        return MessageEditsDialog(
          event: event!,
          events: events.sortedBy((element) => element.originServerTs).toSet(),
          controller: this,
        );
      },
    );
  }

  int? findChildIndexCallback(Key key) {
    // this method is called very often. As such, it has to be optimized for speed.
    if (key is! ValueKey) return null;
    final eventId = key.value;
    if (eventId is! String) return null;
    final index = eventsKeyMap[eventId];
    final nec = newEventCount;
    if (index == null || index < nec) return null;
    // +2 -> child 0 = spacer, 1 = typing indicator
    return (index - nec) + 1;
  }

  int? findNewEventsChildIndexCallback(Key key) {
    if (key is! ValueKey) return null;
    final eventId = key.value;
    if (eventId is! String) return null;
    final index = eventsKeyMap[eventId];
    if (index == null || index >= newEventCount) return null;
    return index;
  }

  void onInputBarSubmitted(_) {
    send();
  }

  void onAddPopupMenuButtonSelected(String choice) {
    if (choice == 'file') {
      sendFileAction();
    }
    if (choice == 'image') {
      sendFileAction(type: FileType.image);
    }
    if (choice == 'video') {
      sendFileAction(type: FileType.video);
    }
    if (choice == 'poll') {
      sendPollAction();
    }
    if (choice == 'camera') {
      openCameraAction();
    }
    if (choice == 'camera-video') {
      openVideoCameraAction();
    }
    if (choice == 'location') {
      sendLocationAction();
    }
  }

  void unpinEvent(String eventId) async {
    final response = await showOkCancelAlertDialog(
      context: context,
      title: L10n.of(context).unpin,
      message: L10n.of(context).confirmEventUnpin,
      okLabel: L10n.of(context).unpin,
      cancelLabel: L10n.of(context).cancel,
    );
    if (response == OkCancelResult.ok) {
      final events = room.pinnedEventIds
        ..removeWhere((oldEvent) => oldEvent == eventId);
      showFutureLoadingDialog(
        context: context,
        future: () => room.setPinnedEvents(events),
      );
    }
  }

  void pinEvent({Event? event}) {
    final pinnedEventIds = room.pinnedEventIds;
    final selectedEventIds = event != null
        ? [event.eventId]
        : selectedEvents.map((e) => e.eventId).toSet();
    final unpin =
        selectedEventIds.length == 1 &&
        pinnedEventIds.contains(selectedEventIds.single);
    if (unpin) {
      pinnedEventIds.removeWhere(selectedEventIds.contains);
    } else {
      pinnedEventIds.addAll(selectedEventIds);
    }
    showFutureLoadingDialog(
      context: context,
      future: () => room.setPinnedEvents(pinnedEventIds),
    );
  }

  Timer? _storeInputTimeoutTimer;
  static const Duration _storeInputTimeout = Duration(milliseconds: 500);

  void onInputBarChanged(String text) {
    if (_inputTextIsEmpty != text.isEmpty) {
      setState(() {
        _inputTextIsEmpty = text.isEmpty;
      });
    }

    _storeInputTimeoutTimer?.cancel();
    _storeInputTimeoutTimer = Timer(_storeInputTimeout, () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('draft_$roomId', text);
    });
    if (text.endsWith(' ') && Matrix.of(context).hasComplexBundles) {
      final clients = currentRoomBundle;
      for (final client in clients) {
        final prefix = client!.sendPrefix;
        if ((prefix.isNotEmpty) &&
            text.toLowerCase() == '${prefix.toLowerCase()} ') {
          setSendingClient(client);
          setState(() {
            sendController.clear();
          });
          return;
        }
      }
    }
    if (shouldSendTypingNotifications(room.client, roomId)) {
      typingCoolDown?.cancel();
      typingCoolDown = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        typingCoolDown = null;
        currentlyTyping = false;
        room.setTyping(false);
      });
      typingTimeout ??= Timer(const Duration(seconds: 30), () {
        typingTimeout = null;
        currentlyTyping = false;
      });
      if (!currentlyTyping) {
        currentlyTyping = true;
        room.setTyping(
          true,
          timeout: const Duration(seconds: 30).inMilliseconds,
        );
      }
    }
  }

  final Map<String, GlobalKey> eventGlobalKeys = {};

  bool _inputTextIsEmpty = true;

  bool get isArchived =>
      {Membership.leave, Membership.ban}.contains(room.membership);

  void showEventInfo([Event? event]) =>
      (event ?? selectedEvents.single).showInfoDialog(context);

  void onPhoneButtonTap() async {
    // VoIP required Android SDK 21
    if (PlatformInfos.isAndroid) {
      DeviceInfoPlugin().androidInfo.then((value) {
        if (value.version.sdkInt < 21) {
          Navigator.pop(context);
          showOkAlertDialog(
            context: context,
            title: L10n.of(context).unsupportedAndroidVersion,
            message: L10n.of(context).unsupportedAndroidVersionLong,
            okLabel: L10n.of(context).close,
          );
        }
      });
    }
    final callType = await showModalActionPopup<CallType>(
      context: context,
      title: L10n.of(context).warning,
      message: L10n.of(context).videoCallsBetaWarning,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          label: L10n.of(context).voiceCall,
          icon: const Icon(Icons.phone_outlined),
          value: CallType.kVoice,
        ),
        AdaptiveModalAction(
          label: L10n.of(context).videoCall,
          icon: const Icon(Icons.video_call_outlined),
          value: CallType.kVideo,
        ),
      ],
    );
    if (callType == null) return;

    final voipPlugin = Matrix.of(context).voipPlugin;
    try {
      final session = await voipPlugin!.voip.inviteToCall(room, callType);
      voipPlugin.addCallingOverlay(session.callId, session);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
      Logs().e("onPhoneButtonTap", e);
    }
  }

  void onLiveKitCallButtonTap() async {
    final callType = await showModalActionPopup<String>(
      context: context,
      title: L10n.of(context).elementCallExperimental,
      message: L10n.of(context).chooseCallType,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          label: L10n.of(context).p2pCall,
          icon: const Icon(Icons.phone_outlined),
          value: 'p2p',
        ),
        AdaptiveModalAction(
          label: L10n.of(context).elementCall,
          icon: const Icon(Icons.video_call_outlined),
          value: 'element_call',
        ),
      ],
    );
    if (callType == null) return;

    if (callType == 'p2p') {
      // Use traditional P2P call
      final voipCallType = await showModalActionPopup<CallType>(
        context: context,
        title: L10n.of(context).warning,
        message: L10n.of(context).videoCallsBetaWarning,
        cancelLabel: L10n.of(context).cancel,
        actions: [
          AdaptiveModalAction(
            label: L10n.of(context).voiceCall,
            icon: const Icon(Icons.phone_outlined),
            value: CallType.kVoice,
          ),
          AdaptiveModalAction(
            label: L10n.of(context).videoCall,
            icon: const Icon(Icons.video_call_outlined),
            value: CallType.kVideo,
          ),
        ],
      );
      if (voipCallType == null) return;

      final voipPlugin = Matrix.of(context).voipPlugin;
      try {
        final session = await voipPlugin!.voip.inviteToCall(room, voipCallType);
        voipPlugin.addCallingOverlay(session.callId, session);
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
        Logs().e("onPhoneButtonTap", e);
      }
    } else if (callType == 'element_call') {
      // Use Element Call (LiveKit)
      try {
        await openLiveKitCall(context, roomId);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.of(context).errorWithMessage('Element Call: $e'),
            ),
          ),
        );
        Logs().e("onLiveKitCallButtonTap", e);
      }
    }
  }

  void cancelReplyEventAction() => setState(() {
    if (editEvent != null) {
      sendController.text = pendingText;
      pendingText = '';
    }
    replyEvent = null;
    editEvent = null;
    editImageFile = null;
    editContentWarning = _originalContentWarning = null;
  });

  late final ValueNotifier<bool> _displayChatDetailsColumn;

  void toggleDisplayChatDetailsColumn() async {
    await AppSettings.displayChatDetailsColumn.setItem(
      !_displayChatDetailsColumn.value,
    );
    _displayChatDetailsColumn.value = !_displayChatDetailsColumn.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: ChatView(this)),
        AnimatedSize(
          duration: FluffyThemes.animationDuration,
          curve: FluffyThemes.animationCurve,
          child: ValueListenableBuilder(
            valueListenable: _displayChatDetailsColumn,
            builder: (context, displayChatDetailsColumn, _) {
              if (!FluffyThemes.isThreeColumnMode(context) ||
                  room.membership != Membership.join ||
                  !displayChatDetailsColumn) {
                return const SizedBox(height: double.infinity, width: 0);
              }
              return Container(
                width: FluffyThemes.columnWidth,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(width: 1, color: theme.dividerColor),
                  ),
                ),
                child: ChatDetails(
                  roomId: roomId,
                  embeddedCloseButton: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: toggleDisplayChatDetailsColumn,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContextMenuOverlay extends StatefulWidget {
  final Offset tapPosition;
  final VoidCallback onDismiss;
  final Widget child;
  final GlobalKey selectedEventKey;

  const _ContextMenuOverlay({
    required this.tapPosition,
    required this.onDismiss,
    required this.child,
    required this.selectedEventKey,
  });

  @override
  State<_ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<_ContextMenuOverlay> {
  Rect? _messageRect;

  @override
  void initState() {
    super.initState();
    _updateRect();
  }

  @override
  void didUpdateWidget(_ContextMenuOverlay old) {
    super.didUpdateWidget(old);
    if (widget.selectedEventKey != old.selectedEventKey) {
      _updateRect();
    }
  }

  void _updateRect() {
    final ctx = widget.selectedEventKey.currentContext;
    if (ctx == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateRect();
      });
      return;
    }

    final box = ctx.findRenderObject() as RenderBox;
    if (!box.hasSize) return;

    final pos = box.localToGlobal(Offset.zero);
    setState(() {
      _messageRect = Rect.fromLTWH(
        pos.dx,
        pos.dy,
        box.size.width,
        box.size.height,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          children: [
            GestureDetector(
              onTap: widget.onDismiss,
              behavior: HitTestBehavior.translucent,
              child: ClipPath(
                clipper: MultiHoleClipper(holes: [?_messageRect]),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: AnimatedOpacity(
                    opacity: _messageRect == null ? 0 : 1,
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
              delegate: _ContextMenuLayoutDelegate(
                tapPosition: widget.tapPosition,
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.3, end: 1.0),
                duration: FluffyThemes.animationDuration,
                curve: FluffyThemes.animationCurve,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.scale(
                      scale: value,
                      alignment: _expansionAlignment(widget.tapPosition, size),
                      child: child,
                    ),
                  );
                },
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }

  Alignment _expansionAlignment(Offset tap, Size size) {
    if (size.isEmpty) return Alignment.topLeft;
    final fx = (tap.dx / size.width).clamp(0.0, 1.0);
    final fy = (tap.dy / size.height).clamp(0.0, 1.0);
    return Alignment(fx * 2 - 1, fy * 2 - 1);
  }
}

class _ContextMenuLayoutDelegate extends SingleChildLayoutDelegate {
  final Offset tapPosition;

  _ContextMenuLayoutDelegate({required this.tapPosition});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const margin = 10.0;

    var left = tapPosition.dx;
    var top = tapPosition.dy;

    if (left + childSize.width > size.width - margin) {
      left = size.width - childSize.width - margin;
    }
    if (left < margin) left = margin;

    if (top + childSize.height > size.height - margin) {
      top = tapPosition.dy - childSize.height;
    }
    if (top < margin) top = margin;

    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_ContextMenuLayoutDelegate oldDelegate) {
    return tapPosition != oldDelegate.tapPosition;
  }
}
