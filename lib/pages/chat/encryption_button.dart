import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import '../../widgets/matrix.dart';

class EncryptionButton extends StatefulWidget {
  final Room room;
  const EncryptionButton(this.room, {super.key});

  @override
  State<EncryptionButton> createState() => _EncryptionButtonState();
}

class _EncryptionButtonState extends State<EncryptionButton> {
  /// Stable device-list pipeline; recomposing it in build() would
  /// resubscribe on every per-second chat page setState.
  late final Stream<SyncUpdate> _deviceListsStream = Matrix.of(
    context,
  ).client.onSync.stream.where((s) => s.deviceLists != null);

  Future<EncryptionHealthState>? _healthFuture;
  Room? _healthRoom;
  SyncUpdate? _healthTrigger;

  /// Recalculates encryption health only when the room changed or a new
  /// device-list sync arrived; previously this ran on every rebuild.
  Future<EncryptionHealthState> _calcHealth(SyncUpdate? trigger) {
    if (_healthFuture == null ||
        !identical(trigger, _healthTrigger) ||
        !identical(widget.room, _healthRoom)) {
      _healthTrigger = trigger;
      _healthRoom = widget.room;
      _healthFuture = widget.room.encrypted
          ? widget.room.calcEncryptionHealthState()
          : Future.value(EncryptionHealthState.allVerified);
    }
    return _healthFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncUpdate>(
      stream: _deviceListsStream,
      builder: (context, snapshot) {
        return FutureBuilder<EncryptionHealthState>(
          future: _calcHealth(snapshot.data),
          builder: (BuildContext context, snapshot) => IconButton(
            tooltip: widget.room.encrypted
                ? L10n.of(context).encrypted
                : L10n.of(context).encryptionNotEnabled,
            icon: Icon(
              widget.room.encrypted
                  ? Icons.lock_outlined
                  : Icons.lock_open_outlined,
              size: 20,
              color:
                  widget.room.joinRules != JoinRules.public &&
                      !widget.room.encrypted
                  ? Colors.red
                  : widget.room.joinRules != JoinRules.public &&
                        snapshot.data == EncryptionHealthState.unverifiedDevices
                  ? Colors.orange
                  : null,
            ),
            onPressed: () => context.go('/rooms/${widget.room.id}/encryption'),
          ),
        );
      },
    );
  }
}
