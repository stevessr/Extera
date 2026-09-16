import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' show Client;

class LiveKitCallManager {
  static final LiveKitCallManager _instance = LiveKitCallManager._internal();
  factory LiveKitCallManager() => _instance;
  LiveKitCallManager._internal();

  String? _currentRoomId;
  final ValueNotifier<String?> currentCallRoomId = ValueNotifier<String?>(null);
  Route? _currentCallRoute;
  bool _disposed = false;

  lk.Room? room;
  String? callStateKey;
  Client? client;

  bool echoCancellation = true;
  bool noiseSuppression = true;
  bool autoGainControl = true;
  String? selectedAudioInput;
  String? selectedAudioOutput;
  String? selectedVideoInput;

  String? get currentRoomId => _currentRoomId;
  Route? get currentCallRoute => _currentCallRoute;

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
    if (!_disposed) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) {
          currentCallRoomId.value = null;
        }
      });
    }
  }

  void markDisposed() {
    _disposed = true;
  }

  bool get isInCall => _currentRoomId != null;
}
