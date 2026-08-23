import 'package:flutter/material.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/avatar_history.dart';
import 'package:extera_next/widgets/avatar.dart';

/// Shows the locally cached historical avatars and returns the picked mxc
/// URI, or null when the sheet was dismissed.
Future<String?> showAvatarHistoryPicker(BuildContext context) async {
  final entries = await AvatarHistory.load();
  if (!context.mounted) return null;
  if (entries.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L10n.of(context).noAvatarHistory)));
    return null;
  }
  return showAdaptiveBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              L10n.of(context).avatarHistory,
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 96,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: entries.length,
              itemBuilder: (context, i) => Avatar(
                mxContent: Uri.tryParse(entries[i]),
                name: null,
                size: 80,
                onTap: () => Navigator.of(context).pop(entries[i]),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
