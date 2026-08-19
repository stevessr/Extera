import 'dart:typed_data';

/// Persists the chat wallpaper bytes outside of the settings store.
///
/// Only implemented on web, where the settings store is backed by local
/// storage and far too small for an image. Native platforms write the
/// wallpaper to a file instead.
Future<void> saveWallpaperBytes(Uint8List bytes) async {}

/// Reads the wallpaper bytes persisted by [saveWallpaperBytes].
Future<Uint8List?> loadWallpaperBytes() async => null;

/// Removes the persisted wallpaper bytes.
Future<void> deleteWallpaperBytes() async {}
