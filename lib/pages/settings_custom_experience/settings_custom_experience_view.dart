import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/layouts/max_width_body.dart';
import 'package:extera_next/widgets/list_divider.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'settings_custom_experience.dart';

class SettingsCustomExperienceView extends StatelessWidget {
  final SettingsCustomExperienceController controller;
  const SettingsCustomExperienceView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).customExperience),
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.textTheme.bodyLarge!.color,
        child: MaxWidthBody(
          withoutVerticalPadding: true,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Material(
                  clipBehavior: Clip.hardEdge,
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: borderRadius,
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(
                          L10n.of(context).roomsWithCustomSettings,
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const ListDivider(),
                      FutureBuilder<List<Room>>(
                        future: controller.customizedRooms,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.all(32),
                              child: CircularProgressIndicator.adaptive(),
                            );
                          }
                          final rooms = snapshot.data ?? const <Room>[];
                          if (rooms.isEmpty) return _emptyPlaceholder(context);
                          return Column(
                            children: [
                              for (final (index, room) in rooms.indexed) ...[
                                if (index > 0) const ListDivider(),
                                ListTile(
                                  leading: Avatar(
                                    mxContent: room.avatar,
                                    name: room.getLocalizedDisplayname(),
                                    client: client,
                                  ),
                                  title: Text(room.getLocalizedDisplayname()),
                                  onTap: () =>
                                      controller.openRoom(context, room),
                                  trailing: const Icon(
                                    Icons.chevron_right_outlined,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.tune_outlined,
              size: 36,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            L10n.of(context).noCustomSettings,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            L10n.of(context).noCustomSettingsDetails,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
