import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Prefix used when the wallpaper is stored inline instead of as a file path.
const String wallpaperDataUrlPrefix = 'data:image/jpeg;base64,';

/// Maximum edge length of a stored wallpaper.
///
/// On web the wallpaper has to live inside the settings store (local storage),
/// so we keep it noticeably smaller there.
int get wallpaperMaxDimension => kIsWeb ? 1280 : 1920;

/// JPEG quality used when storing a wallpaper.
int get wallpaperJpegQuality => kIsWeb ? 75 : 85;

/// Encodes [bytes] into a value that can be persisted in the settings store on
/// platforms without a writable file system (web).
String encodeWallpaperDataUrl(Uint8List bytes) =>
    '$wallpaperDataUrlPrefix${base64Encode(bytes)}';

/// Resolves the persisted wallpaper value into an [ImageProvider].
///
/// [value] is either a file path (native platforms) or a data URL (web).
/// Returns `null` when no wallpaper is set or the value cannot be used on the
/// current platform.
ImageProvider? wallpaperImageProvider(String? value) {
  if (value == null || value.isEmpty) return null;

  if (value.startsWith('data:')) {
    final separator = value.indexOf(',');
    if (separator == -1) return null;
    try {
      return MemoryImage(base64Decode(value.substring(separator + 1)));
    } catch (_) {
      return null;
    }
  }

  // A plain file path is meaningless on web.
  if (kIsWeb) return null;
  return FileImage(File(value));
}
