import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:extera_next/utils/platform_infos.dart';

class PasteIntent extends Intent {
  const PasteIntent();
}

class ChatPasteShortcut extends StatefulWidget {
  final void Function() onPaste;
  final Widget child;

  const ChatPasteShortcut({
    required this.onPaste,
    required this.child,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => ChatPasteShortcutState();
}

class ChatPasteShortcutState extends State<ChatPasteShortcut> {
  bool _usesFlutterKeyboardHandler = false;

  final HotKey pasteKey = HotKey(
    key: LogicalKeyboardKey.keyV,
    modifiers: [HotKeyModifier.control],
    scope: HotKeyScope.inapp,
  );

  @override
  void initState() {
    super.initState();
    if (!PlatformInfos.isDesktop) {
      // hotkey_manager has no web/mobile implementation. This is an in-app
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
      return true;
    }
    return false;
  }

  @override
  void dispose() {
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
