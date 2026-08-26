import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/avatar_history.dart';
import 'package:extera_next/utils/client_profile_extension.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/favourite_stickers_extension.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/pages/image_viewer/image_viewer_view.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/show_scaffold_dialog.dart';
import 'package:extera_next/widgets/share_scaffold_dialog.dart';
import '../../widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import '../../utils/matrix_sdk_extensions/event_extension.dart';

class ImageViewer extends StatefulWidget {
  final Event event;
  final Timeline? timeline;
  final BuildContext outerContext;

  const ImageViewer(
    this.event, {
    required this.outerContext,
    this.timeline,
    super.key,
  });

  @override
  ImageViewerController createState() => ImageViewerController();
}

class ImageViewerController extends State<ImageViewer> {
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    allEvents =
        widget.timeline?.events
            .where(
              (event) => {
                MessageTypes.Image,
                MessageTypes.Sticker,
                if (PlatformInfos.supportsVideoPlayer) MessageTypes.Video,
              }.contains(event.messageType),
            )
            .toList()
            .reversed
            .toList() ??
        [widget.event];
    var index = allEvents.indexWhere(
      (event) => event.eventId == widget.event.eventId,
    );
    if (index < 0) index = 0;
    pageController = PageController(initialPage: index);
  }

  late final PageController pageController;

  late final List<Event> allEvents;

  void onKeyEvent(KeyEvent event) {
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        if (canGoBack) prevImage();
        break;
      case LogicalKeyboardKey.arrowDown:
        if (canGoNext) nextImage();
        break;
    }
  }

  void prevImage() async {
    await pageController.previousPage(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
    if (!mounted) return;
    setState(() {});
  }

  void nextImage() async {
    await pageController.nextPage(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
    if (!mounted) return;
    setState(() {});
  }

  int get _index => pageController.page?.toInt() ?? 0;

  Event get currentEvent => allEvents[_index];

  bool get canGoNext => _index < allEvents.length - 1;

  bool get canGoBack => _index > 0;

  /// Forward this image to another room.
  void forwardAction() => showScaffoldDialog(
    context: context,
    builder: (context) =>
        ShareScaffoldDialog(items: [ContentShareItem(currentEvent.content)]),
  );

  /// Save this file with a system call.
  void saveFileAction(BuildContext context) => currentEvent.saveFile(context);

  /// Save this file with a system call.
  void shareFileAction(BuildContext context) => currentEvent.shareFile(context);

  /// The original attachment mxc of the currently viewed image, or null for
  /// events without an attachment (e.g. stickers sent without url are rare;
  /// videos/images always have one).
  Uri? get _attachmentMxc => currentEvent.attachmentMxcUrl;

  /// Opens the extended actions sheet: reuse this media as sticker or as any
  /// kind of avatar without re-uploading it.
  void showMoreActions(BuildContext context) {
    final event = currentEvent;
    final mxc = _attachmentMxc;
    final client = event.room.client;
    final room = event.room;

    Future<void> run(
      String message,
      Future<void> Function() task, {
      bool recordHistory = false,
    }) => _runAction(context, mxc, message, task, recordHistory);

    final actions = <Widget>[
      if (mxc != null)
        ListTile(
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: Text(L10n.of(context).addToMyStickers),
          onTap: () {
            Navigator.of(context).pop();
            run(L10n.of(context).addedToMyStickers, () async {
              await client.addFavouriteSticker(
                ImagePackImageContent.fromJson({
                  'url': mxc.toString(),
                  'body':
                      event.content.tryGet<String>('filename') ?? event.body,
                  if (event.infoMap.isNotEmpty) 'info': event.infoMap,
                }),
              );
            });
          },
        ),
      if (mxc != null)
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(L10n.of(context).addToAvatarHistory),
          onTap: () {
            Navigator.of(context).pop();
            run(
              L10n.of(context).addedToAvatarHistory,
              () => AvatarHistory.record(mxc.toString()),
            );
          },
        ),
      if (mxc != null)
        ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(L10n.of(context).setAsMyGlobalAvatar),
          onTap: () => _confirmAndRun(
            context,
            L10n.of(context).setAsMyGlobalAvatar,
            () => run(L10n.of(context).setAsMyGlobalAvatar, () async {
              await client.setProfileField(client.userID!, 'avatar_url', {
                'avatar_url': mxc.toString(),
              });
              await client.refreshOwnProfile();
            }, recordHistory: true),
          ),
        ),
      if (mxc != null &&
          room.membership == Membership.join &&
          room.canChangeStateEvent(EventTypes.RoomMember))
        ListTile(
          leading: const Icon(Icons.face_outlined),
          title: Text(L10n.of(context).setAsMyRoomAvatar),
          onTap: () => _confirmAndRun(
            context,
            L10n.of(context).setAsMyRoomAvatar,
            () => run(
              L10n.of(context).setAsMyRoomAvatar,
              () => _setOwnRoomAvatar(room, mxc),
              recordHistory: true,
            ),
          ),
        ),
      if (mxc != null && room.canChangeStateEvent(EventTypes.RoomAvatar))
        ListTile(
          leading: const Icon(Icons.image_outlined),
          title: Text(L10n.of(context).setAsRoomIcon),
          onTap: () => _confirmAndRun(
            context,
            L10n.of(context).setAsRoomIcon,
            () => run(
              L10n.of(context).setAsRoomIcon,
              () => room.client.setRoomStateWithKey(
                room.id,
                EventTypes.RoomAvatar,
                '',
                {'url': mxc.toString()},
              ),
              recordHistory: true,
            ),
          ),
        ),
      if (mxc != null) ..._spaceTiles(context, mxc),
    ];

    showAdaptiveBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Material(
        // Opaque surface so options stay readable over the dark viewer.
        color: Theme.of(sheetContext).colorScheme.surface,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: actions),
          ),
        ),
      ),
    );
  }

  /// Asks the user to confirm applying the current image as [title].
  Future<bool> _confirmApply(BuildContext context, String title) async =>
      OkCancelResult.ok ==
      await showOkCancelAlertDialog(
        context: context,
        title: title,
        message: L10n.of(context).applyImageConfirmation,
      );

  /// Confirms, closes the actions sheet, then runs [action]. Cancelling
  /// keeps the sheet open.
  Future<void> _confirmAndRun(
    BuildContext context,
    String title,
    Future<void> Function() action,
  ) async {
    if (!await _confirmApply(context, title)) return;
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await action();
  }

  /// Runs [task] behind a loading dialog, records the attachment in the
  /// avatar history when [recordHistory] is set and shows [message] on
  /// success.
  Future<void> _runAction(
    BuildContext context,
    Uri? mxc,
    String message,
    Future<void> Function() task,
    bool recordHistory,
  ) async {
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        await task();
        if (recordHistory && mxc != null) {
          await AvatarHistory.record(mxc.toString());
        }
      },
    );
    if (!context.mounted || result.error != null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<Widget> _spaceTiles(BuildContext context, Uri mxc) {
    final client = currentEvent.room.client;
    final spaces = client.rooms
        .where(
          (room) =>
              room.isSpace &&
              room.membership == Membership.join &&
              room.canChangeStateEvent(EventTypes.RoomAvatar),
        )
        .toList();
    if (spaces.isEmpty) return const [];
    return [
      ListTile(
        leading: const Icon(Icons.workspaces_outlined),
        title: Text(L10n.of(context).setAsSpaceIcon),
        onTap: () async {
          final space = spaces.length == 1
              ? spaces.single
              : await showAdaptiveBottomSheet<Room>(
                  context: context,
                  builder: (sheetContext) => Material(
                    color: Theme.of(sheetContext).colorScheme.surface,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: spaces.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return ListTile(
                            title: Text(L10n.of(context).chooseSpace),
                          );
                        }
                        final space = spaces[i - 1];
                        return ListTile(
                          leading: Avatar(
                            mxContent: space.avatar,
                            name: space.getLocalizedDisplayname(),
                          ),
                          title: Text(space.getLocalizedDisplayname()),
                          onTap: () => Navigator.of(context).pop(space),
                        );
                      },
                    ),
                  ),
                );
          if (!context.mounted || space == null) return;
          if (!await _confirmApply(context, L10n.of(context).setAsSpaceIcon)) {
            return;
          }
          Navigator.of(context).pop();
          _runAction(
            context,
            mxc,
            L10n.of(context).setAsSpaceIcon,
            () => space.client.setRoomStateWithKey(
              space.id,
              EventTypes.RoomAvatar,
              '',
              {'url': mxc.toString()},
            ),
            true,
          );
        },
      ),
    ];
  }

  Future<void> _setOwnRoomAvatar(Room room, Uri mxc) async {
    final userId = room.client.userID!;
    final content =
        room.getState(EventTypes.RoomMember, userId)?.content.copy() ??
        <String, Object?>{'membership': room.membership.name};
    content['avatar_url'] = mxc.toString();
    await room.client.setRoomStateWithKey(
      room.id,
      EventTypes.RoomMember,
      userId,
      content,
    );
    // Local echo so the UI updates instantly instead of waiting for the
    // sync round trip to deliver our own state change back.
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        senderId: userId,
        stateKey: userId,
        content: content,
      ),
    );
  }

  static const maxScaleFactor = 1.5;

  /// Go back if user swiped it away
  void onInteractionEnds(ScaleEndDetails endDetails) {
    if (PlatformInfos.usesTouchscreen == false) {
      if (endDetails.velocity.pixelsPerSecond.dy >
          MediaQuery.sizeOf(context).height * maxScaleFactor) {
        Navigator.of(context, rootNavigator: false).pop();
      }
    }
  }

  @override
  void dispose() {
    focusNode.dispose();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ImageViewerView(this);
}
