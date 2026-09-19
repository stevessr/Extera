import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';

class ChatCallIndicator extends StatelessWidget {
  final Room room;

  const ChatCallIndicator({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final callMemberCount = room.getActiveMatrixRtcMembers().length;
    if (callMemberCount == 0) return const SizedBox.shrink();

    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      child: Padding(
        padding: const .symmetric(vertical: 2, horizontal: 8),
        child: Row(
          mainAxisSize: .min,
          spacing: 2,
          children: [
            const Icon(Icons.mic_outlined, size: 18),
            Text(
              callMemberCount.toString(),
              style: TextStyle(color: theme.colorScheme.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
