import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/chat_input_row.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';
import '../../config/themes.dart';
import 'chat.dart';
import 'events/reply_content.dart';

class ReplyDisplay extends StatelessWidget {
  static const double height = 64.0;

  final ChatController controller;
  const ReplyDisplay(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      height: controller.editEvent != null || controller.replyEvent != null
          ? ReplyDisplay.height
          : 0,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 4),
          SizedBox(
            width: ChatInputRow.height,
            height: ChatInputRow.height,
            child: IconButton(
              tooltip: L10n.of(context).close,
              icon: const Icon(Icons.close),
              onPressed: controller.cancelReplyEventAction,
            ),
          ),
          Expanded(
            child: controller.replyEvent != null
                ? Padding(
                    padding: const .symmetric(vertical: 4),
                    child: ReplyContent(
                      controller.replyEvent!,
                      noBubble: true,
                      timeline: controller.timeline,
                    ),
                  )
                : _EditContent(
                    controller.editEvent?.getDisplayEvent(controller.timeline!),
                  ),
          ),
          if (controller.replyEvent != null && controller.editEvent == null)
            SizedBox(
              width: ChatInputRow.height,
              height: ChatInputRow.height,
              child: IconButton(
                tooltip: L10n.of(context).mention,
                icon: controller.replyMention
                    ? const Icon(Icons.notifications_active_outlined)
                    : const Icon(Icons.notifications_off_outlined),
                onPressed: () {
                  controller.setReplyMention(!controller.replyMention);
                },
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _EditContent extends StatelessWidget {
  final Event? event;

  const _EditContent(this.event);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = this.event;
    if (event == null) {
      return const SizedBox.shrink();
    }
    return Row(
      children: <Widget>[
        Icon(Icons.edit, color: theme.colorScheme.primary),
        Container(width: 15.0),
        Text(
          event.calcLocalizedBodyFallback(
            MatrixLocals(L10n.of(context)),
            withSenderNamePrefix: false,
            hideReply: true,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(color: theme.textTheme.bodyMedium!.color),
        ),
      ],
    );
  }
}
