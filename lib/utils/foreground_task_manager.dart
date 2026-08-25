import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:matrix/matrix.dart';

enum ForegroundTaskType { livekitCall, fileUpload }

class ForegroundTaskManager {
  static final List<void Function(Object)> _taskCallbacks = [];
  static ForegroundTaskType? _currentTask;

  static Future<void> _stopFgTaskIfRunning() async {
    if (!PlatformInfos.isAndroid) return;
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> _initTask(BuildContext context) async {
    await ForegroundTaskManager._stopFgTaskIfRunning();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'notification_channel_id',
        channelName: 'Foreground Notification',
        channelDescription: L10n.of(context).foregroundServiceRunning,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );
  }

  static Future<void> startFileUpload(BuildContext context) async {
    if (_currentTask != null) return;
    final l10n = L10n.of(context);

    await _initTask(context);
    await FlutterForegroundTask.startService(
      notificationTitle: l10n.sendingAttachment,
      notificationText: l10n.sendingAttachment,
      serviceTypes: [.dataSync],
      notificationButtons: [],
    );
    _currentTask = .fileUpload;
  }

  static Future<void> startLivekitCall(
    BuildContext context, {
    required Room? room,
    required void Function() startCallback,
    required void Function(Object) taskDataCallback,
  }) async {
    if (_currentTask != null) return;
    await _initTask(context);
    await FlutterForegroundTask.startService(
      notificationTitle: L10n.of(context).ongoingElementCall,
      notificationText: L10n.of(context).ongoingElementCallDetail(
        room?.getLocalizedDisplayname() ?? "Unnamed Room",
      ),
      serviceTypes: [.mediaProjection, .microphone, .camera],
      notificationButtons: [
        NotificationButton(id: 'mute', text: L10n.of(context).muteMic),
        NotificationButton(
          id: 'hangup',
          text: L10n.of(context).hangUp,
          textColor: Colors.red,
        ),
      ],
      callback: startCallback,
    );
    FlutterForegroundTask.addTaskDataCallback(taskDataCallback);
    _taskCallbacks.add(taskDataCallback);
    _currentTask = .livekitCall;
  }

  static Future<void> stopTask({ForegroundTaskType? taskType}) async {
    if (taskType != null && taskType != _currentTask) return;
    await ForegroundTaskManager._stopFgTaskIfRunning();
    for (final callback in _taskCallbacks) {
      FlutterForegroundTask.removeTaskDataCallback(callback);
    }
    _taskCallbacks.clear();
    _currentTask = null;
  }
}
