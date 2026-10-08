import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ThreadPreview extends StatelessWidget {
  final Room room;
  final Event event;
  final Thread thread;

  const ThreadPreview({
    required this.event,
    required this.thread,
    required this.room,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (thread.lastEvent == null) {
      return const SizedBox.shrink();
    }

    return InkWell(
      child: Row(
        mainAxisSize: .min,
        children: [
          Icon(
            (thread.hasNewMessages)
                ? Icons.mark_chat_unread_outlined
                : Icons.chat_bubble_outline,
            color: Colors.grey[200],
            size: 20,
          ),
          const SizedBox(width: 16),
          if (thread.count != null) ...[
            Text(L10n.of(context).repliesInThread(thread.count!)),
            const SizedBox(width: 16),
          ],
          Avatar(
            mxContent: thread.lastEvent!.senderFromMemoryOrFallback.avatarUrl,
            name: thread.lastEvent!.senderFromMemoryOrFallback
                .calcDisplayname(),
            size: 24,
          ),
          const SizedBox(width: 6),
          thread.lastEvent != null
              ? Row(
                  mainAxisSize: .min,
                  spacing: 4,
                  children: [
                    Text(
                      '${thread.lastEvent!.senderFromMemoryOrFallback.calcDisplayname()}: ',
                    ),
                    Text(
                      thread.lastEvent!.text.length > 32
                          ? "${thread.lastEvent!.text.substring(0, 32)}..."
                          : thread.lastEvent!.text,
                    ),
                  ],
                )
              : Text('Thread'),
        ],
      ),
      onTap: () =>
          context.push('/rooms/${event.roomId}/threads/${event.eventId}'),
    );
  }
}
