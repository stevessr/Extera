import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat_details/chat_details_view.dart';
import 'package:extera_next/pages/settings/settings.dart';
import 'package:extera_next/utils/clean_exif.dart';
import 'package:extera_next/utils/file_selector.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/wallpaper.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/matrix.dart';

enum AliasActions { copy, delete, setCanonical }

class ChatDetails extends StatefulWidget {
  final String roomId;
  final Widget? embeddedCloseButton;

  const ChatDetails({
    super.key,
    required this.roomId,
    this.embeddedCloseButton,
  });

  @override
  ChatDetailsController createState() => ChatDetailsController();
}

class ChatDetailsController extends State<ChatDetails> {
  bool displaySettings = false;

  void toggleDisplaySettings() =>
      setState(() => displaySettings = !displaySettings);

  String? get roomId => widget.roomId;

  void setDisplaynameAction() async {
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context).changeTheNameOfTheGroup,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      initialText: room.getLocalizedDisplayname(MatrixLocals(L10n.of(context))),
    );
    if (input == null) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setName(input),
    );
    if (success.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).displaynameHasBeenChanged)),
      );
    }
  }

  Future<void> setOwnDisplaynameAction() async {
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final userId = room.client.userID;
    if (userId == null) return;

    final ownUser = room.getState(EventTypes.RoomMember, userId)?.asUser(room);
    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context).editDisplayname,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      hintText: L10n.of(context).displaynameHint,
      initialText: ownUser?.displayName ?? '',
    );
    if (input == null) return;

    final displayName = input.trim();
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => _setOwnRoomMemberProfile(
        room,
        displayName: displayName.isEmpty ? null : displayName,
        clearDisplayName: displayName.isEmpty,
      ),
    );
    if (result.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).displaynameHasBeenChanged)),
      );
    }
  }

  void setTopicAction() async {
    final room = Matrix.of(context).client.getRoomById(roomId!)!;
    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context).setChatDescription,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      hintText: L10n.of(context).noChatDescriptionYet,
      initialText: room.topic,
      minLines: 4,
      maxLines: 8,
    );
    if (input == null) return;
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.setDescription(input),
    );
    if (success.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).chatDescriptionHasBeenChanged)),
      );
    }
  }

  void goToEmoteSettings() async {
    context.push('/rooms/$roomId/details/emotes');
  }

  /// Whether this room overrides the global wallpaper, shown as the subtitle
  /// of the wallpaper tile.
  bool get hasCustomWallpaper => roomId != null && hasRoomWallpaper(roomId!);

  void goToWallpaperSettings() async {
    await context.push('/rooms/$roomId/details/wallpaper');
    if (mounted) setState(() {});
  }

  void setAvatarAction() async {
    final room = Matrix.of(context).client.getRoomById(roomId!);
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: L10n.of(context).openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: L10n.of(context).openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (room?.avatar != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: L10n.of(context).delete,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: L10n.of(context).editRoomAvatar,
            cancelLabel: L10n.of(context).cancel,
            actions: actions,
          );
    if (action == null) return;
    if (action == AvatarAction.remove) {
      await showFutureLoadingDialog(
        context: context,
        future: () => room!.setAvatar(null),
      );
      return;
    }
    final file = await _pickAvatarFile(action);
    if (file == null) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => room!.setAvatar(file),
    );
  }

  Future<void> setOwnAvatarAction() async {
    final room = Matrix.of(context).client.getRoomById(roomId!);
    final userId = room?.client.userID;
    if (room == null || userId == null) return;

    final ownUser = room.getState(EventTypes.RoomMember, userId)?.asUser(room);
    final currentAvatar = ownUser?.avatarUrl;
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: L10n.of(context).openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: L10n.of(context).openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (currentAvatar != null && currentAvatar.toString().isNotEmpty)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: L10n.of(context).removeYourAvatar,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: L10n.of(context).changeYourAvatar,
            cancelLabel: L10n.of(context).cancel,
            actions: actions,
          );
    if (action == null) return;
    if (action == AvatarAction.remove) {
      await showFutureLoadingDialog(
        context: context,
        future: () => _setOwnRoomMemberProfile(room, clearAvatar: true),
      );
      return;
    }

    final file = await _pickAvatarFile(action);
    if (file == null) return;
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final uploadResponse = await room.client.uploadContent(
          file.bytes,
          filename: file.name,
        );
        await _setOwnRoomMemberProfile(
          room,
          avatarUrl: uploadResponse.toString(),
        );
      },
    );
  }

  Future<MatrixFile?> _pickAvatarFile(AvatarAction action) async {
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return null;
      return MatrixFile(
        bytes: Uint8List.fromList(
          ExifCleaner.removeExifData(await result.readAsBytes()),
        ),
        name: result.path,
      );
    }

    final picked = await selectFiles(
      context,
      allowMultiple: false,
      type: FileType.image,
    );
    final pickedFile = picked.firstOrNull;
    if (pickedFile == null) return null;
    return MatrixFile(
      bytes: Uint8List.fromList(await pickedFile.readAsBytes()),
      name: pickedFile.name,
    );
  }

  Future<void> _setOwnRoomMemberProfile(
    Room room, {
    String? displayName,
    bool clearDisplayName = false,
    String? avatarUrl,
    bool clearAvatar = false,
  }) async {
    final userId = room.client.userID;
    if (userId == null) return;

    final content =
        room.getState(EventTypes.RoomMember, userId)?.content.copy() ??
        <String, Object?>{'membership': room.membership.name};
    if (clearDisplayName) {
      content.remove('displayname');
    } else if (displayName != null) {
      content['displayname'] = displayName;
    }
    if (clearAvatar) {
      content.remove('avatar_url');
    } else if (avatarUrl != null) {
      content['avatar_url'] = avatarUrl;
    }

    await room.client.setRoomStateWithKey(
      room.id,
      EventTypes.RoomMember,
      userId,
      content,
    );
  }

  static const fixedWidth = 360.0;

  @override
  Widget build(BuildContext context) => ChatDetailsView(this);
}
