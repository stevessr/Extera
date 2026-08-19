import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:matrix/matrix.dart';

import 'package:extera_next/config/app_settings.dart';
import 'package:extera_next/utils/wallpaper_store/wallpaper_store.dart';

/// Value stored in [AppSettings.wallpaperPath] on web.
///
/// The image itself lives in IndexedDB, the setting only records that one is
/// set. On native platforms the setting holds the path of the wallpaper file.
const String wallpaperIndexedDbMarker = 'indexeddb:wallpaper';

/// Maximum edge length of a stored wallpaper.
const int wallpaperMaxDimension = 1920;

/// JPEG quality used when storing a wallpaper.
const int wallpaperJpegQuality = 85;

/// In-memory copy of the wallpaper on web, so that [wallpaperImageProvider]
/// can stay synchronous and be called from `build`.
Uint8List? _wallpaperBytes;

/// Loads the web wallpaper into memory. Call once during startup.
///
/// Also migrates wallpapers of older versions, which were stored inline in the
/// settings as a base64 data URL, into IndexedDB.
Future<void> initWallpaper() async {
  if (!kIsWeb) return;

  final value = AppSettings.wallpaperPath.value;
  if (value.isEmpty) return;

  try {
    if (value.startsWith('data:')) {
      final bytes = _decodeDataUrl(value);
      if (bytes == null) {
        await AppSettings.wallpaperPath.setItem('');
        return;
      }
      await saveWallpaperBytes(bytes);
      await AppSettings.wallpaperPath.setItem(wallpaperIndexedDbMarker);
      _wallpaperBytes = bytes;
      return;
    }

    _wallpaperBytes = await loadWallpaperBytes();
    if (_wallpaperBytes == null) {
      // The setting points at something we cannot restore, e.g. a file path
      // from a native installation of a synced account.
      await AppSettings.wallpaperPath.setItem('');
    }
  } catch (e, s) {
    Logs().w('Unable to load the chat wallpaper', e, s);
  }
}

/// Stores [bytes] as the wallpaper and returns the value to persist in
/// [AppSettings.wallpaperPath]. Web only.
Future<String> setWebWallpaperBytes(Uint8List bytes) async {
  await saveWallpaperBytes(bytes);
  _wallpaperBytes = bytes;
  return wallpaperIndexedDbMarker;
}

/// Drops the wallpaper stored by [setWebWallpaperBytes]. Web only.
Future<void> clearWebWallpaperBytes() async {
  _wallpaperBytes = null;
  try {
    await deleteWallpaperBytes();
  } catch (e, s) {
    Logs().w('Unable to delete the chat wallpaper', e, s);
  }
}

Uint8List? _decodeDataUrl(String value) {
  final separator = value.indexOf(',');
  if (separator == -1) return null;
  try {
    return base64Decode(value.substring(separator + 1));
  } catch (_) {
    return null;
  }
}

/// Resolves the persisted wallpaper value into an [ImageProvider].
///
/// [value] is either a file path (native platforms) or [wallpaperIndexedDbMarker]
/// (web). Returns `null` when no wallpaper is set or it cannot be used on the
/// current platform.
ImageProvider? wallpaperImageProvider(String? value) {
  if (value == null || value.isEmpty) return null;

  if (kIsWeb) {
    final bytes = _wallpaperBytes;
    if (bytes != null) return MemoryImage(bytes);
    // Not migrated yet, e.g. when `initWallpaper` has not run.
    if (value.startsWith('data:')) {
      final decoded = _decodeDataUrl(value);
      if (decoded != null) return MemoryImage(decoded);
    }
    return null;
  }

  // A marker or data URL is meaningless on native platforms.
  if (value.startsWith('data:') || value == wallpaperIndexedDbMarker) {
    return null;
  }
  return FileImage(File(value));
}
