// import 'package:extera_next/config/app_config.dart';

import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/url_launcher.dart';
import 'package:extera_next/widgets/adaptive_dialogs/dialog_text_field.dart';

Future<(PresenceType, String?)?> showStatusInputDialog({
  required BuildContext context,
  bool useRootNavigator = false,
  PresenceType? initialPresence,
  String? initialText,
}) {
  final presenceNotifier = ValueNotifier<PresenceType>(
    initialPresence ?? PresenceType.online,
  );

  return showAdaptiveDialog<(PresenceType, String?)>(
    context: context,
    useRootNavigator: useRootNavigator,
    builder: (context) {
      final controller = TextEditingController(text: initialText);
      final error = ValueNotifier<String?>(null);

      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 768),
        child: AlertDialog.adaptive(
          title: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 256),
            child: Text(L10n.of(context).setStatus),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 768),
            child: Column(
              mainAxisSize: .min,
              children: [
                SelectableLinkify(
                  text: L10n.of(context).leaveEmptyToClearStatus,
                  style: Theme.of(context).textTheme.bodyMedium,
                  linkStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    decorationColor: Theme.of(context).colorScheme.primary,
                  ),
                  options: const LinkifyOptions(humanize: false),
                  onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<String?>(
                  valueListenable: error,
                  builder: (context, errorValue, _) {
                    return DialogTextField(
                      hintText: L10n.of(context).statusExampleMessage,
                      errorText: errorValue,
                      controller: controller,
                      initialText: initialText,
                      minLines: 1,
                      maxLines: 6,
                    );
                  },
                ),
                const SizedBox(height: 16),
                // 3. Wrap SegmentedButton in ValueListenableBuilder
                // if (!AppConfig.autoMarkUnavailable)
                ValueListenableBuilder<PresenceType>(
                  valueListenable: presenceNotifier,
                  builder: (context, currentPresence, _) {
                    return SegmentedButton<PresenceType>(
                      segments: [
                        ButtonSegment(
                          value: PresenceType.online,
                          label: Text(L10n.of(context).online),
                        ),
                        ButtonSegment(
                          value: PresenceType.unavailable,
                          label: Text(L10n.of(context).unavailable),
                        ),
                        ButtonSegment(
                          value: PresenceType.offline,
                          label: Text(L10n.of(context).offline),
                        ),
                      ],
                      // Use the value from the builder
                      selected: {currentPresence},
                      onSelectionChanged: (value) {
                        // Update the notifier to trigger a rebuild
                        presenceNotifier.value = value.first;
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(null),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24.0),
                ),
              ),
              child: Text(L10n.of(context).cancel),
            ),
            FilledButton(
              onPressed: () {
                final input = controller.text;

                // IMPORTANT: currently you are only returning the text.
                // The selected presence is stored in `presenceNotifier.value`.
                // You likely want to handle that here.

                Navigator.of(
                  context,
                ).pop<(PresenceType, String?)>((presenceNotifier.value, input));
              },
              autofocus: true,
              child: Text(L10n.of(context).ok),
            ),
          ],
        ),
      );
    },
  );
}
