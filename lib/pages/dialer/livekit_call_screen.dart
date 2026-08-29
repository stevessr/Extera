import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:extera_next/config/themes.dart';
import 'package:extera_next/utils/foreground_task_manager.dart';
import 'package:extera_next/utils/error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' show Client, Logs, DeviceKeys;

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/pages/dialer/dialer.dart';
import 'package:extera_next/pages/dialer/livekit_call_manager.dart';
import 'package:extera_next/pages/dialer/livekit_service.dart';
import 'package:extera_next/utils/matrix_sdk_extensions/call_members_extension.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/widgets/avatar.dart';
import 'package:extera_next/widgets/matrix.dart';
import 'package:extera_next/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:extera_next/utils/matrix_live_kit_calls/call_keys_event_content.dart';
import 'package:extera_next/utils/matrix_live_kit_calls/matrix_live_kit_call_member.dart';

class LiveKitCallScreen extends StatefulWidget {
  final String roomId;
  final List<String> liveKitServiceUrls;
  final String? callStateKey;
  const LiveKitCallScreen({
    required this.roomId,
    required this.liveKitServiceUrls,
    this.callStateKey,
    super.key,
  });

  @override
  State<LiveKitCallScreen> createState() => _LiveKitCallScreenState();
}

class _LiveKitCallScreenState extends State<LiveKitCallScreen> {
  lk.Room? _room;
  bool _connecting = true;
  String? _error;
  bool _disposed = false;
  Client? _client;
  String _localDisplayName = '';
  Uri? _localAvatar;
  StreamSubscription? _onCallEncryptionKeysSub;
  StreamSubscription? _onCallMembersChanged;
  lk.BaseKeyProvider? _keyProvider;
  Set<String> _lastSharedParticipants = {};
  DateTime? _keyCreatedAt;
  Uint8List? _lastKey;
  Timer? _membershipRefreshTimer;

  /// Latest encryption key index received per remote membership identity.
  /// Used to drop out-of-order keys and to resync receiver frame cryptors.
  final Map<String, int> _latestRemoteKeyIndex = {};

  static const Duration _membershipRefreshInterval = Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    final manager = LiveKitCallManager();
    if (manager.room != null && manager.currentRoomId == widget.roomId) {
      _room = manager.room;
      _client = manager.client ?? Matrix.of(context).client;
      _connecting = false;
      _screenShareActive =
          _room?.localParticipant?.videoTrackPublications.any(
            (pub) => pub.isScreenShare,
          ) ??
          false;
      _setupRoomListeners();
      // The previous screen state was disposed and cancelled the matrix
      // listeners with it. Re-register them, otherwise incoming E2EE keys
      // from other members are silently dropped after re-entering a call.
      if (_client != null) {
        _registerMatrixListeners(_client!);
      }
      // The call kept running while this screen was closed; make sure our
      // membership keeps being refreshed.
      _startMembershipRefreshTimer();
      _fetchProfile();
    } else {
      _connect();
    }
  }

  Future<void> _fetchProfile() async {
    final client = Matrix.of(context).client;
    final matrixRoom = client.getRoomById(widget.roomId);
    final profile = matrixRoom?.unsafeGetUserFromMemoryOrFallback(
      client.userID!,
    );
    if (mounted) {
      setState(() {
        _localDisplayName = profile?.displayName ?? client.userID!;
        _localAvatar = profile?.avatarUrl;
      });
    }
  }

  bool _screenShareActive = false;

  Future<void> _startFgTaskIfNeeded() async {
    if (!PlatformInfos.isAndroid) return;
    final client = Matrix.of(context).client;
    final room = client.getRoomById(widget.roomId);
    await ForegroundTaskManager.startLivekitCall(
      context,
      room: room,
      startCallback: startCallback,
      taskDataCallback: onDataReceived,
    );
  }

  void onDataReceived(Object data) async {
    final lp = _room?.localParticipant;
    if (lp == null) return;

    if (data == 'mute') {
      await lp.setMicrophoneEnabled(!lp.isMicrophoneEnabled());
    } else if (data == 'hangup') {
      _hangup();
    }
  }

  Future<void> _toggleScreenShare() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;

    if (_screenShareActive) {
      await lp.setScreenShareEnabled(false);
      setState(() => _screenShareActive = false);
      return;
    }

    try {
      if (PlatformInfos.isAndroid) {
        final source = await rtc.mediaDevices.getDisplayMedia({
          'video': true,
          'audio': true,
        });

        await lp.setScreenShareEnabled(
          true,
          // captureScreenAudio: true,
          screenShareCaptureOptions: lk.ScreenShareCaptureOptions(
            // captureScreenAudio: true,
            maxFrameRate: 30,
            sourceId: source.id,
          ),
        );
      } else {
        final sources = await rtc.desktopCapturer.getSources(
          types: [rtc.SourceType.Screen],
        );

        if (sources.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(L10n.of(context).noScreensAvailable)),
            );
          }
          return;
        }

        await lp.setScreenShareEnabled(
          true,
          // captureScreenAudio: true,
          screenShareCaptureOptions: lk.ScreenShareCaptureOptions(
            // captureScreenAudio: true,
            maxFrameRate: 30,
            sourceId: sources.first.id,
          ),
        );
      }
      setState(() => _screenShareActive = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              L10n.of(context).screenShareErrorWithMessage(e.toString()),
            ),
          ),
        );
      }
    }
  }

  Future<void> _onCallEncryptionKeys(CallKeysEvent event) async {
    final callKeys = event.callKeysContent;
    final keyProvider = _keyProvider;
    if (keyProvider == null) {
      ErrorReporter(
        null,
        'Received a new key but the keyProvider is not ready yet!',
      ).onErrorCallback(Exception(), StackTrace.current);
      return;
    }

    final identity = '${event.sender}:${callKeys.member.claimedDeviceId}';
    final index = callKeys.keys.index;

    // Drop out-of-order keys: applying an older key after a newer one would
    // regress the latest known index and break decryption.
    if (index < (_latestRemoteKeyIndex[identity] ?? -1)) {
      Logs().d('DEBUG: dropping out of order call key from $identity');
      return;
    }
    _latestRemoteKeyIndex[identity] = index;

    await keyProvider.setRawKey(
      base64Decode(callKeys.keys.key),
      participantId: identity,
      keyIndex: index,
    );

    // Setting a key on the key provider only stores the key material. Frame
    // cryptors that were already created for this participant (their tracks
    // were subscribed before the key arrived) stay pinned at their old key
    // index and would never decrypt. Re-apply the latest index so they pick
    // up the newly available key immediately.
    try {
      await _room?.e2eeManager?.setKeyIndex(
        index,
        participantIdentity: identity,
      );
    } catch (e) {
      Logs().d('DEBUG: failed to resync e2ee cryptors for $identity: $e');
    }
  }

  /// Generates/shares our E2EE key. [roomOverride] must be passed when this
  /// is called during [_connect] where [_room] is not yet assigned.
  Future<void> _createKeyAndShare([lk.Room? roomOverride]) async {
    final liveKitRoom = roomOverride ?? _room;
    final client = _client;
    if (liveKitRoom == null || client == null) return;
    final matrixRoom = client.getRoomById(widget.roomId);
    if (matrixRoom == null) return;

    final ownMemberId = '${client.userID}:${client.deviceID}';

    final currentParticipants =
        matrixRoom
            .getActiveMatrixRtcMembers()
            .map((member) => member.membershipId)
            .whereType<String>()
            .toSet()
          ..remove(ownMemberId);

    if (setEquals(currentParticipants, _lastSharedParticipants) &&
        currentParticipants.isNotEmpty) {
      Logs().d(
        'Participant list has not changed. No need to share keys again!',
      );
      return;
    }

    var index = liveKitRoom.roomOptions.encryption!.keyProvider.getLatestIndex(
      ownMemberId,
    );

    final keyCreatedAt = _keyCreatedAt;
    final canJustForwardToNewUsers =
        keyCreatedAt != null &&
        DateTime.now().difference(keyCreatedAt).inSeconds < 15 &&
        _lastSharedParticipants.difference(currentParticipants).isEmpty;

    late final Uint8List key;
    if (_lastKey == null || !canJustForwardToNewUsers) {
      // Key generation
      final rng = Random.secure();
      key = Uint8List(16);
      key.setAll(0, Iterable.generate(key.length, (i) => rng.nextInt(256)));
      if (_lastKey != null) index = (index + 1) % 256;

      await liveKitRoom.roomOptions.encryption!.keyProvider.setRawKey(
        key,
        keyIndex: index,
        participantId: ownMemberId,
      );
      _keyCreatedAt = DateTime.now();
      _lastKey = key;
      if (_lastKey != null) {
        await liveKitRoom.e2eeManager?.setKeyIndex(
          index,
          participantIdentity: ownMemberId,
        );
      }
    } else {
      key = _lastKey!;
    }

    final forwardParticipants = canJustForwardToNewUsers
        ? currentParticipants.difference(_lastSharedParticipants)
        : currentParticipants;
    final deviceKeys = <DeviceKeys>[];
    for (final membershipId in forwardParticipants) {
      final membershipParts = membershipId.split(':');
      final deviceId = membershipParts.removeLast();
      final userId = membershipParts.join(':');
      final keys = client.userDeviceKeys[userId]?.deviceKeys[deviceId];
      if (keys == null) {
        Logs().w('No device keys found for $membershipId');
        continue;
      }
      deviceKeys.add(keys);
    }

    _lastSharedParticipants = currentParticipants;
    await matrixRoom.shareMatrixRtcCallKey(
      key: key,
      index: index,
      memberId: ownMemberId,
      deviceKeys: deviceKeys,
    );
  }

  Future<void> _publishCallMember({bool notify = true}) async {
    final client = _client;
    final matrixRoom = client?.getRoomById(widget.roomId);

    if (client == null || matrixRoom == null) return;

    final deviceId = client.deviceID ?? '';
    final callStateKey = widget.callStateKey;

    if (callStateKey == null) return;

    try {
      final membershipID = '${client.userID!}:$deviceId';

      final memberEventContent = {
        'application': 'm.call',
        'call_id': '',
        'device_id': deviceId,
        'expires': 14400000,
        'foci_preferred': widget.liveKitServiceUrls
            .map(
              (u) => {
                'type': 'livekit',
                'livekit_service_url': u,
                'livekit_alias': widget.roomId,
              },
            )
            .toList(),
        'focus_active': {
          'type': 'livekit',
          'focus_selection': 'oldest_membership',
        },
        'm.call.intent': 'video',
        'membershipID': membershipID,
        'scope': 'm.room',
      };

      final memberEventId = await client.setRoomStateWithKey(
        widget.roomId,
        'org.matrix.msc3401.call.member',
        callStateKey,
        memberEventContent,
      );

      if (notify &&
          matrixRoom.callMembersCount <= 1 &&
          matrixRoom.canSendEvent('org.matrix.msc4075.rtc.notification')) {
        await matrixRoom.sendEvent({
          'lifetime': 30000,
          'm.call.intent': 'video',
          'm.mentions': {'room': true, 'user_ids': []},
          'm.relates.to': {
            'event_id': memberEventId,
            'rel_type': 'm.reference',
          },
          'notification_type': 'notification',
          'sender_ts': DateTime.now().millisecondsSinceEpoch,
        }, type: 'org.matrix.msc4075.rtc.notification');
      }
    } catch (e) {
      Logs().d('DEBUG: error sending call member event: $e');
    }
  }

  /// Registers the matrix listeners required for the E2EE key exchange.
  ///
  /// Cancels any previously registered subscriptions first, so this is safe
  /// to call again when re-attaching to a running call (the reuse path of
  /// [initState]).
  void _registerMatrixListeners(Client client) {
    _onCallEncryptionKeysSub?.cancel();
    _onCallMembersChanged?.cancel();
    _onCallEncryptionKeysSub = client.onCallEncryptionKeys.listen(
      _onCallEncryptionKeys,
    );

    _onCallMembersChanged = client.onSync.stream
        .where(
          (syncUpdate) =>
              syncUpdate.rooms?.join?[widget.roomId]?.timeline?.events?.any(
                (event) => event.type == MatrixRtcCallMember.eventType,
              ) ??
              false,
        )
        .listen((_) => _createKeyAndShare());
  }

  Future<void> _connect() async {
    try {
      await _startFgTaskIfNeeded();
      final client = Matrix.of(context).client;
      _client = client;
      final matrixRoom = client.getRoomById(widget.roomId);
      final profile = matrixRoom?.unsafeGetUserFromMemoryOrFallback(
        client.userID!,
      );
      _localDisplayName = profile?.displayName ?? client.userID!;
      _localAvatar = profile?.avatarUrl;
      final openId = await client.requestOpenIdToken(client.userID!, {});
      final deviceId = client.deviceID ?? '';

      await lk.LiveKitClient.initialize();

      LiveKitCredentials? creds;
      lk.Room? room;

      final keyProviderOptions = rtc.KeyProviderOptions(
        sharedKey: false,
        ratchetSalt: Uint8List.fromList('LKFrameEncryptionKey'.codeUnits),
        // Must be > 0 so decryption can self-heal via ratcheting when the
        // remote side rotates to a key index we have not applied yet.
        // (Element Call uses 10, the livekit default is 16.)
        ratchetWindowSize: 16,
        discardFrameWhenCryptorNotReady: true,
        keyDerivationAlgorithm: rtc.KeyDerivationAlgorithm.kHKDF,
      );
      final nativeKeyProvider = await rtc.frameCryptorFactory
          .createDefaultKeyProvider(keyProviderOptions);
      final baseKeyProvider = _keyProvider = lk.BaseKeyProvider(
        nativeKeyProvider,
        keyProviderOptions,
      );

      _registerMatrixListeners(client);

      final ownMemberId = '${client.userID}:${client.deviceID}';
      final otherActiveMembers = matrixRoom
          ?.getActiveMatrixRtcMembers()
          .where((m) => m.membershipId != null && m.membershipId != ownMemberId)
          .toList();
      Logs().d(
        'DEBUG: livekit service url candidates: ${widget.liveKitServiceUrls}, '
        'other active members: ${otherActiveMembers?.length ?? 0}',
      );

      var membershipPublished = false;
      Future<void> rollbackMembership() async {
        if (!membershipPublished || widget.callStateKey == null) return;
        try {
          await client.setRoomStateWithKey(
            widget.roomId,
            'org.matrix.msc3401.call.member',
            widget.callStateKey!,
            {},
          );
        } catch (_) {}
        membershipPublished = false;
      }

      for (var i = 0; i < widget.liveKitServiceUrls.length; i++) {
        final jwtServiceUrl = widget.liveKitServiceUrls[i];
        final hasNextUrl = i < widget.liveKitServiceUrls.length - 1;
        try {
          creds = await LiveKitService.getCredentials(
            openId: openId,
            roomId: widget.roomId,
            deviceId: deviceId,
            jwtServiceUrl: jwtServiceUrl,
          );
          Logs().d('LiveKit OK: $jwtServiceUrl → ${creds.url}');

          room = lk.Room(
            roomOptions: lk.RoomOptions(
              adaptiveStream: true,
              dynacast: true,
              defaultAudioCaptureOptions: lk.AudioCaptureOptions(
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
                highPassFilter: true,
              ),
              encryption: lk.E2EEOptions(keyProvider: baseKeyProvider),
            ),
          );

          // Publish our membership and share our encryption key BEFORE
          // connecting to the LiveKit room. This mirrors Element Call's join
          // order: existing members start pushing their E2EE keys as soon as
          // they see our membership, while we are subscribing to their tracks.
          // Connecting first would subscribe to already-published tracks and
          // create receiver frame cryptors before any key material exists,
          // leaving them pinned at key index 0 with no way to recover once
          // the peer rotates to a higher index.
          await _publishCallMember();
          membershipPublished = true;
          await _createKeyAndShare(room);

          await room.connect(creds.url, creds.jwt);
          Logs().d('LiveKit connected: $jwtServiceUrl');

          // Sanity check: if the LiveKit room is empty while other members
          // are active in the Matrix call, we most likely ended up on a
          // different LiveKit instance than they did (e.g. a stale foci URL).
          // Fail over to the next candidate URL instead of sitting in an
          // empty room forever.
          if (room.remoteParticipants.isEmpty &&
              (otherActiveMembers?.isNotEmpty ?? false) &&
              hasNextUrl) {
            Logs().w(
              'LiveKit room is empty but ${otherActiveMembers!.length} member(s) '
              'are in the call - wrong instance? Trying next service URL...',
            );
            await rollbackMembership();
            try {
              await room.dispose();
            } catch (_) {}
            room = null;
            creds = null;
            continue;
          }
          break;
        } catch (e) {
          Logs().d('LiveKit FAIL: $jwtServiceUrl → $e');
          await rollbackMembership();
          try {
            await room?.dispose();
          } catch (_) {}
          room = null;
          creds = null;
        }
      }

      if (room == null) {
        throw Exception(L10n.of(context).allLiveKitUnavailable);
      }

      // Keep our own membership alive: it is published with a fixed expiry,
      // and unlike Element Call's membership manager nothing refreshes it.
      _startMembershipRefreshTimer();

      _room = room;
      LiveKitCallManager().room = room;
      LiveKitCallManager().callStateKey = widget.callStateKey;
      LiveKitCallManager().client = _client;

      _setupRoomListeners();

      Logs().d(
        'DEBUG: connected, remote participants: ${_room!.remoteParticipants.length}',
      );

      await _room!.localParticipant?.setCameraEnabled(
        false,
        cameraCaptureOptions: const lk.CameraCaptureOptions(
          maxFrameRate: 30,
          params: lk.VideoParametersPresets.h720_169,
        ),
      );
      await _room!.localParticipant?.setMicrophoneEnabled(
        false,
        audioCaptureOptions: const lk.AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          highPassFilter: true,
          typingNoiseDetection: true,
        ),
      );

      if (mounted && !_disposed) {
        setState(() => _connecting = false);
      }
    } catch (e) {
      Logs().d('LiveKit connect error: $e');
      if (mounted && !_disposed) {
        setState(() {
          _error = e.toString();
          _connecting = false;
        });
      }
    }
  }

  void _setupRoomListeners() {
    _room!.addListener(_onRoomUpdate);

    _room!.events.on<lk.ParticipantConnectedEvent>((event) {
      Logs().d('DEBUG: participant connected: ${event.participant.identity}');
      if (mounted) setState(() {});
    });
    _room!.events.on<lk.ParticipantDisconnectedEvent>((event) {
      Logs().d(
        'DEBUG: participant disconnected: ${event.participant.identity}',
      );
      if (mounted) setState(() {});
    });
    _room!.events.on<lk.TrackSubscribedEvent>((event) {
      Logs().d(
        'DEBUG: track subscribed: ${event.participant.identity} ${event.track.source}',
      );
      if (mounted) setState(() {});
    });
    _room!.events.on<lk.TrackUnsubscribedEvent>((event) {
      if (mounted) setState(() {});
    });
    _room!.events.on<lk.TrackPublishedEvent>((event) {
      if (mounted) setState(() {});
    });
    _room!.events.on<lk.LocalTrackPublishedEvent>((event) {
      if (mounted) setState(() {});
    });
    // Self-healing for E2EE: if a receiver frame cryptor is stuck without a
    // key (e.g. the track was subscribed before the remote key arrived), or
    // failed to decrypt, re-apply the latest known key index for that
    // participant so decryption can resume.
    _room!.events.on<lk.TrackE2EEStateEvent>((event) {
      final state = event.state;
      if (state == lk.E2EEState.kMissingKey ||
          state == lk.E2EEState.kDecryptionFailed ||
          state == lk.E2EEState.kInternalError) {
        final userId = _client?.userID;
        final deviceId = _client?.deviceID;
        final ownIdentity = userId != null && deviceId != null
            ? '$userId:$deviceId'
            : null;
        if (ownIdentity != null && event.participant.identity == ownIdentity) {
          return;
        }
        _resyncRemoteE2ee(event.participant.identity);
      }
    });
  }

  /// Re-applies the latest known remote encryption key index for [identity]
  /// to its existing frame cryptors.
  ///
  /// Setting a key on the [lk.BaseKeyProvider] only stores the material;
  /// already-created cryptors keep using their configured index. Without
  /// this, tracks subscribed before the key arrived stay undecryptable.
  Future<void> _resyncRemoteE2ee(String identity) async {
    final room = _room;
    final keyProvider = _keyProvider;
    if (room == null || keyProvider == null) return;
    final index = keyProvider.getLatestIndex(identity);
    Logs().d('DEBUG: resyncing e2ee cryptor index for $identity -> $index');
    try {
      await room.e2eeManager?.setKeyIndex(index, participantIdentity: identity);
    } catch (e) {
      Logs().d('DEBUG: e2ee resync failed for $identity: $e');
    }
  }

  /// Periodically republishes our call member state event so it does not
  /// expire while we are still in the call. Other clients treat expired
  /// memberships as left, which stops E2EE key delivery towards us.
  void _startMembershipRefreshTimer() {
    _membershipRefreshTimer?.cancel();
    _membershipRefreshTimer = Timer.periodic(_membershipRefreshInterval, (_) {
      if (!_disposed) _publishCallMember(notify: false);
    });
  }

  void _onRoomUpdate() {
    if (!mounted || _disposed) return;
    if (_room?.connectionState == lk.ConnectionState.disconnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposed) _hangup();
      });
      return;
    }
    if (mounted) setState(() {});
  }

  void _hangup() {
    if (_disposed) return;
    _disposed = true;
    final room = _room;
    _room = null;
    final client = _client ?? LiveKitCallManager().client;
    final stateKey = widget.callStateKey ?? LiveKitCallManager().callStateKey;
    LiveKitCallManager().endCall();
    _cleanupCall(room, client, stateKey);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _cleanupCall(
    lk.Room? room,
    Client? client,
    String? stateKey,
  ) async {
    _membershipRefreshTimer?.cancel();
    _membershipRefreshTimer = null;
    try {
      await room?.localParticipant?.setCameraEnabled(false);
    } catch (_) {}
    try {
      await room?.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    try {
      await room?.localParticipant?.setScreenShareEnabled(false);
    } catch (_) {}
    try {
      await room?.disconnect();
    } catch (_) {}
    try {
      await room?.dispose();
    } catch (_) {}
    try {
      await ForegroundTaskManager.stopTask(taskType: .livekitCall);
    } catch (_) {}

    try {
      if (client != null && stateKey != null) {
        try {
          await client.setRoomStateWithKey(
            widget.roomId,
            'org.matrix.msc3401.call.member',
            stateKey,
            {},
          );
        } catch (ex) {
          Logs().e("Failed to send call member state event.", ex);
        }
      }
    } catch (e) {
      Logs().d('DEBUG: error removing call member state: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _membershipRefreshTimer?.cancel();
    _onCallEncryptionKeysSub?.cancel();
    _onCallMembersChanged?.cancel();
    _room?.removeListener(_onRoomUpdate);
    ForegroundTaskManager.stopTask(taskType: .livekitCall);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
      ),
      body: _connecting
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    L10n.of(context).connectingToCall,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.error,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      L10n.of(context).errorWithMessage(_error!),
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _hangup,
                      child: Text(L10n.of(context).close),
                    ),
                  ],
                ),
              ),
            )
          : _buildCallUI(),
    );
  }

  Widget _buildCallUI() {
    final theme = Theme.of(context);
    final participants = _room?.remoteParticipants.values.toList() ?? [];

    final screenShares = <lk.RemoteParticipant>[];
    final regularParticipants = <lk.RemoteParticipant>[];
    for (final p in participants) {
      final hasScreenShare = p.videoTrackPublications.any(
        (pub) => pub.isScreenShare && pub.subscribed,
      );
      if (hasScreenShare) {
        screenShares.add(p);
      } else {
        regularParticipants.add(p);
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: screenShares.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 150.0),
                  child: _ScreenShareView(participant: screenShares.first),
                )
              : regularParticipants.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        L10n.of(context).waitingForParticipants,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                )
              : regularParticipants.length == 1
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 150),
                  child: _ParticipantView(regularParticipants.first),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 150),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: regularParticipants.length > 4 ? 3 : 2,
                    childAspectRatio: regularParticipants.length > 4
                        ? 1.0
                        : 0.8,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: regularParticipants.length,
                  itemBuilder: (context, index) =>
                      _ParticipantView(regularParticipants[index]),
                ),
        ),
        Positioned(
          right: 16,
          bottom: 130, // Increased bottom margin to prevent intersection
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_screenShareActive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _LocalScreenShareView(
                      localParticipant: _room?.localParticipant,
                    ),
                  ),
                _LocalVideoView(
                  localParticipant: _room?.localParticipant,
                  displayName: _localDisplayName,
                  avatar: _localAvatar,
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _CallControls(
            room: _room,
            onHangup: _hangup,
            onScreenShare: _toggleScreenShare,
            screenShareActive: _screenShareActive,
          ),
        ),
      ],
    );
  }
}

class _ScreenShareView extends StatefulWidget {
  final lk.RemoteParticipant participant;
  const _ScreenShareView({required this.participant});

  @override
  State<_ScreenShareView> createState() => _ScreenShareViewState();
}

class _ScreenShareViewState extends State<_ScreenShareView> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    widget.participant.addListener(_onChange);
    _startPolling();
  }

  @override
  void didUpdateWidget(_ScreenShareView oldWidget) {
    oldWidget.participant.removeListener(_onChange);
    widget.participant.addListener(_onChange);
    _startPolling();
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    widget.participant.removeListener(_onChange);
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    Future.delayed(const Duration(seconds: 5), () {
      _pollTimer?.cancel();
    });
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.participant;
    final screenSharePub = p.videoTrackPublications.firstWhere(
      (pub) => pub.isScreenShare && pub.subscribed,
      orElse: () => p.videoTrackPublications.first,
    );
    final videoTrack = screenSharePub.track;

    return Stack(
      children: [
        if (videoTrack != null)
          Center(child: lk.VideoTrackRenderer(videoTrack, fit: .contain))
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.screen_share,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.of(context).isScreenSharing(_shortId(p.identity)),
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: p.isSpeaking
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.onPrimaryContainer,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _shortId(p.identity),
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _shortId(String identity) {
    final at = identity.indexOf(':');
    return at > 0 ? identity.substring(1, at).toLowerCase() : identity;
  }
}

class _ParticipantView extends StatefulWidget {
  final lk.RemoteParticipant participant;
  const _ParticipantView(this.participant);

  @override
  State<_ParticipantView> createState() => _ParticipantViewState();
}

class _ParticipantViewState extends State<_ParticipantView> {
  @override
  void initState() {
    super.initState();
    widget.participant.addListener(_onChange);
  }

  @override
  void didUpdateWidget(_ParticipantView oldWidget) {
    oldWidget.participant.removeListener(_onChange);
    widget.participant.addListener(_onChange);
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.participant;
    final videoPub = p.videoTrackPublications
        .where((pub) => !pub.isScreenShare && pub.subscribed)
        .firstOrNull;
    final videoTrack = (videoPub != null && !videoPub.muted)
        ? videoPub.track
        : null;
    final speaking = p.isSpeaking;
    final micPub = p.audioTrackPublications.firstOrNull;
    final micMuted = micPub?.muted ?? true;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: speaking ? theme.colorScheme.tertiary : Colors.transparent,
          width: speaking ? 3 : 0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoTrack != null)
            lk.VideoTrackRenderer(videoTrack, fit: lk.VideoViewFit.contain)
          else
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.person,
                  size: 40,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Row(
              children: [
                if (micMuted)
                  _statusBadge(Icons.mic_off, theme.colorScheme.error),
                if (!micMuted && speaking)
                  _statusBadge(Icons.mic, theme.colorScheme.tertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _shortId(p.identity),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 2,
                          offset: Offset(1, 1),
                        ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 16),
    );
  }

  String _shortId(String identity) {
    final at = identity.indexOf(':');
    return at > 0 ? identity.substring(1, at).toLowerCase() : identity;
  }
}

class _LocalVideoView extends StatelessWidget {
  final lk.LocalParticipant? localParticipant;
  final String displayName;
  final Uri? avatar;

  const _LocalVideoView({
    this.localParticipant,
    required this.displayName,
    this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lp = localParticipant;
    if (lp == null) return const SizedBox.shrink();
    final videoPub = lp.videoTrackPublications
        .where((pub) => !pub.isScreenShare)
        .firstOrNull;
    final videoTrack = (videoPub != null && !videoPub.muted)
        ? videoPub.track
        : null;
    final speaking = lp.isSpeaking;
    final micPub = lp.audioTrackPublications.firstOrNull;
    final micMuted = micPub?.muted ?? true;

    return Container(
      width: 110,
      height: 150,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: speaking
              ? theme.colorScheme.tertiary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: speaking ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (videoTrack != null)
            lk.VideoTrackRenderer(videoTrack, fit: .contain)
          else
            Center(
              child: Avatar(mxContent: avatar, name: displayName, size: 48),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 4,
            left: 4,
            right: 4,
            child: Row(
              children: [
                if (micMuted)
                  _statusBadge(Icons.mic_off, theme.colorScheme.error),
                if (!micMuted && speaking)
                  _statusBadge(Icons.mic, theme.colorScheme.tertiary),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 2),
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: Colors.black45,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 12),
    );
  }
}

class _LocalScreenShareView extends StatelessWidget {
  final lk.LocalParticipant? localParticipant;
  const _LocalScreenShareView({this.localParticipant});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lp = localParticipant;
    if (lp == null) return const SizedBox.shrink();
    final screenSharePub = lp.videoTrackPublications
        .where((pub) => pub.isScreenShare)
        .firstOrNull;
    final screenShareTrack = screenSharePub?.track;
    if (screenShareTrack == null) return const SizedBox.shrink();

    return Container(
      width: 110,
      height: 150,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.tertiary, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          lk.VideoTrackRenderer(screenShareTrack, fit: .contain),
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.screen_share,
                    color: theme.colorScheme.tertiary,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    L10n.of(context).screenShare,
                    style: TextStyle(
                      color: theme.colorScheme.tertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  final lk.Room? room;
  final VoidCallback onHangup;
  final VoidCallback onScreenShare;
  final bool screenShareActive;
  const _CallControls({
    this.room,
    required this.onHangup,
    required this.onScreenShare,
    this.screenShareActive = false,
  });

  Widget _buildCallButton(
    BuildContext context,
    IconData icon,
    String label,
    bool enabled,
    void Function() onPressed,
  ) {
    final theme = Theme.of(context);

    if (!FluffyThemes.isColumnMode(context)) {
      return IconButton.filledTonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: enabled
              ? theme.colorScheme.secondaryContainer
              : Colors.transparent,
          foregroundColor: enabled
              ? theme.colorScheme.onSecondaryContainer
              : theme.colorScheme.onSurface,
        ),
        icon: Icon(icon),
      );
    }

    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: enabled
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        foregroundColor: enabled
            ? theme.colorScheme.onSecondaryContainer
            : theme.colorScheme.onSurface,
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 12,
        children: [Icon(icon), Text(label)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lp = room?.localParticipant;
    final micOn = _isMicOn(lp);
    final camOn = _isCamOn(lp);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const .all(16),
        child: Align(
          alignment: .center,
          child: Row(
            mainAxisSize: .min,
            spacing: 12,
            children: [
              Container(
                padding: const .symmetric(vertical: 8, horizontal: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  spacing: 8,
                  children: [
                    _buildCallButton(
                      context,
                      camOn ? Icons.videocam : Icons.videocam_off,
                      L10n.of(context).callVideocam,
                      camOn,
                      () {
                        final manager = LiveKitCallManager();
                        lp?.setCameraEnabled(
                          !camOn,
                          cameraCaptureOptions: lk.CameraCaptureOptions(
                            deviceId: manager.selectedVideoInput,
                            maxFrameRate: 30,
                            params: lk.VideoParametersPresets.h720_169,
                          ),
                        );
                      },
                    ),
                    _buildCallButton(
                      context,
                      micOn ? Icons.mic : Icons.mic_off,
                      L10n.of(context).callMic,
                      micOn,
                      () {
                        final manager = LiveKitCallManager();
                        lp?.setMicrophoneEnabled(
                          !micOn,
                          audioCaptureOptions: lk.AudioCaptureOptions(
                            deviceId: manager.selectedAudioInput,
                            echoCancellation: manager.echoCancellation,
                            noiseSuppression: manager.noiseSuppression,
                            autoGainControl: manager.autoGainControl,
                            highPassFilter: true,
                            typingNoiseDetection: true,
                          ),
                        );
                      },
                    ),
                    _buildCallButton(
                      context,
                      screenShareActive
                          ? Icons.screen_share
                          : Icons.screen_share_outlined,
                      L10n.of(context).callScreenShare,
                      screenShareActive,
                      onScreenShare,
                    ),
                    _buildCallButton(
                      context,
                      Icons.settings,
                      L10n.of(context).lkCallSettings,
                      false,
                      () => _showSettingsSheet(context, room),
                    ),
                  ],
                ),
              ),

              FloatingActionButton(
                onPressed: onHangup,
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                child: Icon(Icons.call_end_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showSettingsSheet(BuildContext context, lk.Room? room) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CallSettingsSheet(room: room),
    );
  }

  bool _isMicOn(lk.LocalParticipant? lp) {
    if (lp == null) return false;
    final pub = lp.audioTrackPublications.firstOrNull;
    return pub != null && !pub.muted;
  }

  bool _isCamOn(lk.LocalParticipant? lp) {
    if (lp == null) return false;
    final pub = lp.videoTrackPublications
        .where((p) => !p.isScreenShare)
        .firstOrNull;
    return pub != null && !pub.muted;
  }
}

Future<void> openLiveKitCall(BuildContext context, String roomId) async {
  final manager = LiveKitCallManager();

  // Check if we are already in THIS call. If so, just push the UI, don't send Matrix state events.
  if (manager.isInCall && manager.currentRoomId == roomId) {
    if (context.mounted) {
      final route = MaterialPageRoute(
        builder: (_) => LiveKitCallScreen(
          roomId: roomId,
          liveKitServiceUrls: const [],
          callStateKey: manager.callStateKey,
        ),
      );
      manager.startCall(roomId, route);
      Navigator.of(context).push(route);
    }
    return;
  }

  // If in a DIFFERENT call, we ideally should prompt or end it, but for now we'll just try to let the new call replace it.
  // The old call will disconnect when the user hangs it up, or if LiveKitClient manages one room at a time, it might fail or replace.
  // But to avoid leaking, let's at least clean up the manager.
  if (manager.isInCall && manager.currentRoomId != roomId) {
    try {
      await manager.room?.localParticipant?.setCameraEnabled(false);
      await manager.room?.localParticipant?.setMicrophoneEnabled(false);
      await manager.room?.localParticipant?.setScreenShareEnabled(false);
      await manager.room?.disconnect();
      await manager.room?.dispose();
    } catch (_) {}
    manager.endCall();
  }

  final client = Matrix.of(context).client;
  final room = client.getRoomById(roomId);
  if (room == null) return;

  final deviceId = client.deviceID ?? '';
  final userId = client.userID!;
  final ownMemberId = '$userId:$deviceId';

  final urls = <String>{};

  // Prefer the LiveKit instances that the currently ACTIVE members are
  // actually using. getActiveMatrixRtcMembers() expiry-filters the member
  // state events; without this, a leftover membership from a crashed
  // previous session could send us to a different (empty) LiveKit
  // instance where nobody can see us.
  for (final member in room.getActiveMatrixRtcMembers()) {
    final membershipId = member.membershipId;
    if (membershipId == null || membershipId == ownMemberId) continue;
    for (final focus in member.fociPreferred) {
      if (focus.type == 'livekit' && focus.livekitServiceUrl.isNotEmpty) {
        urls.add(focus.livekitServiceUrl);
      }
    }
  }

  // Fall back to our homeserver's advertised instance.
  try {
    final wellKnown = await client.getWellknown();
    final rtcFoci =
        wellKnown.additionalProperties['org.matrix.msc4143.rtc_foci'];
    if (rtcFoci is List) {
      for (final f in rtcFoci) {
        if (f is Map && f['type'] == 'livekit') {
          final url = f['livekit_service_url'] as String?;
          if (url != null) urls.add(url);
        }
      }
    }
  } catch (_) {}

  // Last resort: scan ALL raw member state events (including expired or
  // unparsable ones). These may be stale, so they must come last.
  final callMembers = room.states['org.matrix.msc3401.call.member'];
  if (callMembers != null && callMembers.isNotEmpty) {
    for (final entry in callMembers.entries) {
      final content = entry.value.content;
      if (content.isEmpty) continue;
      final fociPreferred = content['foci_preferred'] as List?;
      for (final f in fociPreferred ?? []) {
        final fMap = f as Map?;
        if (fMap?['type'] == 'livekit') {
          final url = fMap!['livekit_service_url'] as String?;
          if (url != null) urls.add(url);
        }
      }
      final focusActive = content['focus_active'] as Map?;
      if (focusActive?['type'] == 'livekit') {
        final url = focusActive!['livekit_service_url'] as String?;
        if (url != null) urls.add(url);
      }
    }
  }

  try {
    if (urls.isEmpty) {
      final wellKnown = await client.getWellknown();
      final homeserverUrl = wellKnown.mHomeserver.baseUrl.toString().replaceAll(
        RegExp(r'/+$'),
        '',
      );
      urls.add('$homeserverUrl/livekit-jwt-service');
    }
  } catch (_) {}

  if (urls.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).couldNotFindCallServer)),
      );
    }
    return;
  }

  final stateKey = '_${userId}_${deviceId}_m.call';

  if (context.mounted) {
    final route = MaterialPageRoute(
      builder: (_) => LiveKitCallScreen(
        roomId: roomId,
        liveKitServiceUrls: urls.toList(),
        callStateKey: stateKey,
      ),
    );
    LiveKitCallManager().startCall(roomId, route);
    Navigator.of(context).push(route);
  }
}

class _CallSettingsSheet extends StatefulWidget {
  final lk.Room? room;
  const _CallSettingsSheet({this.room});

  @override
  State<_CallSettingsSheet> createState() => _CallSettingsSheetState();
}

class _CallSettingsSheetState extends State<_CallSettingsSheet> {
  List<rtc.MediaDeviceInfo> _audioInputs = [];
  List<rtc.MediaDeviceInfo> _audioOutputs = [];
  List<rtc.MediaDeviceInfo> _videoInputs = [];

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final devices = await rtc.navigator.mediaDevices.enumerateDevices();
    setState(() {
      _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
      _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
      _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();
    });
  }

  Future<void> _switchAudioInput(rtc.MediaDeviceInfo device) async {
    final manager = LiveKitCallManager();
    setState(() => manager.selectedAudioInput = device.deviceId);
    final lp = widget.room?.localParticipant;
    if (lp == null) return;

    final audioTrack = lp.audioTrackPublications.firstOrNull?.track;
    if (audioTrack is lk.LocalAudioTrack) {
      final options = audioTrack.currentOptions;
      await audioTrack.restartTrack(
        options.copyWith(deviceId: device.deviceId),
      );
    }
  }

  Future<void> _switchAudioOutput(rtc.MediaDeviceInfo device) async {
    final manager = LiveKitCallManager();
    setState(() => manager.selectedAudioOutput = device.deviceId);
    await rtc.Helper.selectAudioOutput(device.deviceId);
  }

  Future<void> _switchVideoInput(rtc.MediaDeviceInfo device) async {
    final manager = LiveKitCallManager();
    setState(() => manager.selectedVideoInput = device.deviceId);
    final lp = widget.room?.localParticipant;
    if (lp == null) return;

    final videoTrack = lp.videoTrackPublications
        .where((p) => !p.isScreenShare)
        .firstOrNull
        ?.track;
    if (videoTrack is lk.LocalVideoTrack) {
      await videoTrack.restartTrack(
        lk.CameraCaptureOptions(
          deviceId: device.deviceId,
          maxFrameRate: 30,
          params: lk.VideoParametersPresets.h720_169,
        ),
      );
    }
  }

  Future<void> _updateAudioSettings() async {
    final lp = widget.room?.localParticipant;
    if (lp == null) return;

    final manager = LiveKitCallManager();
    final audioTrack = lp.audioTrackPublications.firstOrNull?.track;
    if (audioTrack is lk.LocalAudioTrack) {
      final options = audioTrack.currentOptions;
      await audioTrack.restartTrack(
        options.copyWith(
          echoCancellation: manager.echoCancellation,
          noiseSuppression: manager.noiseSuppression,
          autoGainControl: manager.autoGainControl,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = LiveKitCallManager();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              L10n.of(context).callSettings,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            if (_audioInputs.isNotEmpty) ...[
              _sectionTitle(L10n.of(context).microphone),
              const SizedBox(height: 8),
              ..._audioInputs.map(
                (d) => _deviceTile(
                  label: d.label.isEmpty
                      ? L10n.of(
                          context,
                        ).microphoneN(_audioInputs.indexOf(d) + 1)
                      : d.label,
                  selected: manager.selectedAudioInput == d.deviceId,
                  onTap: () => _switchAudioInput(d),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_audioOutputs.isNotEmpty) ...[
              _sectionTitle(L10n.of(context).speaker),
              const SizedBox(height: 8),
              ..._audioOutputs.map(
                (d) => _deviceTile(
                  label: d.label.isEmpty
                      ? L10n.of(context).speakerN(_audioOutputs.indexOf(d) + 1)
                      : d.label,
                  selected: manager.selectedAudioOutput == d.deviceId,
                  onTap: () => _switchAudioOutput(d),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_videoInputs.isNotEmpty) ...[
              _sectionTitle(L10n.of(context).camera),
              const SizedBox(height: 8),
              ..._videoInputs.map(
                (d) => _deviceTile(
                  label: d.label.isEmpty
                      ? L10n.of(context).cameraN(_videoInputs.indexOf(d) + 1)
                      : d.label,
                  selected: manager.selectedVideoInput == d.deviceId,
                  onTap: () => _switchVideoInput(d),
                ),
              ),
              const SizedBox(height: 16),
            ],
            _sectionTitle(L10n.of(context).audioProcessing),
            const SizedBox(height: 8),
            _switchTile(
              title: L10n.of(context).echoCancellation,
              value: manager.echoCancellation,
              onChanged: (v) {
                setState(() => manager.echoCancellation = v);
                _updateAudioSettings();
              },
            ),
            _switchTile(
              title: L10n.of(context).noiseSuppression,
              value: manager.noiseSuppression,
              onChanged: (v) {
                setState(() => manager.noiseSuppression = v);
                _updateAudioSettings();
              },
            ),
            _switchTile(
              title: L10n.of(context).autoGainControl,
              value: manager.autoGainControl,
              onChanged: (v) {
                setState(() => manager.autoGainControl = v);
                _updateAudioSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: TextStyle(
        color: theme.colorScheme.secondary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _deviceTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
      title: Text(label),
      onTap: onTap,
    );
  }

  Widget _switchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}
