import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:extera_next/utils/platform_infos.dart';

/// Tracks the operating system's power-saving state without changing any
/// persisted user preference.
///
/// Android is backed by `PowerManager.isPowerSaveMode`; iOS is backed by
/// `ProcessInfo.isLowPowerModeEnabled`. Other platforms deliberately stay off.
class PowerSaveMode {
  static const _methodChannel = MethodChannel(
    'xyz.extera.next/power_save_mode',
  );
  static const _eventChannel = EventChannel(
    'xyz.extera.next/power_save_mode_changes',
  );

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static StreamSubscription<dynamic>? _subscription;
  static bool _initialized = false;

  static bool get isEnabled => enabled.value;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    if (!PlatformInfos.isAndroid && !PlatformInfos.isIOS) return;
    unawaited(_initializeNativeState());
  }

  static Future<void> _initializeNativeState() async {
    try {
      final initial = await _methodChannel.invokeMethod<bool>(
        'isPowerSaveMode',
      );
      _setEnabled(initial ?? false);
    } on MissingPluginException catch (error) {
      debugPrint('Power-save mode channel unavailable: $error');
    } on PlatformException catch (error) {
      debugPrint('Unable to query power-save mode: $error');
    }

    _subscription ??= _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is bool) _setEnabled(event);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Unable to observe power-save mode: $error');
      },
    );
  }

  static void _setEnabled(bool value) {
    if (enabled.value == value) return;
    enabled.value = value;
  }
}
