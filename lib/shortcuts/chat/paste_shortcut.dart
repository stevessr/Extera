import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/web_paste/web_paste.dart';

class PasteIntent extends Intent {
  const PasteIntent();
}

class ChatPasteShortcut extends StatefulWidget {
  /// Called when the user requested a paste but we have to read the clipboard
  /// ourselves (desktop and mobile).
  final void Function() onPaste;

  /// Called with the decoded image bytes when the platform hands us the
  /// clipboard content directly (web).
  final void Function(Uint8List bytes, String mimeType)? onPasteImage;

  final Widget child;

  const ChatPasteShortcut({
    required this.onPaste,
    required this.child,
    this.onPasteImage,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => ChatPasteShortcutState();
}

class ChatPasteShortcutState extends State<ChatPasteShortcut> {
  bool _usesFlutterKeyboardHandler = false;
  void Function()? _disposeWebPasteListener;

  final HotKey pasteKey = HotKey(
    key: LogicalKeyboardKey.keyV,
    modifiers: [HotKeyModifier.control],
    scope: HotKeyScope.inapp,
  );

  @override
  void initState() {
    super.initState();

    if (PlatformInfos.isWeb) {
      // On web we cannot read the clipboard from a keyboard shortcut: browsers
      // only expose the clipboard content inside the `paste` event itself.
      // That event also covers Cmd+V on macOS and the browser context menu.
      _disposeWebPasteListener = registerWebPasteListener((bytes, mimeType) {
        widget.onPasteImage?.call(bytes, mimeType);
      });
      return;
    }

    if (!PlatformInfos.isDesktop) {
      // hotkey_manager has no mobile implementation. This is an in-app
      // shortcut, so Flutter's keyboard API is sufficient here.
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
      _usesFlutterKeyboardHandler = true;
      return;
    }

    hotKeyManager.register(
      pasteKey,
      keyDownHandler: (hotKey) {
        widget.onPaste();
      },
    );
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isControlPressed) {
      widget.onPaste();
    }
    // Never claim the event: the text field still has to receive a plain text
    // paste.
    return false;
  }

  @override
  void dispose() {
    _disposeWebPasteListener?.call();
    if (_usesFlutterKeyboardHandler) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    } else if (PlatformInfos.isDesktop) {
      hotKeyManager.unregister(pasteKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
