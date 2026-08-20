import 'dart:typed_data';

/// Persists chat wallpaper bytes outside of the settings store.
///
/// Only implemented on web, where the settings store is backed by local
/// storage and far too small for an image. Native platforms write the
/// wallpaper to a file instead.
///
/// [storageKey] is the empty string for the global wallpaper and the room id
/// for a room specific one.
Future<void> saveWallpaperBytes(String storageKey, Uint8List bytes) async {}

/// Reads the bytes persisted by [saveWallpaperBytes].
Future<Uint8List?> loadWallpaperBytes(String storageKey) async => null;

/// Removes the bytes persisted by [saveWallpaperBytes].
Future<void> deleteWallpaperBytes(String storageKey) async {}
