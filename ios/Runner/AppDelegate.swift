import UIKit
import Flutter

private final class PowerSaveModeStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    events(ProcessInfo.processInfo.isLowPowerModeEnabled)

    observer = NotificationCenter.default.addObserver(
      forName: Notification.Name.NSProcessInfoPowerStateDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.eventSink?(ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    if let observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
    return nil
  }

  deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var powerSaveModeMethodChannel: FlutterMethodChannel?
  private var powerSaveModeEventChannel: FlutterEventChannel?
  private var powerSaveModeStreamHandler: PowerSaveModeStreamHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let methodChannel = FlutterMethodChannel(
        name: "xyz.extera.next/power_save_mode",
        binaryMessenger: controller.binaryMessenger
      )
      methodChannel.setMethodCallHandler { call, result in
        if call.method == "isPowerSaveMode" {
          result(ProcessInfo.processInfo.isLowPowerModeEnabled)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      powerSaveModeMethodChannel = methodChannel

      let streamHandler = PowerSaveModeStreamHandler()
      let eventChannel = FlutterEventChannel(
        name: "xyz.extera.next/power_save_mode_changes",
        binaryMessenger: controller.binaryMessenger
      )
      eventChannel.setStreamHandler(streamHandler)
      powerSaveModeStreamHandler = streamHandler
      powerSaveModeEventChannel = eventChannel
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
