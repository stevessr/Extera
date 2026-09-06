import 'dart:async';

import 'package:action_slider/action_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/config/themes.dart';
import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/chat_list/chat_list.dart';
import 'package:extera_next/pages/dialer/livekit_call_manager.dart';
import 'package:extera_next/pages/dialer/livekit_call_screen.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/fluffy_chat_app.dart';
import 'package:extera_next/widgets/matrix.dart';

class LiveKitIncomingCallManager {
  static final LiveKitIncomingCallManager _instance =
      LiveKitIncomingCallManager._internal();
  factory LiveKitIncomingCallManager() => _instance;
  LiveKitIncomingCallManager._internal();

  OverlayEntry? _overlayEntry;

  String? _activeRoomId;

  bool _showing = false;

  Timer? _lifetimeTimer;

  MatrixState? _matrix;

  BuildContext? _resolveContext() {
    return ChatList.contextForVoip ??
        FluffyChatApp.router.routerDelegate.navigatorKey.currentContext;
  }

  void bind(MatrixState matrix) => _matrix = matrix;

  void register(
    Client client,
    Map<String, StreamSubscription<Event>> subs,
    String name,
  ) {
    if (!AppSettings.experimentalLiveKit.value) return;
    subs[name] ??= client.onTimelineEvent.stream.listen(
      (s) => _onSync(client, s),
    );
  }

  void _onSync(Client client, Event ev) {
    if (ev.type != 'org.matrix.msc4075.rtc.notification') return;
    if (ev.senderId == client.userID) return;
    _handleNotification(
      client,
      ev.room.id,
      ev.content,
      ev.senderId,
      ev.originServerTs,
    );
  }

  void _handleNotification(
    Client client,
    String roomId,
    Map<String, Object?> content,
    String senderId,
    DateTime originServerTs,
  ) {
    Logs().w(
      "[LiveKitIncoming] Handling notification in $roomId from $senderId",
    );
    final lifetimeMs = (content['lifetime'] as num?)?.toInt() ?? 30000;
    final senderTs = (content['sender_ts'] as num?)?.toInt();
    final referenceMs = senderTs ?? originServerTs.millisecondsSinceEpoch;
    final expiresAt = referenceMs + lifetimeMs;
    if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
      Logs().w('[LiveKitIncoming] Ignoring stale RTC notification in $roomId.');
      return;
    }

    if (LiveKitCallManager().isInCall) {
      Logs().w('[LiveKitIncoming] Ignoring notification: already in a call.');
      return;
    }

    if (_showing && _activeRoomId == roomId) {
      Logs().w(
        "[LiveKitIncoming] Ignoring notification: already showing && active room is current",
      );
      return;
    }

    if (_showing) {
      Logs().w("[LiveKitIncoming] Dismissing: already showing");
      _dismiss();
    }

    final room = client.getRoomById(roomId);
    if (room == null) return;

    _activeRoomId = roomId;
    _showing = true;

    if (PlatformInfos.isAndroid) {
      try {
        FlutterForegroundTask.setOnLockScreenVisibility(
          AppSettings.incomingCallsOnLockScreen.value,
        );
        FlutterForegroundTask.wakeUpScreen();
        FlutterForegroundTask.launchApp();
      } catch (e) {
        Logs().e('[LiveKitIncoming] bring-to-front failed', e);
      }
    }

    _startRingtone();

    _lifetimeTimer?.cancel();
    _lifetimeTimer = Timer(Duration(milliseconds: lifetimeMs), _dismiss);

    _present(room, senderId);
  }

  void _present(Room room, String senderId) {
    final context = _resolveContext();
    if (context == null) {
      Logs().w('[LiveKitIncoming] No context available to show popup.');
      _dismiss();
      return;
    }

    final client = room.client;

    if (FluffyThemes.isColumnMode(context) && !PlatformInfos.isMobile) {
      unawaited(
        showDialog(
          context: context,
          useRootNavigator: false,
          barrierDismissible: true,
          builder: (_) => _IncomingCallPopup(
            room: room,
            senderId: senderId,
            client: client,
            onAccept: () => _accept(context, room.id),
            onReject: () => _dismiss(),
          ),
        ).then((_) {
          if (_activeRoomId == room.id) {
            _dismiss();
          }
        }),
      );
    } else {
      final overlay = Overlay.of(context, rootOverlay: true);
      _overlayEntry = OverlayEntry(
        builder: (_) => _IncomingCallPopup(
          room: room,
          senderId: senderId,
          client: client,
          onAccept: () => _accept(context, room.id),
          onReject: () => _dismiss(),
        ),
      );
      overlay.insert(_overlayEntry!);
    }
  }

  void _accept(BuildContext context, String roomId) {
    _stopRingtone();
    _lifetimeTimer?.cancel();
    _lifetimeTimer = null;
    final entry = _overlayEntry;
    _overlayEntry = null;
    entry?.remove();
    _showing = false;
    _activeRoomId = null;
    if (FluffyThemes.isColumnMode(context)) {
      final nav = Navigator.of(context, rootNavigator: false);
      if (nav.canPop()) nav.pop();
    }
    unawaited(openLiveKitCall(context, roomId));
  }

  void _dismiss() {
    _stopRingtone();
    _lifetimeTimer?.cancel();
    _lifetimeTimer = null;
    _showing = false;
    _activeRoomId = null;
    final entry = _overlayEntry;
    _overlayEntry = null;
    entry?.remove();
    final context = _resolveContext();
    if (context != null && FluffyThemes.isColumnMode(context)) {
      final nav = Navigator.of(context, rootNavigator: false);
      if (nav.canPop()) nav.pop();
    }
  }

  void _startRingtone() {
    try {
      _matrix?.voipPlugin?.playRingtone();
    } catch (e) {
      Logs().e('[LiveKitIncoming] playRingtone failed', e);
    }
  }

  void _stopRingtone() {
    try {
      _matrix?.voipPlugin?.stopRingtone();
    } catch (e) {
      Logs().e('[LiveKitIncoming] stopRingtone failed', e);
    }
  }
}

class _IncomingCallPopup extends StatelessWidget {
  final Room room;
  final String senderId;
  final Client client;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingCallPopup({
    required this.room,
    required this.senderId,
    required this.client,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isColumn = FluffyThemes.isColumnMode(context);
    final useSlider = PlatformInfos.isMobile;

    final sender = room.unsafeGetUserFromMemoryOrFallback(senderId);
    final senderName = sender.calcDisplayname();
    final senderAvatar = sender.avatarUrl;
    final roomName = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );

    final topInfo = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          L10n.of(context).incomingCall,
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Text(
          senderName,
          style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(
              mxContent: room.avatar,
              name: roomName,
              size: 24,
              client: client,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'From $roomName',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );

    final centerAvatar = Avatar(
      mxContent: senderAvatar,
      name: senderName,
      size: 128,
      client: client,
    );

    final mobileSlider = ConstrainedBox(
      constraints: const BoxConstraints.tightFor(width: 312),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ActionSlider.dual(
          startChild: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.call_end, color: Colors.red),
                const SizedBox(width: 18),
                Text(L10n.of(context).hangUp),
              ],
            ),
          ),
          endChild: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L10n.of(context).answerCall),
                const SizedBox(width: 18),
                const Icon(Icons.call, color: Colors.green),
              ],
            ),
          ),
          icon: const Icon(Icons.phone),
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          toggleColor: theme.colorScheme.primary,
          sliderBehavior: SliderBehavior.move,
          startAction: (controller) {
            controller.loading();
            onReject();
            controller.success();
          },
          endAction: (controller) {
            controller.loading();
            onAccept();
            controller.success();
          },
        ),
      ),
    );

    if (useSlider) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.only(top: 48), child: topInfo),
              const Spacer(),
              Center(child: centerAvatar),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Center(child: mobileSlider),
              ),
            ],
          ),
        ),
      );
    }

    // Column-mode and desktop (non-mobile) share this card-style body.
    final cardBody = SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Avatar(
              mxContent: senderAvatar,
              name: senderName,
              size: 96,
              client: client,
            ),
            const SizedBox(height: 24),
            Text(
              L10n.of(context).incomingCall,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              senderName,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Avatar(
                  mxContent: room.avatar,
                  name: roomName,
                  size: 24,
                  client: client,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'From $roomName',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.left,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: 'lk_incoming_reject',
                  backgroundColor: theme.colorScheme.errorContainer,
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  tooltip: L10n.of(context).hangUp,
                  onPressed: onReject,
                  child: const Icon(Icons.call_end),
                ),
                FloatingActionButton(
                  heroTag: 'lk_incoming_accept',
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  tooltip: L10n.of(context).answerCall,
                  onPressed: onAccept,
                  child: const Icon(Icons.phone),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (isColumn) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            color: theme.colorScheme.surface,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(color: Colors.transparent, child: cardBody),
        ),
      );
    }

    return Material(color: theme.colorScheme.surface, child: cardBody);
  }
}
