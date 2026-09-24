import 'package:flutter/scheduler.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' show Client, Logs, Room;

import 'package:extera_next/utils/foreground_task_manager.dart';
import 'package:extera_next/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';

class LiveKitCallManager {
  static final LiveKitCallManager _instance = LiveKitCallManager._internal();
  factory LiveKitCallManager() => _instance;
  LiveKitCallManager._internal();

  String? _currentRoomId;
  final ValueNotifier<String?> currentCallRoomId = ValueNotifier<String?>(null);
  Route? _currentCallRoute;
  bool _disposed = false;

  lk.Room? _room;
  String? callStateKey;
  Client? client;

  /// True when the microphone is off / muted. Defaults to true because the
  /// call screen publishes the mic disabled on connect.
  final ValueNotifier<bool> micMuted = ValueNotifier<bool>(true);

  /// Number of remote participants currently connected to the LiveKit room.
  final ValueNotifier<int> participantCount = ValueNotifier<int>(0);

  bool echoCancellation = true;
  bool noiseSuppression = true;
  bool autoGainControl = true;
  String? selectedAudioInput;
  String? selectedAudioOutput;
  String? selectedVideoInput;

  String? get currentRoomId => _currentRoomId;
  Route? get currentCallRoute => _currentCallRoute;

  Room? get currentMatrixRoom {
    final id = _currentRoomId;
    final c = client;
    if (id == null || c == null) return null;
    return c.getRoomById(id);
  }

  lk.Room? get room => _room;

  set room(lk.Room? value) {
    _room?.removeListener(_onRoomChanged);
    _room = value;
    if (value != null) {
      value.addListener(_onRoomChanged);
      _updateMicState();
      _updateParticipantCount();
    }
  }

  void _updateMicState() {
    final pub = _room?.localParticipant?.audioTrackPublications.firstOrNull;
    micMuted.value = pub == null || pub.muted;
  }

  void _updateParticipantCount() {
    participantCount.value = _room?.remoteParticipants.length ?? 0;
  }

  void _onRoomChanged() {
    try {
      // The room can be mid-dispose when events fire.
      _updateMicState();
      _updateParticipantCount();
    } catch (_) {}
  }

  void startCall(String roomId, Route route) {
    _disposed = false;
    _currentRoomId = roomId;
    _currentCallRoute = route;
    currentCallRoomId.value = roomId;
  }

  void endCall() {
    _currentRoomId = null;
    _currentCallRoute = null;
    room = null;
    callStateKey = null;
    client = null;
    micMuted.value = true;
    participantCount.value = 0;
    if (!_disposed) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) {
          currentCallRoomId.value = null;
        }
      });
    }
  }

  Future<void> toggleMute() async {
    final lp = _room?.localParticipant;
    if (lp == null) return;
    final pub = lp.audioTrackPublications.firstOrNull;
    final micOn = pub != null && !pub.muted;
    try {
      await lp.setMicrophoneEnabled(
        !micOn,
        audioCaptureOptions: lk.AudioCaptureOptions(
          deviceId: selectedAudioInput,
          echoCancellation: echoCancellation,
          noiseSuppression: noiseSuppression,
          autoGainControl: autoGainControl,
          highPassFilter: true,
          typingNoiseDetection: true,
        ),
      );
    } catch (e) {
      Logs().e('Failed to toggle microphone: $e');
    }
    _updateMicState();
  }

  Future<void> hangup() async {
    final room = _room;
    final client = this.client;
    final stateKey = callStateKey;
    final roomId = _currentRoomId;
    final route = _currentCallRoute;
    endCall();

    if (route?.isActive ?? false) {
      // The call screen is still on the navigator: let its own disconnect
      // detection run its full cleanup and pop the screen. Do not dispose the
      // room here - the screen would read a disposed room.
      try {
        await room?.disconnect();
      } catch (_) {}
      return;
    }

    // Background call with the screen closed: replicate the screen's
    // _cleanupCall sequence.
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
      if (client != null && stateKey != null && roomId != null) {
        final matrixRoom = client.getRoomById(roomId);
        try {
          await matrixRoom?.leaveMatrixRtcCall();
        } catch (ex) {
          Logs().e("Failed to send call member state event.", ex);
        }
      }
    } catch (e) {
      Logs().d('DEBUG: error removing call member state: $e');
    }
  }

  void markDisposed() {
    _disposed = true;
  }

  bool get isInCall => _currentRoomId != null;
}
