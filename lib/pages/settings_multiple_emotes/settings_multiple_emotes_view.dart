import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/settings_multiple_emotes/settings_multiple_emotes.dart';
import 'package:extera_next/utils/image_pack_migration.dart';
import 'package:extera_next/widgets/matrix.dart';

class MultipleEmotesSettingsView extends StatelessWidget {
  final MultipleEmotesSettingsController controller;

  const MultipleEmotesSettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(context).client.getRoomById(controller.roomId!)!;
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(L10n.of(context).emotePacks),
      ),
      body: StreamBuilder(
        stream: room.client.onRoomState.stream.where(
          (update) => update.roomId == room.id,
        ),
        builder: (context, snapshot) {
          final legacyPacks = room.states[legacyRoomImagePackEventType];
          final stablePacks = room.states[EventTypes.RoomImagePack];
          // Stable state wins if both event types use the same state key.
          final packs = <String, StrippedStateEvent?>{
            if (legacyPacks != null)
              ...Map<String, StrippedStateEvent?>.of(legacyPacks),
            if (stablePacks != null)
              ...Map<String, StrippedStateEvent?>.of(stablePacks),
          };
          if (!packs.containsKey('')) {
            packs[''] = null;
          }
          final keys = packs.keys.toList();
          keys.sort();
          return ListView.separated(
            separatorBuilder: (BuildContext context, int i) =>
                const SizedBox.shrink(),
            itemCount: keys.length,
            itemBuilder: (BuildContext context, int i) {
              final event = packs[keys[i]];
              final eventPack = event?.content.tryGetMap<String, Object?>(
                'pack',
              );
              final packName =
                  eventPack?.tryGet<String>('display_name') ??
                  eventPack?.tryGet<String>('name') ??
                  (keys[i].isNotEmpty ? keys[i] : 'Default Pack');

              return ListTile(
                title: Text(packName),
                onTap: () async {
                  context.go(
                    [
                      '',
                      'rooms',
                      room.id,
                      'details',
                      'emotes',
                      keys[i],
                    ].join('/'),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
