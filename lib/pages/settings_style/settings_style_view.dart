import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat/events/message.dart';
import 'package:extera_next/pages/chat/events/state_message.dart';
import 'package:extera_next/utils/color_value.dart';
import 'package:extera_next/utils/dummy_timeline.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/wallpaper.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';
import 'package:extera_next/widgets/list_divider.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/widgets/theme_builder.dart';
import '../../config/app_config.dart';
import '../../widgets/settings_switch_list_tile.dart';
import 'settings_style.dart';

class SettingsStyleView extends StatelessWidget {
  final SettingsStyleController controller;

  const SettingsStyleView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);

    const colorPickerSize = 32.0;
    final client = Matrix.of(context).client;

    final paletteNames = {
      DynamicSchemeVariant.tonalSpot: L10n.of(context).palette_tonalSpot,
      DynamicSchemeVariant.fidelity: L10n.of(context).palette_fidelity,
      DynamicSchemeVariant.monochrome: L10n.of(context).palette_monochrome,
      DynamicSchemeVariant.neutral: L10n.of(context).palette_neutral,
      DynamicSchemeVariant.vibrant: L10n.of(context).palette_vibrant,
      DynamicSchemeVariant.expressive: L10n.of(context).palette_expressive,
      DynamicSchemeVariant.content: L10n.of(context).palette_content,
      DynamicSchemeVariant.rainbow: L10n.of(context).palette_rainbow,
      DynamicSchemeVariant.fruitSalad: L10n.of(context).palette_fruitSalad,
    };

    final wallpaperImage = wallpaperImageProvider(controller.wallpaperPath);
    final hasWallpaper = wallpaperImage != null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
        title: Text(L10n.of(context).changeTheme),
      ),
      backgroundColor: theme.colorScheme.surface,
      body: MaxWidthBody(
        withoutVerticalPadding: true,
        child: Padding(
          padding: const .all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: theme.colorScheme.surfaceContainerHigh,
                clipBehavior: Clip.hardEdge,
                borderRadius: borderRadius,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: SegmentedButton<ThemeMode>(
                        selected: {controller.currentTheme},
                        onSelectionChanged: (selected) =>
                            controller.switchTheme(selected.single),
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text(L10n.of(context).lightTheme),
                            icon: const Icon(Icons.light_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text(L10n.of(context).darkTheme),
                            icon: const Icon(Icons.dark_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text(L10n.of(context).systemTheme),
                            icon: const Icon(Icons.auto_mode_outlined),
                          ),
                        ],
                      ),
                    ),
                    if (controller.currentTheme != ThemeMode.light) ...[
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).pureBlackToggle,
                        onChanged: (b) =>
                            ThemeController.of(context).setPureBlack(b),
                        setting: AppSettings.pureBlack,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: theme.colorScheme.surfaceContainerHigh,
                clipBehavior: Clip.hardEdge,
                borderRadius: borderRadius,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        L10n.of(context).setColorTheme,
                        style: TextStyle(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DynamicColorBuilder(
                      builder: (light, dark) {
                        final systemColor =
                            Theme.of(context).brightness == Brightness.light
                            ? light?.primary
                            : dark?.primary;
                        final colors = [
                          null,
                          AppConfig.chatColor,
                          ...Colors.primaries,
                        ];
                        if (systemColor == null) {
                          colors.remove(null);
                        }
                        return GridView.builder(
                          shrinkWrap: true,
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 64,
                              ),
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: colors.length,
                          itemBuilder: (context, i) {
                            final color = colors[i];
                            return Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Tooltip(
                                message: color == null
                                    ? L10n.of(context).systemTheme
                                    : '#${color.hexValue.toRadixString(16).toUpperCase()}',
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    colorPickerSize,
                                  ),
                                  onTap: () => controller.setChatColor(color),
                                  child: Material(
                                    color: color ?? systemColor,
                                    elevation: 0,
                                    borderRadius: BorderRadius.circular(
                                      colorPickerSize,
                                    ),
                                    child: SizedBox(
                                      width: colorPickerSize,
                                      height: colorPickerSize,
                                      child: controller.currentColor == color
                                          ? Center(
                                              child: Icon(
                                                Icons.check,
                                                size: 16,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onPrimary,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    const ListDivider(),
                    ListTile(
                      subtitle: Text(
                        paletteNames[ThemeController.of(context).variant]!,
                      ),
                      title: Text(L10n.of(context).colorPalette),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: controller.setSchemeVariant,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: theme.colorScheme.surfaceContainerHigh,
                clipBehavior: Clip.hardEdge,
                borderRadius: borderRadius,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        L10n.of(context).messagesStyle,
                        style: TextStyle(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: FluffyThemes.animationDuration,
                          curve: FluffyThemes.animationCurve,
                          decoration: const BoxDecoration(),
                          clipBehavior: Clip.hardEdge,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (hasWallpaper)
                                Positioned.fill(
                                  child: ClipRect(
                                    child: Opacity(
                                      opacity: controller.wallpaperOpacity,
                                      child: ImageFiltered(
                                        imageFilter: ImageFilter.blur(
                                          sigmaX: controller.wallpaperBlur,
                                          sigmaY: controller.wallpaperBlur,
                                        ),
                                        child: Image(
                                          image: wallpaperImage,
                                          fit: BoxFit.cover,
                                          width: FluffyThemes.columnWidth * 2,
                                          height: 212,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 16),
                                  Material(
                                    color: hasWallpaper
                                        ? Colors.transparent
                                        : theme.scaffoldBackgroundColor,
                                    child: Column(
                                      children: [
                                        StateMessage(
                                          Event(
                                            eventId: 'style_dummy',
                                            room: Room(
                                              id: '!style_dummy',
                                              client: client,
                                            ),
                                            content: {'membership': 'join'},
                                            type: EventTypes.RoomMember,
                                            senderId: client.userID!,
                                            originServerTs: DateTime.now(),
                                            stateKey: client.userID!,
                                          ),
                                          selected: false,
                                        ),
                                        Message(
                                          Event(
                                            eventId: 'style_dummy_1',
                                            content: {
                                              'msgtype': 'm.text',
                                              'body': L10n.of(
                                                context,
                                              ).settingsStyleMessage1,
                                              'format':
                                                  'org.matrix.custom.html',
                                              'formatted_body': L10n.of(
                                                context,
                                              ).settingsStyleMessage1,
                                            },
                                            originServerTs: DateTime.now(),
                                            senderId: client.userID!,
                                            status: .sent,
                                            type: EventTypes.Message,
                                            room: Room(
                                              id: '!style_dummy',
                                              client: client,
                                            ),
                                          ),
                                          exampleMessage: true,
                                          onInfoTab: (_) {},
                                          onMention: () {},
                                          onSelect: (_, _) {},
                                          onSwipe: (_) {},
                                          scrollToEventId: (_, _) => {},
                                          timeline: DummyTimeline(),
                                          animateIn: false,
                                          displayReadMarker: false,
                                          highlightMarker: false,
                                          longPressSelect: false,
                                          selected: false,
                                          wallpaperMode: false,
                                          colors: [
                                            theme.secondaryBubbleColor,
                                            theme.bubbleColor,
                                          ],
                                          layout: controller.messageStyle,
                                        ),
                                        Message(
                                          Event(
                                            eventId: 'style_dummy_2',
                                            content: {
                                              'msgtype': 'm.text',
                                              'body': L10n.of(
                                                context,
                                              ).settingsStyleMessage2,
                                              'format':
                                                  'org.matrix.custom.html',
                                              'formatted_body': L10n.of(
                                                context,
                                              ).settingsStyleMessage2,
                                            },
                                            originServerTs: DateTime.now(),
                                            senderId: '@yuki:example.com',
                                            status: .sent,
                                            type: EventTypes.Message,
                                            room: Room(
                                              id: '!style_dummy',
                                              client: client,
                                            ),
                                          ),
                                          exampleMessage: true,
                                          onInfoTab: (_) {},
                                          onMention: () {},
                                          onSelect: (_, _) {},
                                          onSwipe: (_) {},
                                          scrollToEventId: (_, _) => {},
                                          timeline: DummyTimeline(),
                                          animateIn: false,
                                          displayReadMarker: false,
                                          highlightMarker: false,
                                          longPressSelect: false,
                                          selected: false,
                                          wallpaperMode: false,
                                          colors: [
                                            theme.secondaryBubbleColor,
                                            theme.bubbleColor,
                                          ],
                                          layout: controller.messageStyle,
                                        ),
                                        Message(
                                          Event(
                                            eventId: 'style_dummy_3',
                                            content: {
                                              'msgtype': 'm.text',
                                              'body': L10n.of(
                                                context,
                                              ).settingsStyleMessage3,
                                              'format':
                                                  'org.matrix.custom.html',
                                              'formatted_body': L10n.of(
                                                context,
                                              ).settingsStyleMessage3,
                                            },
                                            originServerTs: DateTime.now(),
                                            senderId: client.userID!,
                                            status: .sent,
                                            type: EventTypes.Message,
                                            room: Room(
                                              id: '!style_dummy',
                                              client: client,
                                            ),
                                          ),
                                          exampleMessage: true,
                                          onInfoTab: (_) {},
                                          onMention: () {},
                                          onSelect: (_, _) {},
                                          onSwipe: (_) {},
                                          scrollToEventId: (_, _) => {},
                                          timeline: DummyTimeline(),
                                          animateIn: false,
                                          displayReadMarker: false,
                                          highlightMarker: false,
                                          longPressSelect: false,
                                          selected: false,
                                          wallpaperMode: false,
                                          colors: [
                                            theme.secondaryBubbleColor,
                                            theme.bubbleColor,
                                          ],
                                          layout: controller.messageStyle,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ListTile(
                          title: Text(
                            L10n.of(context).messageLayout,
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 16,
                            left: 32,
                            right: 32,
                          ),
                          child: RadioGroup<MessageLayout>(
                            onChanged: (value) {
                              if (value != null) {
                                controller.setMessageStyle(value);
                              }
                            },
                            groupValue: controller.messageStyle,
                            child: Row(
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: .center,
                                    child: _LabeledRadio<MessageLayout>(
                                      label: L10n.of(context).bubblesLayout,
                                      value: .bubbles,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: .center,
                                    child: _LabeledRadio<MessageLayout>(
                                      label: L10n.of(
                                        context,
                                      ).legacyBubblesLayout,
                                      value: .bubblesLegacy,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: .center,
                                    child: _LabeledRadio<MessageLayout>(
                                      label: L10n.of(context).modernLayout,
                                      value: .modern,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const ListDivider(),
                        // SettingsSwitchListTile.adaptive(
                        //   title: L10n.of(context).enableGradient,
                        //   setting: AppSettings.enableGradient,
                        // ),
                        // const ListDivider(),
                        SettingsSwitchListTile.adaptive(
                          title: L10n.of(context).enableChatFrostedGlass,
                          setting: AppSettings.enableChatFrostedGlass,
                        ),
                        const ListDivider(),
                        SettingsSwitchListTile.adaptive(
                          title: L10n.of(context).showSeconds,
                          setting: AppSettings.showSeconds,
                          onChanged: controller.toggleShowSeconds,
                        ),
                        const ListDivider(),
                        SettingsSwitchListTile.adaptive(
                          title: L10n.of(context).useNotoEmoji,
                          setting: AppSettings.notoEmojiFont,
                          // Rebuild so that the animated emoji switch below
                          // appears or disappears right away.
                          onChanged: controller.refreshView,
                        ),
                        if (AppSettings.notoEmojiFont.value) ...[
                          const ListDivider(),
                          SettingsSwitchListTile.adaptive(
                            title: L10n.of(context).useAnimatedEmoji,
                            subtitle: L10n.of(
                              context,
                            ).useAnimatedEmojiDescription,
                            setting: AppSettings.animatedEmoji,
                          ),
                        ],
                        const ListDivider(),
                        const SizedBox(height: 8),
                        ListTile(
                          title: TextButton.icon(
                            style: TextButton.styleFrom(
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onSecondaryContainer,
                            ),
                            onPressed: controller.setWallpaper,
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(L10n.of(context).setWallpaper),
                          ),
                          trailing: !hasWallpaper
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.delete_outlined),
                                  color: theme.colorScheme.error,
                                  onPressed: controller.deleteChatWallpaper,
                                ),
                        ),
                        if (hasWallpaper) ...[
                          ListTile(title: Text(L10n.of(context).opacity)),
                          Slider.adaptive(
                            min: 0.1,
                            max: 1.0,
                            divisions: 9,
                            semanticFormatterCallback: (d) => d.toString(),
                            value: controller.wallpaperOpacity,
                            onChanged: controller.updateWallpaperOpacity,
                            onChangeEnd: controller.saveWallpaperOpacity,
                          ),
                          ListTile(title: Text(L10n.of(context).blur)),
                          Slider.adaptive(
                            min: 0.0,
                            max: 10.0,
                            divisions: 10,
                            semanticFormatterCallback: (d) => d.toString(),
                            value: controller.wallpaperBlur,
                            onChanged: controller.updateWallpaperBlur,
                            onChangeEnd: controller.saveWallpaperBlur,
                          ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                    const ListDivider(),
                    ListTile(
                      title: Text(L10n.of(context).fontSize),
                      trailing: Text(
                        '× ${AppSettings.fontSizeFactor.value.toStringAsFixed(2)}',
                      ),
                    ),
                    Slider.adaptive(
                      min: 0.5,
                      max: 2.5,
                      divisions: 20,
                      value: AppSettings.fontSizeFactor.value,
                      semanticFormatterCallback: (d) => d.toString(),
                      onChanged: controller.changeFontSizeFactor,
                    ),
                    const ListDivider(),
                    ListTile(
                      title: Text(L10n.of(context).avatarBorderRadius),
                      trailing: Text(
                        '× ${AppSettings.avatarBorderRadius.value}',
                      ),
                    ),
                    Slider.adaptive(
                      min: 0.5,
                      max: 1,
                      divisions: 20,
                      value: AppSettings.avatarBorderRadius.value,
                      semanticFormatterCallback: (d) => d.toString(),
                      onChanged: controller.changeAvatarBorderRadius,
                    ),
                    const ListDivider(),
                    ListTile(
                      title: Text(L10n.of(context).stickerScale),
                      trailing: Text('× ${AppSettings.stickerScale.value}'),
                    ),
                    Slider.adaptive(
                      min: 1,
                      max: 5,
                      divisions: 20,
                      value: AppSettings.stickerScale.value,
                      semanticFormatterCallback: (d) => d.toString(),
                      onChanged: controller.changeStickerScale,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: theme.colorScheme.surfaceContainerHigh,
                clipBehavior: Clip.hardEdge,
                borderRadius: borderRadius,
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        L10n.of(context).fonts,
                        style: TextStyle(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ListTile(
                      title: Text(L10n.of(context).uiFont),
                      trailing: FilledButton.tonalIcon(
                        onPressed: controller.editUIFont,
                        icon: const Icon(Icons.edit),
                        label: Text(L10n.of(context).edit),
                      ),
                    ),
                    const ListDivider(),
                    ListTile(
                      title: Text(L10n.of(context).uiFontFallback),
                      trailing: FilledButton.tonalIcon(
                        onPressed: controller.editUIFallbackFonts,
                        icon: const Icon(Icons.edit),
                        label: Text(L10n.of(context).edit),
                      ),
                    ),
                    const ListDivider(),
                    ListTile(
                      title: Text(L10n.of(context).monospaceFont),
                      trailing: FilledButton.tonalIcon(
                        onPressed: controller.editMonospaceFont,
                        icon: const Icon(Icons.edit),
                        label: Text(L10n.of(context).edit),
                      ),
                    ),
                    const ListDivider(),
                    ListTile(
                      title: Text(L10n.of(context).monospaceFontFallback),
                      trailing: FilledButton.tonalIcon(
                        onPressed: controller.editMonospaceFallbackFonts,
                        icon: const Icon(Icons.edit),
                        label: Text(L10n.of(context).edit),
                      ),
                    ),
                    const ListDivider(),
                    ListTile(
                      title: Text(L10n.of(context).chatFont),
                      trailing: FilledButton.tonalIcon(
                        onPressed: controller.editChatFont,
                        icon: const Icon(Icons.edit),
                        label: Text(L10n.of(context).edit),
                      ),
                    ),
                    const ListDivider(),
                    ListTile(
                      title: Text(L10n.of(context).chatFontFallback),
                      trailing: FilledButton.tonalIcon(
                        onPressed: controller.editChatFallbackFonts,
                        icon: const Icon(Icons.edit),
                        label: Text(L10n.of(context).edit),
                      ),
                    ),
                    if (PlatformInfos.isAndroid) ...[
                      const ListDivider(),
                      SettingsSwitchListTile.adaptive(
                        title: L10n.of(context).systemFont,
                        setting: AppSettings.systemFont,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledRadio<T> extends StatelessWidget {
  const _LabeledRadio({required this.label, required this.value});

  final String label;
  final T value;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        RadioGroup.maybeOf<T>(context)?.onChanged(value);
      },
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      child: Padding(
        padding: const .only(right: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Radio<T>(value: value),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
