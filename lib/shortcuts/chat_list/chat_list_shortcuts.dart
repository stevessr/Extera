import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:extera_next/utils/platform_infos.dart';

class NextChatIntent extends Intent {
  const NextChatIntent();
}

class PreviousChatIntent extends Intent {
  const PreviousChatIntent();
}

class ChatListShortcuts extends StatefulWidget {
  final void Function() onPreviousChat;
  final void Function() onNextChat;
  final Widget child;

  const ChatListShortcuts({
    required this.onPreviousChat,
    required this.onNextChat,
    required this.child,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => ChatListShortcutsState();
}

class ChatListShortcutsState extends State<ChatListShortcuts> {
  bool _usesFlutterKeyboardHandler = false;

  final HotKey prevChatKey = HotKey(
    key: LogicalKeyboardKey.arrowUp,
    modifiers: [HotKeyModifier.alt],
    scope: HotKeyScope.inapp,
  );

  final HotKey nextChatKey = HotKey(
    key: LogicalKeyboardKey.arrowDown,
    modifiers: [HotKeyModifier.alt],
    scope: HotKeyScope.inapp,
  );

  @override
  void initState() {
    super.initState();
    if (!PlatformInfos.isDesktop) {
      // hotkey_manager has no web/mobile implementation. The shortcuts are
      // in-app shortcuts, so Flutter's keyboard API is sufficient here.
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
      _usesFlutterKeyboardHandler = true;
      return;
    }

    hotKeyManager.register(
      prevChatKey,
      keyDownHandler: (hotKey) {
        widget.onPreviousChat();
      },
    );
    hotKeyManager.register(
      nextChatKey,
      keyDownHandler: (hotKey) {
        widget.onNextChat();
      },
    );
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || !HardwareKeyboard.instance.isAltPressed) {
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onPreviousChat();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.onNextChat();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    if (_usesFlutterKeyboardHandler) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    } else if (PlatformInfos.isDesktop) {
      hotKeyManager.unregister(prevChatKey);
      hotKeyManager.unregister(nextChatKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
