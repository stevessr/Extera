import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart' show FileType;
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/clean_exif.dart';
import 'package:extera_next/utils/file_selector.dart';
import 'package:extera_next/utils/avatar_history.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:extera_next/widgets/avatar_history_picker.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';
import 'package:extera_next/widgets/matrix.dart';

import 'chat_room_profile_view.dart';

enum _AvatarChoice { file, history }

/// Edits the own member state of a single room, so that name and avatar can
/// differ from the account profile just for this chat (the equivalent of the
/// `/myroomnick` and `/myroomavatar` commands).
class ChatRoomProfile extends StatefulWidget {
  final String roomId;

  const ChatRoomProfile({required this.roomId, super.key});

  @override
  ChatRoomProfileController createState() => ChatRoomProfileController();
}

class ChatRoomProfileController extends State<ChatRoomProfile> {
  /// Local echo of the member state; takes precedence over the possibly stale
  /// room state until the sync catches up.
  Map<String, dynamic>? _overrideContent;

  /// Account profile, used as the display fallback while this chat has no
  /// in-chat override for name or avatar.
  Future<Profile>? _accountProfile;

  Future<Profile> get accountProfile =>
      _accountProfile ??= Matrix.of(context).client.fetchOwnProfile();

  Room get room => Matrix.of(context).client.getRoomById(widget.roomId)!;

  Map<String, dynamic> get _memberContent =>
      _overrideContent ??
      room.getState(EventTypes.RoomMember, room.client.userID!)?.content ??
      const {};

  String? get displayName => _memberContent['displayname'] as String?;

  Uri? get avatarUrl {
    final source = _memberContent['avatar_url'] as String?;
    return source == null ? null : Uri.parse(source);
  }

  bool get isCustomized =>
      _memberContent.containsKey('displayname') ||
      _memberContent.containsKey('avatar_url');

  Future<void> editDisplayname() async {
    final l10n = L10n.of(context);
    final input = await showTextInputDialog(
      context: context,
      title: l10n.editDisplayname,
      initialText: displayName,
      labelText: l10n.editDisplayname,
    );
    if (input == null) return;
    await _applyPatch({'displayname': input.trim().isEmpty ? null : input});
  }

  Future<void> changeAvatar() async {
    final action = await showModalActionPopup<_AvatarChoice>(
      context: context,
      title: L10n.of(context).changeYourAvatar,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          value: _AvatarChoice.file,
          label: L10n.of(context).openGallery,
          isDefaultAction: true,
          icon: const Icon(Icons.photo_outlined),
        ),
        AdaptiveModalAction(
          value: _AvatarChoice.history,
          label: L10n.of(context).avatarHistory,
          icon: const Icon(Icons.history_outlined),
        ),
      ],
    );
    if (!mounted) return;
    if (action == _AvatarChoice.history) {
      final mxc = await showAvatarHistoryPicker(context);
      if (mxc == null || !mounted) return;
      await _applyPatch({'avatar_url': mxc});
      await AvatarHistory.record(mxc);
      return;
    }
    if (action != _AvatarChoice.file) return;
    final result = await selectFiles(context, type: FileType.image);
    final pickedFile = result.firstOrNull;
    if (pickedFile == null || !mounted) return;
    final rawBytes = await pickedFile.readAsBytes();
    final mxc = await showFutureLoadingDialog(
      context: context,
      future: () async {
        final file = MatrixFile(
          bytes: Uint8List.fromList(ExifCleaner.removeExifData(rawBytes)),
          name: pickedFile.name,
        );
        return room.client.uploadContent(
          file.bytes,
          filename: file.name,
          contentType: file.mimeType,
        );
      },
    );
    if (mxc.error != null || !mounted) return;
    await _applyPatch({'avatar_url': mxc.result!.toString()});
    await AvatarHistory.record(mxc.result!.toString());
  }

  Future<void> removeAvatar() => _applyPatch({'avatar_url': null});

  /// Drops both overrides, so this chat shows the account profile again.
  Future<void> resetToAccountProfile() =>
      _applyPatch({'displayname': null, 'avatar_url': null});

  /// Merges [patch] into the current member content and sends it; `null`
  /// values remove the key, which makes the field fall back to the account
  /// profile.
  Future<void> _applyPatch(Map<String, String?> patch) async {
    final content = Map<String, dynamic>.of(_memberContent);
    patch.forEach((key, value) {
      value == null ? content.remove(key) : content[key] = value;
    });
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => _sendMemberState(content),
    );
    if (result.error != null) return;
    if (mounted) {
      setState(() {
        _overrideContent = content;
      });
    }
  }

  Future<void> _sendMemberState(Map<String, dynamic> content) async {
    final client = room.client;
    final userId = client.userID!;
    await client.setRoomStateWithKey(
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

  @override
  Widget build(BuildContext context) => ChatRoomProfileView(this);
}
