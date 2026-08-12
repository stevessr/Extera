import 'package:collection/collection.dart';
import 'package:emojis/emoji.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/widgets/emoji_picker.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/mxc_image.dart';
import 'package:flutter/material.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:matrix/matrix.dart';
import 'package:slugify/slugify.dart';
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
      final finalSlug = slugify(slug ?? 'pack');
      for (final entry in imagePack.images.entries) {
        final image = entry.value;
        if (allMxcs.contains(image.url)) {
          continue;
        }
        final imageUsage = image.usage ?? imagePack.pack.usage;
        if (usage != null &&
            imageUsage != null &&
            !imageUsage.contains(usage)) {
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

    // first we add the user image pack
    addImagePack(client.accountData['im.ponies.user_emotes'], slug: 'user');
    // next we add all the external image packs
    final packRooms = client.accountData['im.ponies.emote_rooms'];
    final rooms = packRooms?.content.tryGetMap<String, Object?>('rooms');
    if (packRooms != null && rooms != null) {
      for (final roomEntry in rooms.entries) {
        final roomId = roomEntry.key;
        final room = client.getRoomById(roomId);
        final roomEntryValue = roomEntry.value;
        if (room != null && roomEntryValue is Map<String, Object?>) {
          for (final stateKeyEntry in roomEntryValue.entries) {
            final stateKey = stateKeyEntry.key;
            final fallbackSlug =
                '${room.getLocalizedDisplayname()}-${stateKey.isNotEmpty ? '$stateKey-' : ''}${room.id}';
            addImagePack(
              room.getState('im.ponies.room_emotes', stateKey),
              room: room,
              slug: fallbackSlug,
            );
          }
        }
      }
    }
    return packs;
  }

  void changeDefaultReaction() async {
    final client = Matrix.of(context).client;

    final imagePacks = getImagePacks(client, ImagePackUsage.emoticon);

    final recentEmojisAll = client.recentEmojis.entries
        .sortedByCompare((element) => element.value, (a, b) => b - a)
        .map((entry) => entry.key)
        .toList();
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
            recentEmojis: recentEmojisAll.map((recent) {
              // MXC custom emoji
              if (recent.startsWith('mxc://')) {
                for (final entry in imagePacks.entries) {
                  for (final imgEntry in entry.value.images.entries) {
                    final url = imgEntry.value.url.toString();
                    if (url == recent) {
                      return PickerEmoji.custom(
                        name: imgEntry.key,
                        customData: url,
                        categoryId: entry.key,
                      );
                    }
                  }
                }

                // fallback: keep the MXC url as custom data
                return PickerEmoji.custom(
                  name: recent,
                  customData: recent,
                  categoryId: null,
                );
              }

              // Try to find a matching standard Emoji by char, name or shortName
              Emoji? found;
              final all = Emoji.all();
              try {
                found = all.firstWhere(
                  (e) =>
                      e.char == recent ||
                      e.name == recent ||
                      e.shortName == recent,
                );
              } catch (_) {
                found = null;
              }

              if (found != null) {
                return PickerEmoji.standard(found);
              }

              // fallback: treat as custom string
              return PickerEmoji.custom(
                name: recent,
                customData: recent,
                categoryId: null,
              );
            }).toList(),
            customCategories: imagePacks.entries
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
                .toList(),
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
