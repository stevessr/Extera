import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/chat.dart';
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

        return ChatPageWithRoom(
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
