import 'dart:typed_data';

/// The handful of browser APIs this app needs.
///
/// Kept behind a conditional import rather than `universal_html`, which pulls
/// in `dart:html` and therefore cannot be compiled to WebAssembly.
///
/// Every function is a no-op outside of the browser; the call sites are all
/// guarded by a platform check already.
/// Asks the browser not to evict the database under storage pressure.
void requestPersistentStorage() {}

/// Saves [bytes] to the user's downloads.
void downloadBytes(Uint8List bytes, {required String name, String? mimeType}) {}

/// Creates a browser object URL for [bytes].
Uri? createObjectUrl(Uint8List bytes, {String? mimeType}) => null;

/// Releases a browser object URL previously returned by [createObjectUrl].
void revokeObjectUrl(Uri url) {}

/// The URL of the page the app is running in, without query and fragment.
Uri? currentPageUrl() => null;

/// Asks for permission to show browser notifications.
void requestNotificationPermission() {}

/// Shows a browser notification.
void showBrowserNotification(
  String title, {
  String? body,
  String? icon,
  String? tag,
}) {}

/// Plays the notification sound bundled with the app.
void playNotificationSound() {}
