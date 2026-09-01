import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/widgets/list_divider.dart';
import 'package:extera_next/widgets/mxc_image.dart';
import 'package:extera_next/widgets/mxc_image_viewer.dart';

import '../../widgets/matrix.dart';
import 'settings_emotes.dart';

enum PopupMenuEmojiActions { import, export, migrateToStable }

class EmotesSettingsView extends StatelessWidget {
  final EmotesSettingsController controller;

  const EmotesSettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    if (controller.widget.roomId != null && controller.room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
        ),
      );
    }
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    final imageKeys = controller.pack!.images.keys.toList();
    final packKeys = controller.packKeys;
    if (packKeys != null && packKeys.isEmpty) {
      packKeys.add('');
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !controller.showSave,
        title: controller.showSave
            ? TextButton(
                onPressed: controller.resetAction,
                child: Text(L10n.of(context).cancel),
              )
            : Text(L10n.of(context).customEmojisAndStickers),
        actions: [
          if (controller.showSave)
            ElevatedButton(
              onPressed: () => controller.save(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              child: Text(L10n.of(context).saveChanges),
            )
          else
            PopupMenuButton<PopupMenuEmojiActions>(
              useRootNavigator: false,
              onSelected: (value) {
                switch (value) {
                  case PopupMenuEmojiActions.export:
                    controller.exportAsZip();
                    break;
                  case PopupMenuEmojiActions.import:
                    controller.importEmojiZip();
                    break;
                  case PopupMenuEmojiActions.migrateToStable:
                    controller.migrateLegacyImagePacks();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (!controller.readonly)
                  PopupMenuItem(
                    value: PopupMenuEmojiActions.import,
                    child: Text(L10n.of(context).importFromZipFile),
                  ),
                if (imageKeys.isNotEmpty)
                  PopupMenuItem(
                    value: PopupMenuEmojiActions.export,
                    child: Text(L10n.of(context).exportEmotePack),
                  ),
                if (controller.hasLegacyImagePacksToMigrate)
                  PopupMenuItem(
                    value: PopupMenuEmojiActions.migrateToStable,
                    enabled: controller.canMigrateLegacyImagePacks,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upgrade_outlined),
                        SizedBox(width: 12),
                        Text('Migrate to stable Matrix format'),
                      ],
                    ),
                  ),
              ],
            ),
        ],
        bottom: packKeys == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: packKeys.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          if (controller.readonly) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                            ),
                            child: FilterChip(
                              label: const Icon(Icons.add_outlined, size: 20),
                              onSelected: controller.showSave
                                  ? null
                                  : (_) => controller.createImagePack(),
                            ),
                          );
                        }
                        i--;
                        final key = packKeys[i];
                        final event = controller.getRoomPackEvent(key);

                        final eventPack = event?.content
                            .tryGetMap<String, Object?>('pack');
                        final packName =
                            eventPack?.tryGet<String>('display_name') ??
                            eventPack?.tryGet<String>('name') ??
                            (key.isNotEmpty ? key : 'Default');

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: FilterChip(
                            label: Text(packName),
                            selected:
                                controller.stateKey == key ||
                                (controller.stateKey == null && key.isEmpty),
                            onSelected: controller.showSave
                                ? null
                                : (_) => controller.setStateKey(key),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const .symmetric(horizontal: 8),
                      child: Material(
                        borderRadius: BorderRadius.circular(
                          AppConfig.borderRadius,
                        ),
                        clipBehavior: .hardEdge,
                        color: theme.colorScheme.surfaceContainerHigh,
                        child: Column(
                          children: [
                            if (controller.room != null &&
                                imageKeys.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SwitchListTile.adaptive(
                                title: Text(
                                  L10n.of(context).enableEmotesGlobally,
                                ),
                                value: controller.isGloballyActive(client),
                                onChanged: controller.setIsGloballyActive,
                              ),
                              const ListDivider(),
                              const SizedBox(height: 8),
                            ],
                            if (controller.room != null) ...[
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                ),
                                child: TextField(
                                  maxLength: 256,
                                  controller:
                                      controller.packDisplayNameController,
                                  readOnly: controller.readonly,
                                  onSubmitted: (_) =>
                                      controller.submitDisplaynameAction(),
                                  decoration: InputDecoration(
                                    counter: const SizedBox.shrink(),
                                    hintText: controller.stateKey,
                                    labelText: L10n.of(context).stickerPackName,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                ),
                                child: TextField(
                                  maxLength: 256,
                                  controller:
                                      controller.packAttributionController,
                                  readOnly: controller.readonly,
                                  onSubmitted: (_) =>
                                      controller.submitAttributionAction(),
                                  decoration: InputDecoration(
                                    counter: const SizedBox.shrink(),
                                    labelText: L10n.of(context).attribution,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (!controller.readonly &&
                                imageKeys.isNotEmpty) ...[
                              SwitchListTile.adaptive(
                                title: Text(L10n.of(context).useAsEmoji),
                                value: controller.packUses(
                                  ImagePackUsage.emoticon,
                                ),
                                onChanged:
                                    controller.packUses(
                                          ImagePackUsage.emoticon,
                                        ) &&
                                        !controller.packUses(
                                          ImagePackUsage.sticker,
                                        )
                                    ? null
                                    : (_) => controller.togglePackUsage(
                                        ImagePackUsage.emoticon,
                                      ),
                              ),
                              const ListDivider(),
                              SwitchListTile.adaptive(
                                title: Text(L10n.of(context).useAsSticker),
                                value: controller.packUses(
                                  ImagePackUsage.sticker,
                                ),
                                onChanged:
                                    controller.packUses(
                                          ImagePackUsage.sticker,
                                        ) &&
                                        !controller.packUses(
                                          ImagePackUsage.emoticon,
                                        )
                                    ? null
                                    : (_) => controller.togglePackUsage(
                                        ImagePackUsage.sticker,
                                      ),
                              ),
                              const ListDivider(),
                            ],
                            if (!controller.readonly) ...[
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: ElevatedButton.icon(
                                  onPressed: controller.createStickers,
                                  icon: const Icon(Icons.upload_outlined),
                                  label: Text(L10n.of(context).createSticker),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (imageKeys.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        L10n.of(context).noEmotesFound,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate((
                    BuildContext context,
                    int i,
                  ) {
                    final imageCode = imageKeys[i];
                    final image = controller.pack!.images[imageCode]!;
                    // TODO: dispose this
                    final textEditingController = TextEditingController();
                    textEditingController.text = imageCode;
                    final useShortCuts =
                        (PlatformInfos.isWeb || PlatformInfos.isDesktop);

                    return ListTile(
                      title: Shortcuts(
                        shortcuts: !useShortCuts
                            ? {}
                            : {
                                LogicalKeySet(LogicalKeyboardKey.enter):
                                    SubmitLineIntent(),
                              },
                        child: Actions(
                          actions: !useShortCuts
                              ? {}
                              : {
                                  SubmitLineIntent: CallbackAction(
                                    onInvoke: (i) {
                                      controller.submitImageAction(
                                        imageCode,
                                        image,
                                        textEditingController,
                                      );
                                      return null;
                                    },
                                  ),
                                },
                          child: TextField(
                            readOnly: controller.readonly,
                            controller: textEditingController,
                            autocorrect: false,
                            minLines: 1,
                            maxLines: 1,
                            maxLength: 128,
                            decoration: InputDecoration(
                              hintText: L10n.of(context).emoteShortcode,
                              prefixText: ': ',
                              suffixText: ':',
                              counter: const SizedBox.shrink(),
                              filled: false,
                              enabledBorder: const OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: Colors.transparent,
                                ),
                              ),
                            ),
                            onSubmitted: (s) => controller.submitImageAction(
                              imageCode,
                              image,
                              textEditingController,
                            ),
                          ),
                        ),
                      ),
                      leading: _EmoteImage(image.url),
                      trailing: controller.readonly
                          ? null
                          : IconButton(
                              tooltip: L10n.of(context).delete,
                              onPressed: () =>
                                  controller.removeImageAction(imageCode),
                              icon: const Icon(Icons.delete_outlined),
                            ),
                    );
                  }, childCount: imageKeys.length),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmoteImage extends StatelessWidget {
  final Uri mxc;

  const _EmoteImage(this.mxc);

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    final key = 'sticker_preview_$mxc';
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => showDialog(
        context: context,
        useRootNavigator: false,
        builder: (_) => MxcImageViewer(mxc),
      ),
      child: MxcImage(
        key: ValueKey(key),
        cacheKey: key,
        uri: mxc,
        fit: BoxFit.contain,
        width: size,
        height: size,
        isThumbnail: true,
        animated: true,
      ),
    );
  }
}

class SubmitLineIntent extends Intent {}
