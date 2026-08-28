import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Asks the browser not to evict the database under storage pressure.
void requestPersistentStorage() {
  web.window.navigator.storage.persist();
}

/// Saves [bytes] to the user's downloads.
void downloadBytes(Uint8List bytes, {required String name, String? mimeType}) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType ?? 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);

  (web.document.createElement('a') as web.HTMLAnchorElement)
    ..href = url
    ..download = name
    ..click();

  // The blob stays alive for as long as the URL does, so hand it back once the
  // download has started.
  web.URL.revokeObjectURL(url);
}

/// Creates a browser object URL for [bytes].
Uri? createObjectUrl(Uint8List bytes, {String? mimeType}) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType ?? 'application/octet-stream'),
  );
  return Uri.parse(web.URL.createObjectURL(blob));
}

/// Releases a browser object URL previously returned by [createObjectUrl].
void revokeObjectUrl(Uri url) {
  web.URL.revokeObjectURL(url.toString());
}

/// The URL of the page the app is running in, without query and fragment.
Uri? currentPageUrl() =>
    Uri.parse(web.window.location.href.split('#').first.split('?').first);

/// Asks for permission to show browser notifications.
void requestNotificationPermission() {
  web.Notification.requestPermission();
}

/// Shows a browser notification.
void showBrowserNotification(
  String title, {
  String? body,
  String? icon,
  String? tag,
}) {
  web.Notification(
    title,
    web.NotificationOptions(
      body: body ?? '',
      icon: icon ?? '',
      tag: tag ?? '',
    ),
  );
}

web.HTMLAudioElement? _audioPlayer;

/// Plays the notification sound bundled with the app.
void playNotificationSound() {
  final player =
      _audioPlayer ??=
          (web.document.createElement('audio') as web.HTMLAudioElement)
            ..src = 'assets/assets/sounds/notification.ogg'
            ..load();
  player.play();
}
