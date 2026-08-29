import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:extera_next/pages/chat_list/chat_list_body.dart';
import 'package:extera_next/pages/intro/intro_page.dart';
import 'package:extera_next/pages/login/login_view.dart';

import '../users.dart';
import 'wait_for.dart';

extension DefaultFlowExtensions on WidgetTester {
  Future<void> login() async {
    final tester = this;

    await tester.pumpAndSettle();

    // The current onboarding starts on IntroPage. Use the direct Matrix ID
    // flow so the integration test can still target its local homeserver.
    if (find.byType(IntroPage).evaluate().isNotEmpty) {
      await tester.tap(find.text('Login with Matrix ID'));
      await tester.pumpAndSettle();
    }

    await tester.waitFor(find.byType(LoginView));
    final inputs = find.byType(TextField);
    expect(inputs, findsNWidgets(2));

    final homeserverAuthority = Uri.parse(homeserver).authority;
    await tester.enterText(
      inputs.first,
      '@${Users.user1.name}:$homeserverAuthority',
    );
    await tester.enterText(inputs.last, Users.user1.password);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.go);

    try {
      // pumpAndSettle does not work in here as setState is called
      // asynchronously
      await tester.waitFor(
        find.byType(LinearProgressIndicator),
        timeout: const Duration(milliseconds: 1500),
        skipPumpAndSettle: true,
      );
    } catch (_) {
      // in case the input action does not work on the desired platform
      if (find.text('Login').evaluate().isNotEmpty) {
        await tester.tap(find.text('Login'));
      }
    }

    try {
      await tester.pumpAndSettle();
    } catch (_) {
      // may fail because of ongoing animation below dialog
    }

    await tester.waitFor(
      find.byType(ChatListViewBody),
      skipPumpAndSettle: true,
    );
  }

  /// ensure PushProvider check passes
  Future<void> acceptPushWarning() async {
    final tester = this;

    final matcher = find.maybeUppercaseText('Do not show again');

    try {
      await tester.waitFor(matcher, timeout: const Duration(seconds: 5));

      // the FCM push error dialog to be handled...
      await tester.tap(matcher);
      await tester.pumpAndSettle();
    } catch (_) {}
  }

  Future<void> ensureLoggedOut() async {
    final tester = this;
    await tester.pumpAndSettle();
    if (find.byType(ChatListViewBody).evaluate().isNotEmpty) {
      await tester.tap(find.byTooltip('Show menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Account'),
        500,
        scrollable: find.descendant(
          of: find.byKey(const Key('SettingsListViewContent')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();
      await tester.tap(find.maybeUppercaseText('Yes'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> ensureAppStartedHomescreen({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final tester = this;
    await tester.pumpAndSettle();

    final introFinder = find.byType(IntroPage);
    final loginFinder = find.byType(LoginView);
    final chatListFinder = find.byType(ChatListViewBody);

    final end = DateTime.now().add(timeout);

    log(
      'Waiting for IntroPage, LoginView or ChatListViewBody...',
      name: 'Test Runner',
    );
    do {
      if (DateTime.now().isAfter(end)) {
        throw Exception(
          'Timed out waiting for IntroPage, LoginView or ChatListViewBody',
        );
      }

      await pumpAndSettle();
      await Future.delayed(const Duration(milliseconds: 100));
    } while (introFinder.evaluate().isEmpty &&
        loginFinder.evaluate().isEmpty &&
        chatListFinder.evaluate().isEmpty);

    if (introFinder.evaluate().isNotEmpty ||
        loginFinder.evaluate().isNotEmpty) {
      log('Found logged-out UI, performing login.', name: 'Test Runner');
      await tester.login();
    } else {
      log('Found ChatListViewBody, skipping login.', name: 'Test Runner');
    }

    await tester.acceptPushWarning();
  }
}
