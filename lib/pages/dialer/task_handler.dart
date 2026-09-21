import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Entry point for the background isolate used by the Android foreground
/// service (LiveKit calls and file uploads).
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(DialerTaskHandler());
}

class DialerTaskHandler extends TaskHandler {
  @override
  void onNotificationButtonPressed(String id) {
    FlutterForegroundTask.sendDataToMain(id);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
}
