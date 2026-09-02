import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
import 'package:slugify/slugify.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/emoji_picker_recent.dart';
import 'package:extera_next/utils/image_pack_migration.dart';
import 'package:extera_next/widgets/emoji_picker.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/mxc_image.dart';

import 'settings_chat_view.dart';

class SettingsChat extends StatefulWidget {
  const SettingsChat({super.key});

  @override
  SettingsChatController createState() => SettingsChatController();
}

class SettingsChatController extends State<SettingsChat> {
  void changeMessageFontSize(double d) {
    AppSettings.messageFontSize.setItem(d);
    setState(() {});
  }

  String get doubleTapAction {
    return AppSettings.doubleTapAction.value;
  }

  String get doubleTapReact {
    return AppSettings.doubleTapReaction.value;
  }

  void setDoubleTapAction(String value) {
    setState(() {
      AppSettings.doubleTapAction.setItem(value);
    });
  }

  Map<String, ImagePackContent> getImagePacks(
    Client client, [
    ImagePackUsage? usage,
  ]) {
    final allMxcs = <Uri>{}; // used for easy deduplication
    final packs = <String, ImagePackContent>{};

    void addImagePack(BasicEvent? event, {Room? room, String? slug}) {
      if (event == null) return;
      final imagePack = event.parsedImagePackContent;
      final rawSlug = slug ?? 'pack';
      var finalSlug = slugify(rawSlug);
      if (finalSlug.isEmpty) finalSlug = rawSlug;
      if (packs.containsKey(finalSlug)) {
        var suffix = 2;
        while (packs.containsKey('$finalSlug-$suffix')) {
          suffix++;
        }
        finalSlug = '$finalSlug-$suffix';
      }
      for (final entry in imagePack.images.entries) {
        final image = entry.value;
        if (allMxcs.contains(image.url)) {
          continue;
        }
        final imageUsage = image.usage ?? imagePack.pack.usage;
        if (usage != null &&
            imageUsage?.isNotEmpty == true &&
            !imageUsage!.contains(usage)) {
          continue;
        }
        packs
                .putIfAbsent(
                  finalSlug,
                  () => ImagePackContent.fromJson({})
                    ..pack.displayName =
                        imagePack.pack.displayName ??
                        room?.getLocalizedDisplayname() ??
                        finalSlug
                    ..pack.avatarUrl = imagePack.pack.avatarUrl ?? room?.avatar
                    ..pack.attribution = imagePack.pack.attribution,
                )
                .images[entry.key] =
            image;
        allMxcs.add(image.url);
      }
    }

    void addReferencedPacks(BasicEvent? references, {required bool stable}) {
      final rooms = references?.content.tryGetMap<String, Object?>('rooms');
      if (rooms == null) return;

      for (final roomEntry in rooms.entries) {
        final room = client.getRoomById(roomEntry.key);
        final referencedStateKeys = roomEntry.value;
        if (room == null || referencedStateKeys is! Map) continue;

        for (final stateKey in referencedStateKeys.keys.whereType<String>()) {
          final stableEvent = room.getState(EventTypes.RoomImagePack, stateKey);
          final legacyEvent = room.getState(
            legacyRoomImagePackEventType,
            stateKey,
          );
          final event = stable
              ? stableEvent ?? legacyEvent
              : legacyEvent ?? stableEvent;
          final fallbackSlug =
              '${room.getLocalizedDisplayname()}-${stateKey.isNotEmpty ? '$stateKey-' : ''}${room.id}';
          addImagePack(event, room: room, slug: fallbackSlug);
        }
      }
    }

    // Match stable MSC2545 priority: stable globally-enabled packs come first.
    addReferencedPacks(
      client.accountData[EventTypes.ImagePackRooms],
      stable: true,
    );

    // The historical direct user pack has no stable MSC2545 equivalent.
    addImagePack(
      client.accountData[legacyUserImagePackEventType],
      slug: 'user',
    );
    addReferencedPacks(
      client.accountData[legacyImagePackRoomsEventType],
      stable: false,
    );
    return packs;
  }

  void changeDefaultReaction() async {
    final client = Matrix.of(context).client;
    final imagePacks = getImagePacks(client, ImagePackUsage.emoticon);
    final recentEmojisAll = client.recentEmojis.entries
        .sortedByCompare((element) => element.value, (a, b) => b - a)
        .map((entry) => entry.key)
        .toList();
    final customCategories = imagePacks.entries
        .map(
          (entry) => CustomCategory(
            id: entry.key,
            name: entry.value.pack.displayName!,
            icon: MxcImage(
              uri: entry.value.images.values.first.url,
              width: 32,
              height: 32,
            ),
            emojis: entry.value.images.map((name, content) {
              return MapEntry(name, content.url.toString());
            }),
          ),
        )
        .toList(growable: false);
    final recentPickerEmojis = buildRecentPickerEmojis(
      recent: recentEmojisAll,
      customCategories: customCategories,
    );

    final emoji = await showAdaptiveBottomSheet<String>(
      context: context,
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(L10n.of(context).customReaction),
          leading: CloseButton(
            onPressed: () => Navigator.of(context).pop(null),
          ),
        ),
        body: SizedBox(
          height: double.infinity,
          child: MatrixEmojiPicker(
            onEmojiSelected: (_, emoji) => Navigator.of(
              context,
            ).pop(emoji.customData ?? emoji.standardEmoji!.char),
            onBackspacePressed: () {},
            recentEmojis: recentPickerEmojis,
            customCategories: customCategories,
            customEmojiBuilder: (context, name, size) {
              return MxcImage(uri: Uri.parse(name), width: 32, height: 32);
            },
          ),
        ),
      ),
    );
    if (emoji == null) {
      return;
    }
    setState(() {
      AppSettings.doubleTapReaction.setItem(emoji);
    });
  }

  @override
  Widget build(BuildContext context) => SettingsChatView(this);
}
