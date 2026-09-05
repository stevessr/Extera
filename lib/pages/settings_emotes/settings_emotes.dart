import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:archive/archive.dart'
    if (dart.library.io) 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' hide Client;
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/client_manager.dart';
import 'package:extera_next/utils/file_selector.dart';
import 'package:extera_next/utils/image_pack_migration.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:extera_next/widgets/future_loading_dialog.dart';

import '../../utils/emote_shortcode.dart';
import '../../widgets/matrix.dart';
import 'import_archive_dialog.dart';
import 'settings_emotes_view.dart';

class EmotesSettings extends StatefulWidget {
  final String? roomId;
  const EmotesSettings({required this.roomId, super.key});

  @override
  EmotesSettingsController createState() => EmotesSettingsController();
}

class EmotesSettingsController extends State<EmotesSettings> {
  late final Room? room;

  String? stateKey;

  BasicEvent? getRoomPackEvent(String key) {
    final room = this.room;
    if (room == null) return null;
    return room.getState(EventTypes.RoomImagePack, key) ??
        room.getState(legacyRoomImagePackEventType, key);
  }

  List<String>? get packKeys {
    final room = this.room;
    if (room == null) return null;
    final keys = <String>{
      ...?room.states[legacyRoomImagePackEventType]?.keys,
      ...?room.states[EventTypes.RoomImagePack]?.keys,
    }.toList()..sort();
    return keys;
  }

  List<String> get legacyPackKeysToMigrate {
    final room = this.room;
    if (room == null) return const [];
    final legacy = room.states[legacyRoomImagePackEventType];
    if (legacy == null) return const [];
    return legacy.keys
        .where((key) => room.getState(EventTypes.RoomImagePack, key) == null)
        .toList()
      ..sort();
  }

  bool get hasLegacyImagePacksToMigrate => legacyPackKeysToMigrate.isNotEmpty;

  bool get canMigrateLegacyImagePacks {
    final room = this.room;
    return room != null && room.canChangeStateEvent(EventTypes.RoomImagePack);
  }

  @override
  void initState() {
    super.initState();
    room = widget.roomId != null
        ? Matrix.of(context).client.getRoomById(widget.roomId!)
        : null;
    setStateKey(packKeys?.firstOrNull, reset: false);
  }

  void setStateKey(String? key, {reset = true}) {
    stateKey = key;

    final event = key == null ? null : getRoomPackEvent(key);
    final eventPack = event?.content.tryGetMap<String, Object?>('pack');
    packDisplayNameController.text =
        eventPack?.tryGet<String>('display_name') ?? '';
    packAttributionController.text =
        eventPack?.tryGet<String>('attribution') ?? '';
    if (reset) resetAction();
  }

  bool showSave = false;

  ImagePackContent _getPack() {
    final client = Matrix.of(context).client;
    final event =
        (room != null
            ? getRoomPackEvent(stateKey ?? '')
            : client.accountData[legacyUserImagePackEventType]) ??
        BasicEvent(type: 'm.dummy', content: {});
    // make sure we work on a *copy* of the event
    return BasicEvent.fromJson(event.toJson()).parsedImagePackContent;
  }

  Map<String, dynamic> _stablePackJson(ImagePackContent imagePack) =>
      normalizeStableImagePackContent(
        Map<String, dynamic>.from(imagePack.toJson()),
      );

  ImagePackContent? _pack;

  ImagePackContent? get pack {
    if (_pack != null) {
      return _pack;
    }
    _pack = _getPack();
    return _pack;
  }

  Future<void> save(BuildContext context) async {
    if (readonly) {
      return;
    }
    final client = Matrix.of(context).client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => room != null
          ? client.setRoomStateWithKey(
              room!.id,
              EventTypes.RoomImagePack,
              stateKey ?? '',
              _stablePackJson(pack!),
            )
          : client.setAccountData(
              client.userID!,
              legacyUserImagePackEventType,
              pack!.toJson(),
            ),
    );
    if (!result.isError) {
      setState(() {
        showSave = false;
      });
    }
  }

  Future<void> _setGlobalReference(
    Client client,
    String eventType,
    bool active,
  ) async {
    final room = this.room;
    if (room == null) return;
    if (!active && client.accountData[eventType] == null) return;

    final content = Map<String, dynamic>.from(
      client.accountData[eventType]?.content ?? const <String, dynamic>{},
    );
    final rawRooms = content['rooms'];
    final rooms = rawRooms is Map
        ? Map<String, dynamic>.from(rawRooms)
        : <String, dynamic>{};
    final rawRoomReferences = rooms[room.id];
    final roomReferences = rawRoomReferences is Map
        ? Map<String, dynamic>.from(rawRoomReferences)
        : <String, dynamic>{};
    final key = stateKey ?? '';

    if (active) {
      roomReferences[key] = <String, dynamic>{};
      rooms[room.id] = roomReferences;
    } else {
      roomReferences.remove(key);
      if (roomReferences.isEmpty) {
        rooms.remove(room.id);
      } else {
        rooms[room.id] = roomReferences;
      }
    }
    content['rooms'] = rooms;

    await client.setAccountData(client.userID!, eventType, content);
  }

  Future<void> setIsGloballyActive(bool active) async {
    if (room == null) {
      return;
    }
    final client = Matrix.of(context).client;
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        if (active) {
          await _setGlobalReference(client, EventTypes.ImagePackRooms, true);
        } else {
          // Remove both forms: otherwise the SDK's legacy compatibility path
          // would keep surfacing a pack which the user just disabled.
          await _setGlobalReference(client, EventTypes.ImagePackRooms, false);
          await _setGlobalReference(
            client,
            legacyImagePackRoomsEventType,
            false,
          );
        }
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  final TextEditingController packDisplayNameController =
      TextEditingController();

  final TextEditingController packAttributionController =
      TextEditingController();

  void removeImageAction(String oldImageCode) => setState(() {
    pack!.images.remove(oldImageCode);
    showSave = true;
  });

  void togglePackUsage(ImagePackUsage usage) {
    setState(() {
      final usages = pack!.pack.usage ??= List.from(ImagePackUsage.values);
      if (!usages.remove(usage)) usages.add(usage);
      showSave = true;
    });
  }

  bool packUses(ImagePackUsage usage) =>
      pack!.pack.usage?.contains(usage) ?? true;

  void submitDisplaynameAction() {
    if (readonly) return;
    packDisplayNameController.text = packDisplayNameController.text.trim();
    final input = packDisplayNameController.text;

    setState(() {
      pack!.pack.displayName = input;
      showSave = true;
    });
  }

  void submitAttributionAction() {
    if (readonly) return;
    packAttributionController.text = packAttributionController.text.trim();
    final input = packAttributionController.text;

    setState(() {
      pack!.pack.attribution = input;
      showSave = true;
    });
  }

  void submitImageAction(
    String oldImageCode,
    ImagePackImageContent image,
    TextEditingController controller,
  ) {
    controller.text = controller.text.trim().replaceAll(' ', '-');
    final imageCode = controller.text;
    if (imageCode == oldImageCode) return;
    if (pack!.images.keys.any((k) => k == imageCode && k != oldImageCode)) {
      controller.text = oldImageCode;
      showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteExists,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    if (!emoteShortcodePattern.hasMatch(imageCode)) {
      controller.text = oldImageCode;
      showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).emoteInvalid,
        okLabel: L10n.of(context).ok,
      );
      return;
    }
    setState(() {
      pack!.images[imageCode] = image;
      pack!.images.remove(oldImageCode);
      showSave = true;
    });
  }

  bool _hasGlobalReference(Client client, String eventType) {
    final room = this.room;
    if (room == null) return false;
    return client.accountData[eventType]?.content
            .tryGetMap<String, Object?>('rooms')
            ?.tryGetMap<String, Object?>(room.id)
            ?.containsKey(stateKey ?? '') ==
        true;
  }

  bool isGloballyActive(Client? client) =>
      room != null &&
      client != null &&
      (_hasGlobalReference(client, EventTypes.ImagePackRooms) ||
          _hasGlobalReference(client, legacyImagePackRoomsEventType));

  bool get readonly => room == null
      ? false
      : room?.canChangeStateEvent(EventTypes.RoomImagePack) == false;

  void resetAction() {
    setState(() {
      _pack = _getPack();
      showSave = false;
    });
  }

  Future<void> migrateLegacyImagePacks() async {
    final room = this.room;
    if (room == null || !canMigrateLegacyImagePacks) return;
    final keysToMigrate = legacyPackKeysToMigrate;
    if (keysToMigrate.isEmpty) return;

    final client = room.client;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () async {
        for (final key in keysToMigrate) {
          // Never overwrite a stable event if one appeared while the dialog
          // was opening or while another device was migrating the room.
          if (room.getState(EventTypes.RoomImagePack, key) != null) continue;
          final legacyEvent = room.getState(legacyRoomImagePackEventType, key);
          if (legacyEvent == null) continue;
          await client.setRoomStateWithKey(
            room.id,
            EventTypes.RoomImagePack,
            key,
            normalizeStableImagePackContent(
              Map<String, dynamic>.from(legacyEvent.content),
            ),
          );
        }

        // Preserve the user's global activation choices in the stable account
        // data event. Legacy account data is intentionally left in place for
        // older clients; disabling a pack removes both forms above.
        final legacyGlobal = client.accountData[legacyImagePackRoomsEventType];
        final legacyRoomReferences = legacyGlobal?.content
            .tryGetMap<String, Object?>('rooms')
            ?.tryGetMap<String, Object?>(room.id);
        if (legacyRoomReferences != null && legacyRoomReferences.isNotEmpty) {
          final stableContent = Map<String, dynamic>.from(
            client.accountData[EventTypes.ImagePackRooms]?.content ??
                const <String, dynamic>{},
          );
          final rawStableRooms = stableContent['rooms'];
          final stableRooms = rawStableRooms is Map
              ? Map<String, dynamic>.from(rawStableRooms)
              : <String, dynamic>{};
          final rawStableReferences = stableRooms[room.id];
          final stableReferences = rawStableReferences is Map
              ? Map<String, dynamic>.from(rawStableReferences)
              : <String, dynamic>{};
          final availableStableKeys = <String>{
            ...?room.states[EventTypes.RoomImagePack]?.keys,
            ...keysToMigrate,
          };
          var changed = false;
          for (final key in legacyRoomReferences.keys) {
            if (!availableStableKeys.contains(key)) continue;
            if (!stableReferences.containsKey(key)) {
              stableReferences[key] = <String, dynamic>{};
              changed = true;
            }
          }
          if (changed) {
            stableRooms[room.id] = stableReferences;
            stableContent['rooms'] = stableRooms;
            await client.setAccountData(
              client.userID!,
              EventTypes.ImagePackRooms,
              stableContent,
            );
          }
        }

        await client.oneShotSync();
      },
    );

    if (!mounted || result.isError) return;
    _pack = null;
    setStateKey(stateKey);
  }

  void createImagePack() async {
    final room = this.room;
    if (room == null) throw Exception('Cannot create image pack without room');

    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context).newStickerPack,
      hintText: L10n.of(context).name,
      okLabel: L10n.of(context).create,
    );
    final name = input?.trim();
    if (name == null || name.isEmpty) return;
    if (!mounted) return;

    final keyName = name.toLowerCase().replaceAll(' ', '_');

    if (packKeys?.contains(keyName) ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).stickerPackNameAlreadyExists)),
      );
      return;
    }

    await showFutureLoadingDialog(
      context: context,
      future: () => room.client.setRoomStateWithKey(
        room.id,
        EventTypes.RoomImagePack,
        keyName,
        {
          'images': {},
          'pack': {'display_name': name},
        },
      ),
    );
    if (!mounted) return;
    setState(() {});
    await room.client.oneShotSync();
    if (!mounted) return;
    setState(() {});
  }

  void saveAction() async {
    await save(context);
    if (!mounted) return;
    setState(() {
      showSave = false;
    });
  }

  void createStickers() async {
    final pickedFiles = await selectFiles(
      context,
      type: FileType.image,
      allowMultiple: true,
    );
    if (pickedFiles.isEmpty) return;
    if (!mounted) return;

    await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (setProgress) async {
        for (final (i, pickedFile) in pickedFiles.indexed) {
          setProgress(i / pickedFiles.length);
          var file = MatrixImageFile(
            bytes: await pickedFile.readAsBytes(),
            name: pickedFile.name,
          );
          file =
              await file.generateThumbnail(
                nativeImplementations: ClientManager.nativeImplementations,
              ) ??
              file;
          final uri = await Matrix.of(context).client.uploadContent(
            file.bytes,
            filename: file.name,
            contentType: file.mimeType,
          );

          setState(() {
            final imageCode = pickedFile.name.split('.').first;
            pack!.images[imageCode] = ImagePackImageContent.fromJson(
              <String, dynamic>{'url': uri.toString(), 'info': file.info},
            );
          });
        }
      },
    );

    setState(() {
      showSave = true;
    });
  }

  @override
  void dispose() {
    packAttributionController.dispose();
    packDisplayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EmotesSettingsView(this);
  }

  Future<void> importEmojiZip() async {
    final result = await selectFiles(context, type: FileType.any);

    if (result.isEmpty) return;

    final buffer = InputMemoryStream(await result.single.readAsBytes());

    final archive = ZipDecoder().decodeStream(buffer);

    await showDialog(
      context: context,
      // breaks [Matrix.of] calls otherwise
      useRootNavigator: false,
      builder: (context) =>
          ImportEmoteArchiveDialog(controller: this, archive: archive),
    );
    setState(() {});
  }

  Future<void> exportAsZip() async {
    final client = Matrix.of(context).client;

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final pack = _getPack();
        final archive = Archive();
        for (final entry in pack.images.entries) {
          final emote = entry.value;
          final name = entry.key;
          final url = await emote.url.getDownloadUri(client);
          final response = await get(
            url,
            headers: {'authorization': 'Bearer ${client.accessToken}'},
          );

          archive.addFile(
            ArchiveFile(name, response.bodyBytes.length, response.bodyBytes),
          );
        }
        final fileName =
            '${pack.pack.displayName ?? client.userID?.localpart ?? 'emotes'}.zip';
        final output = ZipEncoder().encode(archive);

        MatrixFile(
          name: fileName,
          bytes: Uint8List.fromList(output),
        ).save(context);
      },
    );
  }
}
