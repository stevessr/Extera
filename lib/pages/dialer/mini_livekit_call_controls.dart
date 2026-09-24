import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/dialer/livekit_call_manager.dart';
import 'package:extera_next/pages/dialer/livekit_call_screen.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:extera_next/widgets/avatar.dart';

class MiniLiveKitCallControls extends StatelessWidget {
  const MiniLiveKitCallControls({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = LiveKitCallManager();
    return ValueListenableBuilder<String?>(
      valueListenable: manager.currentCallRoomId,
      builder: (context, roomId, _) {
        if (roomId == null) {
          return const SizedBox.shrink();
        }
        final room = manager.currentMatrixRoom;
        return ValueListenableBuilder<bool>(
          valueListenable: manager.micMuted,
          builder: (context, micMuted, _) {
            final paddingChild = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => openLiveKitCall(context, roomId),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Avatar(
                            mxContent: room?.avatar,
                            name:
                                room?.getLocalizedDisplayname(
                                  MatrixLocals(L10n.of(context)),
                                ) ??
                                roomId,
                            size: 36,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  room?.getLocalizedDisplayname(
                                        MatrixLocals(L10n.of(context)),
                                      ) ??
                                      roomId,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                                ValueListenableBuilder<int>(
                                  valueListenable: manager.participantCount,
                                  builder: (context, participantCount, _) {
                                    return Text(
                                      participantCount == 0
                                          ? L10n.of(
                                              context,
                                            ).waitingForParticipants
                                          : '${L10n.of(context).ongoingElementCall} \u00b7 ${L10n.of(context).countParticipants(participantCount)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: L10n.of(context).muteMic,
                    onPressed: manager.toggleMute,
                    icon: Icon(micMuted ? Icons.mic_off : Icons.mic),
                    color: micMuted
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  IconButton(
                    tooltip: L10n.of(context).hangUp,
                    onPressed: manager.hangup,
                    icon: const Icon(Icons.call_end_outlined),
                    color: theme.colorScheme.error,
                  ),
                ],
              ),
            );
            return AppSettings.enableChatFrostedGlass.value
                ? _FloatingShell(
                    child: Material(
                      borderRadius: BorderRadius.circular(128),
                      clipBehavior: Clip.hardEdge,
                      color: Colors.transparent,
                      child: paddingChild,
                    ),
                  )
                : Material(
                    borderRadius: BorderRadius.circular(128),
                    clipBehavior: Clip.hardEdge,
                    color: theme.colorScheme.surfaceContainer,
                    child: paddingChild,
                  );
          },
        );
      },
    );
  }
}

class _FloatingShell extends StatelessWidget {
  final Widget child;
  const _FloatingShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PhysicalModel(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.hardEdge,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: theme.colorScheme.surfaceContainerHigh.withAlpha(
                theme.brightness == Brightness.dark ? 160 : 190,
              ),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withAlpha(60),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(
                    theme.brightness == Brightness.dark ? 60 : 20,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
