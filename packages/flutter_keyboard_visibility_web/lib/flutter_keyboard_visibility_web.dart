import 'package:flutter_keyboard_visibility_platform_interface/flutter_keyboard_visibility_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// The web implementation of [FlutterKeyboardVisibilityPlatform].
///
/// Reimplemented locally because the published package imports `dart:html`,
/// which dart2wasm cannot compile. The upstream implementation only used that
/// import for an unused `Navigator` constructor argument - the browser has no
/// soft keyboard visibility API, so the platform reports "never visible"
/// either way.
class FlutterKeyboardVisibilityPlugin extends FlutterKeyboardVisibilityPlatform {
  static void registerWith(Registrar registrar) {
    FlutterKeyboardVisibilityPlatform.instance =
        FlutterKeyboardVisibilityPlugin();
  }

  /// The web has no way to tell whether a soft keyboard is up, so this matches
  /// the upstream behaviour and reports that it never is.
  @override
  Stream<bool> get onChange async* {
    yield false;
  }
}
