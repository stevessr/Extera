import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:emojis/emoji.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/emoji_data.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/sticker_picker_dialog.dart';
import 'package:extera_next/pages/chat/trust_user_key_dialog.dart';
import 'package:extera_next/utils/animated_emoji.dart';
import 'package:extera_next/utils/dynamic_emoji.dart';
import 'package:extera_next/widgets/animated_emoji_image.dart';
import 'package:extera_next/widgets/animated_emoji_picker.dart';
import 'package:extera_next/widgets/emoji_picker.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/mxc_image.dart';
import 'chat.dart';

class ChatEmojiPicker extends StatelessWidget {
  final ChatController controller;
  const ChatEmojiPicker(this.controller, {super.key});

  Future<bool> _confirmAnimatedEmojiSend(
    BuildContext context,
    Emoji emoji,
    String codepoint,
    DynamicEmojiFormat format,
  ) async {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return await showDialog<bool>(
          context: context,
          useRootNavigator: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(isZh ? '发送动态表情？' : 'Send animated emoji?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 112,
                  height: 112,
                  child: Center(
                    child: AnimatedEmojiImage(
                      emoji: emoji.char,
                      codepoint: codepoint,
                      fontSize: 80,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isZh
                      ? '将以 ${format.label} 图片发送'
                      : 'This will be sent as a ${format.label} image.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(isZh ? '取消' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(isZh ? '发送' : 'Send'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _sendAnimatedEmoji(BuildContext context, Emoji emoji) async {
    final codepoint = animatedEmojiCodepoint(emoji.char);
    if (codepoint == null) return;

    final format = await DynamicEmojiPreferences.load();
    if (!context.mounted) return;

    // Dynamic emoji are sent immediately as media rather than inserted into
    // the composer, so always require an explicit second tap before upload.
    final confirmed = await _confirmAnimatedEmojiSend(
      context,
      emoji,
      codepoint,
      format,
    );
    if (!confirmed || !context.mounted) return;

    final proceed = await showTrustUserInRoomDialog(context, controller.room);
    if (!proceed) return;

    try {
      await sendDynamicEmoji(
        room: controller.room,
        source: animatedEmojiGifUrl(codepoint).toString(),
        name: emoji.char,
        format: format,
        replyEvent: controller.replyEvent,
        thread: controller.thread,
      );
      controller.cancelReplyEventAction();
      controller.hideEmojiPicker();
    } catch (error) {
      if (!context.mounted) return;
      final isZh = Localizations.localeOf(context).languageCode == 'zh';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isZh ? '无法发送动态表情：$error' : 'Unable to send animated emoji: $error',
          ),
          showCloseIcon: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final imagePacks = controller.room.getImagePacks(ImagePackUsage.emoticon);
    final recentEmojis = client.recentEmojis.entries
        .sortedByCompare((element) => element.value, (a, b) => b - a)
        .map((entry) => entry.key)
        .toList();
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    return ClipRect(
      child: AnimatedSize(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: controller.showEmojiPicker
            ? SizedBox(
                height: MediaQuery.sizeOf(context).height / 2,
                child: DefaultTabController(
                  length: 3,
                  initialIndex: controller.initiallyShowStickerPicker ? 1 : 0,
                  child: Column(
                    children: [
                      TabBar(
                        tabs: [
                          Tab(text: L10n.of(context).emojis),
                          Tab(text: L10n.of(context).stickers),
                          Tab(text: isZh ? '动态表情' : 'Animated'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            MatrixEmojiPicker(
                              onEmojiSelected: controller.onEmojiSelected,
                              onBackspacePressed:
                                  controller.emojiPickerBackspace,
                              recentEmojis: recentEmojis.map((recent) {
                                // MXC custom emoji
                                if (recent.startsWith('mxc://')) {
                                  for (final entry in imagePacks.entries) {
                                    for (final imgEntry
                                        in entry.value.images.entries) {
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
                                final all = EmojiData.all();
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
                                        uri:
                                            entry.value.images.values.first.url,
                                        width: 32,
                                        height: 32,
                                        cacheKey: entry
                                            .value
                                            .images
                                            .values
                                            .first
                                            .url
                                            .toString(),
                                      ),
                                      emojis: entry.value.images.map((
                                        name,
                                        content,
                                      ) {
                                        return MapEntry(
                                          name,
                                          content.url.toString(),
                                        );
                                      }),
                                    ),
                                  )
                                  .toList(),
                              customEmojiBuilder: (context, name, size) {
                                return MxcImage(
                                  uri: Uri.parse(name),
                                  width: 32,
                                  height: 32,
                                  cacheKey: name,
                                  animated: true,
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
                            AnimatedEmojiPicker(
                              onEmojiSelected: (emoji) =>
                                  _sendAnimatedEmoji(context, emoji),
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
