import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:extera_next/config/app_config.dart';
import 'package:extera_next/utils/client_manager.dart';
import 'package:extera_next/utils/notification_background_handler.dart';
import 'package:extera_next/utils/noto_emoji_font.dart';
import 'package:extera_next/utils/platform_infos.dart';
import 'package:extera_next/utils/wallpaper.dart';
import 'package:extera_next/widgets/error_widget.dart';

import 'config/app_settings.dart';
import 'utils/background_push.dart';
import 'widgets/fluffy_chat_app.dart';

ReceivePort? mainIsolateReceivePort;

void main() async {
  Logs().i('Welcome to ${AppConfig.applicationName}! Wonderhoy!!');

  if (PlatformInfos.isAndroid) {
    final port = mainIsolateReceivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(AppConfig.mainIsolatePortName);
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      AppConfig.mainIsolatePortName,
    );
    await waitForPushIsolateDone();
  }

  // Our background push shared isolate accesses flutter-internal things very early in the startup proccess
  // To make sure that the parts of flutter needed are started up already, we need to ensure that the
  // widget bindings are initialized already.
  WidgetsFlutterBinding.ensureInitialized();

  if (PlatformInfos.isWeb) {
    // Disable the native browser context menu so that our own right click
    // handlers (message context menu, image viewer, ...) can take over.
    await BrowserContextMenu.disableContextMenu();
  }

  // IndexedDB/config loading and the vodozemac WebAssembly download are
  // independent. Start both before parsing timezone data so browser I/O can
  // overlap the remaining synchronous startup work.
  final storeFuture = AppSettings.init();
  final vodozemacFuture = vod.init(wasmPath: './assets/assets/vodozemac/');

  if (!PlatformInfos.isWeb) {
    FlutterForegroundTask.initCommunicationPort();
  }

  Logs().nativeColors = !PlatformInfos.isIOS;

  final store = await storeFuture;

  // The 10.7 MB emoji font is no longer engine-preloaded via
  // FontManifest.json; only fetch it when the fallback setting is on.
  if (AppSettings.notoEmojiFont.value) {
    unawaited(ensureNotoEmojiFontLoaded());
  }

  // Client construction only opens IndexedDB and reads the session, while
  // the vodozemac download and wallpaper load are independent I/O — run
  // them concurrently instead of serializing startup behind each other.
  // Initialization itself (which unpickles the Olm account) must wait for
  // vodozemac, so it runs once both have finished.
  final clientsFuture = ClientManager.getClients(
    store: store,
    initialize: false,
  );
  final warmupFuture = Future.wait([vodozemacFuture, initWallpaper()]);

  final clients = await clientsFuture;
  await warmupFuture;
  await ClientManager.initializeClients(clients, store: store);

  // If the app starts in detached mode, we assume that it is in
  // background fetch mode for processing push notifications. This is
  // currently only supported on Android.
  if (PlatformInfos.isAndroid &&
      AppLifecycleState.detached == WidgetsBinding.instance.lifecycleState) {
    // Do not send online presences when app is in background fetch mode.
    for (final client in clients) {
      client.backgroundSync = false;
      client.syncPresence = PresenceType.offline;
    }

    // In the background fetch mode we do not want to waste ressources with
    // starting the Flutter engine but process incoming push notifications.
    BackgroundPush.clientOnly(clients.first);
    // To start the flutter engine afterwards we add an custom observer.
    WidgetsBinding.instance.addObserver(AppStarter(clients, store));
    Logs().i(
      '${AppConfig.applicationName} started in background-fetch mode. No GUI will be created unless the app is no longer detached.',
    );
    return;
  }

  for (final client in clients) {
    client.syncPresence = PresenceType.values.firstWhere(
      (x) => x.name == AppSettings.presenceStatus.value,
    );
  }

  // Started in foreground mode.
  Logs().i(
    '${AppConfig.applicationName} started in foreground mode. Rendering GUI...',
  );
  await startGui(clients, store);
}

/// Fetch the pincode for the applock and start the flutter engine.
Future<void> startGui(List<Client> clients, SharedPreferences store) async {
  // The PIN read, room loading and account-data loading are independent:
  // overlap them instead of paying the sum of all three at startup.
  var pinFuture = Future.value();
  if (PlatformInfos.isMobile) {
    pinFuture = const FlutterSecureStorage()
        .read(key: SettingKeys.appLockKey)
        .catchError((Object e, StackTrace s) {
          Logs().d('Unable to read PIN from Secure storage', e, s);
          return null;
        });
  }

  // Preload first client
  final firstClient = clients.firstOrNull;
  Logs().i("Loading rooms...");
  await Future.wait([
    ?firstClient?.roomsLoading,
    ?firstClient?.accountDataLoading,
    pinFuture,
  ]);
  final pin = await pinFuture;

  ErrorWidget.builder = (details) => FluffyChatErrorWidget(details);
  Logs().i('${clients.length} clients');

  // Runs in the background: it has to wait for every client to have loaded its
  // rooms, which must not hold up the GUI.
  unawaited(pruneWallpapersOfLeftRooms(clients));

  runApp(FluffyChatApp(clients: clients, pincode: pin, store: store));
}

/// Watches the lifecycle changes to start the application when it
/// is no longer detached.
class AppStarter with WidgetsBindingObserver {
  final List<Client> clients;
  final SharedPreferences store;
  bool guiStarted = false;

  AppStarter(this.clients, this.store);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (guiStarted) return;
    if (state == AppLifecycleState.detached) return;

    Logs().i(
      '${AppConfig.applicationName} switches from the detached background-fetch mode to ${state.name} mode. Rendering GUI...',
    );
    // Switching to foreground mode needs to reenable send online sync presence.
    for (final client in clients) {
      client.backgroundSync = true;
      client.syncPresence = PresenceType.values.firstWhere(
        (x) => x.name == AppSettings.presenceStatus.value,
      );
    }
    startGui(clients, store);
    // We must make sure that the GUI is only started once.
    guiStarted = true;
  }
}
