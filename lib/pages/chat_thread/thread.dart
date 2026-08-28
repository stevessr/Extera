import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/chat.dart';
import 'package:extera_next/utils/privacy_options.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/share_scaffold_dialog.dart';

class ThreadPage extends StatefulWidget {
  final String roomId;
  final List<ShareItem>? shareItems;
  final String? threadRootEventId;
  final String? eventId;

  const ThreadPage({
    super.key,
    required this.roomId,
    required this.threadRootEventId,
    this.eventId,
    this.shareItems,
  });

  @override
  State<ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<ThreadPage> {
  late final Future<Thread?> _threadFuture = _resolveThread();

  Room? get _room => Matrix.of(context).client.getRoomById(widget.roomId);

  /// Looks up the thread to display.
  ///
  /// [Room.threads] is only filled while syncing and by an explicit
  /// [Room.loadThreadsFromServer], so opening a thread through its route -
  /// from a link, a search result or a jump to a thread reply - regularly
  /// finds it empty. Fall back to the database and finally to the root event.
  Future<Thread?> _resolveThread() async {
    final room = _room;
    final rootEventId = widget.threadRootEventId;
    if (room == null || rootEventId == null) return null;

    final cached = room.threads[rootEventId];
    if (cached != null) return cached;

    try {
      final stored = (await room.getThreads())[rootEventId];
      if (stored != null) return room.threads[rootEventId] = stored;

      final rootEvent = await room.getEventById(rootEventId);
      if (rootEvent == null) return null;
      return room.threads[rootEventId] = await room.getThread(rootEvent);
    } catch (e, s) {
      Logs().w('Unable to open thread $rootEventId', e, s);
      return null;
    }
  }

  Widget _messageScaffold(String message) => Scaffold(
    appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
    body: Center(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_room == null) {
      return _messageScaffold(
        L10n.of(context).youAreNoLongerParticipatingInThisChat,
      );
    }

    return FutureBuilder<Thread?>(
      future: _threadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator.adaptive()),
          );
        }

        final thread = snapshot.data;
        final room = _room;
        if (thread == null || room == null) {
          return _messageScaffold(L10n.of(context).unableToOpenThread);
        }

        return _ThreadChatPageWithRoom(
          key: Key(
            'chat_page_${widget.roomId}_${widget.threadRootEventId}_${widget.eventId}',
          ),
          room: room,
          thread: thread,
          shareItems: widget.shareItems,
          eventId: widget.eventId,
        );
      },
    );
  }
}

class _ThreadChatPageWithRoom extends ChatPageWithRoom {
  const _ThreadChatPageWithRoom({
    super.key,
    required super.room,
    required super.thread,
    super.shareItems,
    super.eventId,
  });

  @override
  ChatController createState() => _ThreadChatController();
}

class _ThreadChatController extends ChatController {
  Future<void>? _threadReadMarkerFuture;

  @override
  void setReadMarker({String? eventId}) {
    if (_threadReadMarkerFuture != null) return;
    if (scrolledUpNotifier.value) return;
    if (scrollUpBannerEventId != null) return;

    final currentTimeline = timeline;
    final currentThread = thread;
    if (currentTimeline == null ||
        currentTimeline.events.isEmpty ||
        currentThread == null) {
      return;
    }

    if (eventId == null) {
      for (final event in currentTimeline.events) {
        if (event.status.isSynced) {
          eventId = event.eventId;
          break;
        }
      }
    }
    if (eventId == null) return;

    Logs().d(
      'Set thread read marker ${currentThread.rootEvent.eventId}...',
      eventId,
    );

    // A room can already be fully read while one of its threads is still
    // unread. Do not reuse ChatController's room-level unread fast path here:
    // post a threaded receipt for the latest synced thread event explicitly.
    _threadReadMarkerFuture = currentTimeline
        .setReadMarker(
          eventId: eventId,
          public: shouldSendPublicReadReceipts(room.client, roomId),
        )
        .then((_) {
          // Remove the local unread indicator immediately instead of waiting
          // for the next /sync response to echo the threaded receipt.
          currentThread.notificationCount = 0;
          currentThread.highlightCount = 0;
          if (mounted) setState(() {});
        })
        .catchError((Object error, StackTrace stackTrace) {
          Logs().w('Unable to set thread read marker', error, stackTrace);
        })
        .whenComplete(() {
          // Always unlock so a transient receipt failure can be retried by the
          // next existing read-marker trigger.
          _threadReadMarkerFuture = null;
        });

    unawaited(_threadReadMarkerFuture);
  }
}
