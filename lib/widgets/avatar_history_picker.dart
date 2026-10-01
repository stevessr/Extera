import 'package:material_ui/material_ui.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/adaptive_bottom_sheet.dart';
import 'package:extera_next/utils/avatar_history.dart';
import 'package:extera_next/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:extera_next/widgets/avatar.dart';

/// Shows the locally cached historical avatars and returns the picked mxc
/// URI, or null when the sheet was dismissed.
///
/// Short-press keeps the fast selection flow. Long-press (or secondary click
/// on desktop) opens management actions for the entry.
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
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                L10n.of(sheetContext).avatarHistory,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.55,
              ),
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Text(
                        L10n.of(sheetContext).noAvatarHistory,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 96,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final mxc = entries[i];

                        Future<void> manage() async {
                          final action =
                              await showModalActionPopup<_AvatarHistoryAction>(
                                context: sheetContext,
                                title: L10n.of(sheetContext).avatarHistory,
                                cancelLabel: L10n.of(sheetContext).cancel,
                                actions: [
                                  AdaptiveModalAction(
                                    value: _AvatarHistoryAction.remove,
                                    label: L10n.of(sheetContext).delete,
                                    isDestructive: true,
                                    icon: const Icon(Icons.delete_outlined),
                                  ),
                                ],
                              );
                          if (action != _AvatarHistoryAction.remove) return;
                          await AvatarHistory.remove(mxc);
                          if (!sheetContext.mounted) return;
                          setSheetState(() => entries.remove(mxc));
                        }

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: manage,
                          onSecondaryTap: manage,
                          child: Avatar(
                            mxContent: Uri.parse(mxc),
                            name: null,
                            size: 80,
                            onTap: () => Navigator.of(context).pop(mxc),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

enum _AvatarHistoryAction { remove }
