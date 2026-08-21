import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/widgets/message_selection_area.dart';

void main() {
  testWidgets('keeps the message context menu after a text right click', (
    tester,
  ) async {
    final menuKey = GlobalKey();
    var callbackCalled = false;
    ContextMenuController? menuController;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MessageSelectionArea(
              onSecondaryTap: (position) {
                callbackCalled = true;
                menuController?.remove();
                menuController = ContextMenuController();
                menuController!.show(
                  context: tester.element(find.text('message')),
                  contextMenuBuilder: (_) =>
                      Material(key: menuKey, child: const Text('Reply')),
                );
              },
              child: const Text('message'),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('message')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.pump();

    expect(callbackCalled, isTrue);
    expect(menuController?.isShown, isTrue);
    expect(find.byKey(menuKey), findsOneWidget);

    await gesture.up();
    menuController?.remove();
    await tester.pump();
  });
}
