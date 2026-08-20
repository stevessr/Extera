import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/chat_input_row.dart';
import 'package:extera_next/utils/content_warning.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:extera_next/widgets/mxc_image.dart';
import '../../config/app_config.dart';
import '../../config/themes.dart';
import 'chat.dart';
import 'events/reply_content.dart';

enum _EditImageAction { edit, replace, undo }

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
          if (controller.isEditingImage) _EditImageButton(controller),
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
          if (controller.isEditingImage)
            SizedBox(
              width: ChatInputRow.height,
              height: ChatInputRow.height,
              child: _ContentWarningButton(controller),
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

/// Thumbnail of the attachment of the image message being edited.
///
/// Tapping it offers to edit or replace the image. As long as it is left
/// untouched the original attachment is kept and nothing is uploaded on send.
class _EditImageButton extends StatelessWidget {
  final ChatController controller;

  const _EditImageButton(this.controller);

  void _showActions(BuildContext context) async {
    final l10n = L10n.of(context);
    final hasReplacement = controller.editImageFile != null;

    final action = await showModalActionPopup<_EditImageAction>(
      context: context,
      actions: [
        AdaptiveModalAction(
          value: _EditImageAction.edit,
          label: l10n.editImage,
          icon: const Icon(Icons.brush_outlined),
        ),
        AdaptiveModalAction(
          value: _EditImageAction.replace,
          label: l10n.replaceImage,
          icon: const Icon(Icons.photo_library_outlined),
        ),
        if (hasReplacement)
          AdaptiveModalAction(
            value: _EditImageAction.undo,
            label: l10n.undoImageChange,
            icon: const Icon(Icons.undo_outlined),
          ),
      ],
    );

    switch (action) {
      case _EditImageAction.edit:
        controller.editEditImageAction();
      case _EditImageAction.replace:
        controller.replaceEditImageAction();
      case _EditImageAction.undo:
        controller.resetEditImageAction();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius / 2);
    final replacement = controller.editImageFile;
    final event = controller.editEvent;
    final timeline = controller.timeline;
    const size = 44.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () => _showActions(context),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            ClipRRect(
              borderRadius: borderRadius,
              child: SizedBox.square(
                dimension: size,
                child: replacement != null
                    ? Image.memory(
                        replacement.bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : event == null || timeline == null
                    ? const SizedBox.shrink()
                    : MxcImage(
                        event: event.getDisplayEvent(timeline),
                        fit: BoxFit.cover,
                        width: size,
                        height: size,
                      ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.edit,
                size: 12,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user change the content warning of the image being edited.
///
/// Mirrors the picker of the send dialog, so that setting a warning afterwards
/// looks the same as setting it while sending.
class _ContentWarningButton extends StatelessWidget {
  final ChatController controller;

  const _ContentWarningButton(this.controller);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final current = controller.editContentWarning;

    return PopupMenuButton<String?>(
      initialValue: current,
      onSelected: controller.setEditContentWarning,
      tooltip: '${l10n.contentWarning}: ${contentWarningLabel(l10n, current)}',
      icon: Icon(
        current == null
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined,
        color: current == null ? null : Theme.of(context).colorScheme.primary,
      ),
      itemBuilder: (context) => [
        PopupMenuItem(value: null, child: Text(l10n.none)),
        for (final type in ContentWarningType.values)
          PopupMenuItem(value: type.value, child: Text(type.label(l10n))),
      ],
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
