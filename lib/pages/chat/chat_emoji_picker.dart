import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/sticker_picker_dialog.dart';
import 'package:extera_next/pages/chat/trust_user_key_dialog.dart';
import 'package:extera_next/utils/emoji_picker_recent.dart';
import 'package:extera_next/widgets/emoji_picker.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/mxc_image.dart';

import 'chat.dart';

class ChatEmojiPicker extends StatelessWidget {
  final ChatController controller;
  const ChatEmojiPicker(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final showEmojiPicker = controller.showEmojiPicker;
    final client = Matrix.of(context).client;
    final imagePacks = controller.room.getImagePacks(ImagePackUsage.emoticon);
    final recentEmojis = showEmojiPicker
        ? client.recentEmojis.entries
              .sortedByCompare((element) => element.value, (a, b) => b - a)
              .map((entry) => entry.key)
              .toList()
        : const <String>[];

    // Image packs are remote state and may legitimately be incomplete while a
    // room is syncing or after migration from an older MSC representation.
    // Never let one malformed/empty pack take down the entire emoji panel.
    final customCategories = <CustomCategory>[];
    if (showEmojiPicker) {
      for (final entry in imagePacks.entries) {
        final images = entry.value.images;
        if (images.isEmpty) continue;

        final packName = entry.value.pack.displayName?.trim();
        final firstImage = images.values.first;
        customCategories.add(
          CustomCategory(
            id: entry.key,
            name: packName == null || packName.isEmpty ? entry.key : packName,
            icon: MxcImage(
              uri: firstImage.url,
              width: 32,
              height: 32,
              cacheKey: firstImage.url.toString(),
              retryDuration: const Duration(milliseconds: 500),
            ),
            emojis: images.map((name, content) {
              return MapEntry(name, content.url.toString());
            }),
          ),
        );
      }
    }

    final recentPickerEmojis = showEmojiPicker
        ? buildRecentPickerEmojis(
            recent: recentEmojis,
            customCategories: customCategories,
          )
        : const <PickerEmoji>[];

    return ClipRect(
      child: AnimatedSize(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: showEmojiPicker
            ? SizedBox(
                height: MediaQuery.sizeOf(context).height / 2,
                child: DefaultTabController(
                  length: 2,
                  initialIndex: controller.initiallyShowStickerPicker ? 1 : 0,
                  child: Column(
                    children: [
                      TabBar(
                        tabs: [
                          Tab(text: L10n.of(context).emojis),
                          Tab(text: L10n.of(context).stickers),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            MatrixEmojiPicker(
                              onEmojiSelected: controller.onEmojiSelected,
                              onBackspacePressed:
                                  controller.emojiPickerBackspace,
                              recentEmojis: recentPickerEmojis,
                              customCategories: customCategories,
                              customEmojiBuilder: (context, name, size) {
                                return MxcImage(
                                  key: ValueKey(name),
                                  uri: Uri.parse(name),
                                  width: size,
                                  height: size,
                                  cacheKey: name,
                                  animated: true,
                                  retryDuration: const Duration(
                                    milliseconds: 500,
                                  ),
                                );
                              },
                            ),
                            StickerPickerDialog(
                              room: controller.room,
                              onSelected: (sticker) async {
                                final proceed = await showTrustUserInRoomDialog(
                                  context,
                                  controller.room,
                                );
                                if (!proceed) return;
                                controller.room.sendEvent(
                                  {
                                    'body': sticker.body,
                                    'info': sticker.info ?? {},
                                    'url': sticker.url.toString(),
                                  },
                                  type: EventTypes.Sticker,
                                  inReplyTo: controller.replyEvent,
                                  threadRootEventId:
                                      controller.threadRootEventId,
                                );
                                controller.cancelReplyEventAction();
                                controller.hideEmojiPicker();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class NoRecent extends StatelessWidget {
  const NoRecent({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          L10n.of(context).emoteKeyboardNoRecents,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
