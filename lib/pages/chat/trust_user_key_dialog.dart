// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
// SPDX-FileCopyrightText: 2026-Present rustyraven <rustyraven[at]extera[dot]xyz>
// SPDX-FileCopyrightText: 2026-Present Contributors to Extera
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/key_verification/key_verification_dialog.dart';
import 'package:extera_next/utils/beautify_string_extension.dart';
import 'package:extera_next/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:extera_next/widgets/avatar.dart';

Future<bool> showTrustUserInRoomDialog(BuildContext context, Room room) async {
  if (!room.encrypted) return true;

  final users = await room.requestParticipants();
  if (!context.mounted) return false;

  users.removeWhere((user) {
    if (user.id == room.client.userID) return true;
    final keys = room.client.userDeviceKeys[user.id];
    final masterKey = keys?.masterKey;

    if (keys == null ||
        masterKey == null ||
        masterKey.verified ||
        masterKey.trustOnFirstUseSince != null) {
      return true;
    }
    return false;
  });

  if (users.isEmpty) return true;

  final l10n = L10n.of(context);
  final theme = Theme.of(context);

  final action = await showAdaptiveDialog<_Action>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Center(
        child: Icon(
          Icons.lock_outlined,
          size: 32,
          color: theme.colorScheme.primary,
        ),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 128),
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Text(
                  users.length == 1
                      ? l10n.messageCanOnlyBeReadByUser
                      : l10n.messageCanOnlyBeReadByUsers,
                  style: TextStyle(fontSize: 16),
                  textAlign: .center,
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: users
                            .map(
                              (user) => ListTile(
                                leading: Avatar(
                                  mxContent: user.avatarUrl,
                                  name: user.calcDisplayname(),
                                ),
                                title: Text(
                                  user.calcDisplayname(),
                                  maxLines: 1,
                                  textAlign: TextAlign.start,
                                ),
                                subtitle: Text(
                                  room
                                          .client
                                          .userDeviceKeys[user.id]
                                          ?.masterKey
                                          ?.publicKey
                                          ?.beautifiedOneLine ??
                                      '???',
                                  style: TextStyle(
                                    fontFamily: AppSettings.monospaceFont.value,
                                    fontFamilyFallback: AppSettings.fontFallback(
                                      AppSettings.monospaceFallbackFonts,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          autofocus: true,
          bigButtons: true,
          onPressed: () {
            for (final user in users) {
              room.client.userDeviceKeys[user.id]?.masterKey?.trustOnFirstUse();
            }
            Navigator.of(context).pop(_Action.allow);
          },
          child: Text(L10n.of(context).continueText),
        ),
        if (room.isDirectChat)
          AdaptiveDialogAction(
            bigButtons: true,
            onPressed: () => Navigator.of(context).pop(_Action.verification),
            child: Text(L10n.of(context).interactiveVerification),
          ),
        AdaptiveDialogAction(
          bigButtons: true,
          onPressed: () => Navigator.of(context).pop(_Action.deny),
          child: Text(l10n.cancel),
        ),
      ],
    ),
  );

  if (action == null) return false;

  switch (action) {
    case _Action.allow:
      for (final user in users) {
        room.client.userDeviceKeys[user.id]?.masterKey?.trustOnFirstUse();
      }
    case _Action.deny:
      return false;
    case _Action.verification:
      final req = await room.client.userDeviceKeys[room.directChatMatrixID]
          ?.startVerification();
      if (req == null) return false;
      if (!context.mounted) return false;
      final success = await KeyVerificationDialog(request: req).show(context);
      return success == true;
  }

  return true;
}

enum _Action { allow, deny, verification }
