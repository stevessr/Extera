import 'package:material_ui/material_ui.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/dialer/livekit_call_screen.dart';

class BackToLiveKitCallButton extends StatelessWidget {
  final String? roomId;
  final BuildContext? context;

  const BackToLiveKitCallButton({super.key, this.roomId, this.context});

  @override
  Widget build(BuildContext context) {
    if (roomId == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: FilledButton.tonal(
        onPressed: () {
          openLiveKitCall(context, roomId!);
        },
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_call),
            const SizedBox(width: 18),
            Text(L10n.of(context).backToCall),
          ],
        ),
      ),
    );
  }
}
